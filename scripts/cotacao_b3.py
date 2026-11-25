"""Busca a cotação do boi gordo na B3 (pregão regular) no Notícias Agrícolas
(ou, se ele bloquear, direto na API pública da B3) e grava em mercado/boi_gordo_b3 no Firestore, para o pop-up do app.

Roda no GitHub Actions (.github/workflows/cotacao-b3.yml) com a conta de
serviço do segredo FIREBASE_SERVICE_ACCOUNT. Sem a conta, só mostra o que leu.
"""
import html
import json
import os
import re
import sys
import urllib.request

INDICE = 'https://www.noticiasagricolas.com.br/cotacoes/boi-gordo'
PROJETO = 'caderneta-rebanho'

NUM = re.compile(r'^[+-]?\d{1,3}(?:\.\d{3})*,\d{1,2}$')


def numero(t):
    t = t.strip().replace('%', '').replace(' ', '')
    if not NUM.match(t):
        return None
    return float(t.replace('.', '').replace(',', '.'))


def texto(celula):
    return html.unescape(re.sub(r'<[^>]+>', ' ', celula)).replace('\xa0', ' ').strip()


def ler(pagina):
    """Primeira tabela com linhas "contrato | fechamento | variação" e a data dela."""
    for tabela in re.finditer(r'<table\b.*?</table>', pagina, re.S | re.I):
        linhas = []
        for tr in re.findall(r'<tr\b.*?</tr>', tabela.group(0), re.S | re.I):
            cel = [texto(c) for c in re.findall(r'<td\b[^>]*>(.*?)</td>', tr, re.S | re.I)]
            if len(cel) < 2:
                continue
            fech = numero(cel[1])
            if not cel[0] or fech is None or not 100 <= fech <= 2000:
                continue
            var = numero(cel[2]) if len(cel) > 2 else None
            linhas.append({'contrato': re.sub(r'\s+', ' ', cel[0]), 'fechamento': fech, 'variacao': var})
        if len(linhas) >= 2:
            antes = pagina[max(0, tabela.start() - 3000):tabela.start()]
            datas = re.findall(r'\d{2}/\d{2}/\d{4}', antes) or re.findall(r'\d{2}/\d{2}/\d{4}', tabela.group(0))
            return linhas, (datas[-1] if datas else '')
    return [], ''


def valor(v):
    if v is None:
        return {'nullValue': None}
    if isinstance(v, float):
        return {'doubleValue': v}
    if isinstance(v, list):
        return {'arrayValue': {'values': [valor(x) for x in v]}}
    if isinstance(v, dict):
        return {'mapValue': {'fields': {k: valor(x) for k, x in v.items()}}}
    return {'stringValue': str(v)}


def gravar(dados, conta):
    from google.oauth2 import service_account
    from google.auth.transport.requests import AuthorizedSession

    cred = service_account.Credentials.from_service_account_info(
        conta, scopes=['https://www.googleapis.com/auth/datastore'])
    s = AuthorizedSession(cred)
    url = (f'https://firestore.googleapis.com/v1/projects/{PROJETO}/databases/(default)/documents/'
           'mercado/boi_gordo_b3')
    r = s.patch(url, json={'fields': {k: valor(v) for k, v in dados.items()}})
    if r.status_code >= 300:
        sys.exit(f'Falha ao gravar no Firestore: {r.status_code} {r.text[:500]}')


NAVEGADOR = {
    'User-Agent': ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                   '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'),
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,*/*;q=0.7',
    'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8',
}


def baixar(url):
    req = urllib.request.Request(url, headers=NAVEGADOR)
    return urllib.request.urlopen(req, timeout=60).read().decode('utf-8', 'replace')


# Reserva: a própria B3 publica os futuros do boi (BGI) num JSON aberto.
B3_API = 'https://cotacao.b3.com.br/mds/api/v1/DerivativeQuotation/BGI'
MESES = dict(zip('FGHJKMNQUVXZ', ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
                                   'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez']))


def da_b3():
    """Linhas no mesmo formato do Notícias Agrícolas, lidas da API da B3."""
    bruto = json.loads(baixar(B3_API))
    linhas = []
    for c in bruto.get('Scty') or []:
        simb = str(c.get('symb') or '')
        q = c.get('SctyQtn') or {}
        m = re.fullmatch(r'BGI([FGHJKMNQUVXZ])(\d{2})', simb)
        # Fechamento = último preço do dia; sem negócio, o ajuste da véspera.
        fech = q.get('curPrc') or q.get('prvsDayAdjstmntPric')
        if not m or not fech:
            continue
        fech = float(fech)
        if not 100 <= fech <= 2000:
            continue
        ant = q.get('prvsDayAdjstmntPric')
        var = round((fech / float(ant) - 1) * 100, 2) if ant and fech != float(ant) else (0.0 if ant else None)
        linhas.append({'contrato': f'{MESES[m.group(1)]}/{m.group(2)}', 'fechamento': fech, 'variacao': var,
                       '_ordem': (m.group(2), 'FGHJKMNQUVXZ'.index(m.group(1)))})
    linhas.sort(key=lambda l: l.pop('_ordem'))
    dt = str((bruto.get('Msg') or {}).get('dtTm') or bruto.get('BizSts', {}).get('dtTm') or '')
    d = re.match(r'(\d{4})-(\d{2})-(\d{2})', dt)
    return linhas[:8], (f'{d.group(3)}/{d.group(2)}/{d.group(1)}' if d else '')


def pagina_b3():
    """Acha, no índice do boi gordo, a página do pregão da B3."""
    indice = baixar(INDICE)
    links = sorted(set(re.findall(r'href="((?:https://www\.noticiasagricolas\.com\.br)?/cotacoes/boi-gordo/[^"#?]+)"', indice)))
    print('Páginas do boi gordo:', *links, sep='\n  ')
    b3 = [l for l in links if 'b3' in l.lower() and 'regular' in l.lower()] or [l for l in links if 'b3' in l.lower()]
    for l in b3:
        url = l if l.startswith('http') else 'https://www.noticiasagricolas.com.br' + l
        try:
            return url, baixar(url)
        except Exception as e:  # noqa: BLE001
            print('Falhou', url, e)
    # Sem a página da B3 não grava: a tabela do índice é de outra cotação.
    sys.exit('Não consegui baixar a página da B3; nada gravado.')


def main():
    try:
        url, pagina = pagina_b3()
        linhas, data = ler(pagina)
    except (Exception, SystemExit) as e:  # noqa: BLE001
        print('Notícias Agrícolas falhou:', e)
        url, linhas, data = '', [], ''
    if not linhas:
        url = B3_API
        linhas, data = da_b3()
    if not linhas:
        sys.exit('Não achei a cotação da B3 em nenhuma fonte; nada gravado.')
    dados = {'linhas': linhas, 'atualizado': data, 'fonte': 'B3', 'origem': url}
    print(json.dumps(dados, ensure_ascii=False, indent=1))
    conta = os.environ.get('FIREBASE_SA', '').strip()
    if not conta:
        print('Sem FIREBASE_SERVICE_ACCOUNT: não gravei.')
        return
    gravar(dados, json.loads(conta))
    print('Gravado em mercado/boi_gordo_b3.')


if __name__ == '__main__':
    main()
