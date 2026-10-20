"""Resumo diário do Painel do criador por e-mail.

Lê contas/ e chamados/ no Firestore e põe um e-mail na fila mail/ para
eitogestaorural@gmail.com: quem se cadastrou nas últimas 24 h, testes que
acabam em até 3 dias, planos vencendo em até 7 dias ou atrasados e chamados
abertos. Quem envia é a extensão "Trigger Email" do Firebase (sem ela
instalada, o e-mail fica só guardado na fila).

Roda no GitHub Actions (.github/workflows/resumo-criador.yml) com a conta de
serviço do segredo FIREBASE_SERVICE_ACCOUNT. Sem a conta, não faz nada.
"""
import datetime as dt
import html
import json
import os
import sys

PROJETO = 'caderneta-rebanho'
PARA = 'eitogestaorural@gmail.com'
BASE = f'https://firestore.googleapis.com/v1/projects/{PROJETO}/databases/(default)/documents'
PAGOS = {'Simples', 'Média', 'Plus', 'Essencial', 'Profissional', 'Completa'}


def ler_valor(v):
    """Valor do formato REST do Firestore para Python."""
    if 'timestampValue' in v:
        return dt.datetime.fromisoformat(v['timestampValue'].replace('Z', '+00:00'))
    if 'integerValue' in v:
        return int(v['integerValue'])
    if 'doubleValue' in v:
        return v['doubleValue']
    if 'mapValue' in v:
        return {k: ler_valor(x) for k, x in v['mapValue'].get('fields', {}).items()}
    if 'arrayValue' in v:
        return [ler_valor(x) for x in v['arrayValue'].get('values', [])]
    for k in ('stringValue', 'booleanValue'):
        if k in v:
            return v[k]
    return None


def valor(v):
    if isinstance(v, dict):
        return {'mapValue': {'fields': {k: valor(x) for k, x in v.items()}}}
    return {'stringValue': str(v)}


def listar(s, colecao):
    docs, token = [], None
    while True:
        r = s.get(f'{BASE}/{colecao}', params={'pageSize': 300, **({'pageToken': token} if token else {})})
        if r.status_code >= 300:
            sys.exit(f'Falha ao ler {colecao}: {r.status_code} {r.text[:300]}')
        j = r.json()
        for d in j.get('documents', []):
            docs.append({'_id': d['name'].rsplit('/', 1)[1],
                         **{k: ler_valor(x) for k, x in d.get('fields', {}).items()}})
        token = j.get('nextPageToken')
        if not token:
            return docs


def resumo(contas, chamados, agora):
    donos = [c for c in contas if c.get('papel', 'dono') == 'dono']

    def quando(c, campo):
        v = c.get(campo)
        return v if isinstance(v, dt.datetime) else None

    novos = [c for c in donos if (quando(c, 'criado_em') or agora - dt.timedelta(days=99)) > agora - dt.timedelta(days=1)]
    testes = [c for c in donos if c.get('plano', 'Teste') == 'Teste' and c.get('status') != 'suspensa'
              and quando(c, 'teste_ate') and quando(c, 'teste_ate') - agora <= dt.timedelta(days=3)]
    planos = [c for c in donos if c.get('plano') in PAGOS and quando(c, 'plano_ate')
              and quando(c, 'plano_ate') - agora <= dt.timedelta(days=7)]
    abertos = [c for c in chamados if c.get('status') != 'fechado']
    return [
        ('Novos cadastros (24 h)', [f"{c.get('email', '')} {c.get('telefone', '')}".strip() for c in novos]),
        ('Testes acabando ou vencidos', [f"{c.get('email', '')} · até {quando(c, 'teste_ate'):%d/%m}" for c in testes]),
        ('Planos vencendo ou atrasados', [f"{c.get('email', '')} · {c.get('plano')} até {quando(c, 'plano_ate'):%d/%m}" for c in planos]),
        ('Chamados abertos', [f"{c.get('assunto', '')} · {c.get('email', '')}" for c in abertos]),
    ]


def texto_e_html(secoes, hoje):
    txt = [f'Resumo do Eito Gestão · {hoje:%d/%m/%Y}', '']
    htm = [f'<h2 style="color:#00602A;font-family:Arial">Resumo do Eito Gestão · {hoje:%d/%m/%Y}</h2>']
    for titulo, itens in secoes:
        txt.append(f'{titulo}: {len(itens)}')
        txt += [f'  • {i}' for i in itens[:30]]
        txt.append('')
        htm.append(f'<h3 style="font-family:Arial">{html.escape(titulo)}: {len(itens)}</h3><ul style="font-family:Arial">')
        htm += [f'<li>{html.escape(i)}</li>' for i in itens[:30]]
        htm.append('</ul>')
    htm.append('<p style="font-family:Arial"><a href="https://eitogestao.com.br">Abrir o Painel do criador</a></p>')
    return '\n'.join(txt), ''.join(htm)


def main():
    conta = os.environ.get('FIREBASE_SA', '').strip()
    if not conta:
        print('Sem FIREBASE_SERVICE_ACCOUNT: nada a fazer.')
        return
    from google.oauth2 import service_account
    from google.auth.transport.requests import AuthorizedSession

    cred = service_account.Credentials.from_service_account_info(
        json.loads(conta), scopes=['https://www.googleapis.com/auth/datastore'])
    s = AuthorizedSession(cred)
    agora = dt.datetime.now(dt.timezone.utc)
    secoes = resumo(listar(s, 'contas'), listar(s, 'chamados'), agora)
    hoje = agora - dt.timedelta(hours=3)
    txt, htm = texto_e_html(secoes, hoje)
    print(txt)
    doc = {'to': PARA, 'message': {'subject': f'Eito · resumo do dia {hoje:%d/%m}', 'text': txt, 'html': htm}}
    r = s.patch(f'{BASE}/mail/resumo-{hoje:%Y-%m-%d}', json={'fields': {k: valor(v) for k, v in doc.items()}})
    if r.status_code >= 300:
        sys.exit(f'Falha ao gravar o e-mail: {r.status_code} {r.text[:300]}')
    print('E-mail na fila mail/.')


if __name__ == '__main__':
    main()
