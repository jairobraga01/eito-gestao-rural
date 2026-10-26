// Relatório completo da fazenda em página para imprimir ou salvar em PDF
// (para o banco, o contador ou o veterinário).
import 'db.dart';
import 'financeiro.dart';
import 'mapa.dart' show Lotacao;

const _meses = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

String _esc(Object? v) =>
    '${v ?? ''}'.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _reais(double v) {
  final partes = v.abs().toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${v < 0 ? '−' : ''}R\$ $inteiro,${partes[1]}';
}

String _n1(num v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

String _data(String iso) =>
    iso.length >= 10 ? '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}' : iso;

Map<String, int> _contar(List<Reg> animais, String Function(Reg) chave) {
  final c = <String, int>{};
  for (final a in animais) {
    final k = chave(a);
    c[k] = (c[k] ?? 0) + 1;
  }
  return Map.fromEntries(c.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
}

/// [ativos] são os animais ativos da propriedade; [piquetes] vêm de Db.piquetes().
/// O resultado financeiro só entra para o dono da conta.
String htmlRelatorioFazenda({
  required String hoje,
  required List<Reg> ativos,
  required List<Reg> lotes,
  required List<Reg> piquetes,
  required Map<int, Lotacao> lotacao,
  required int prenhes,
  required int partos90,
  required int emCarencia,
  required int aplicacoes30,
}) {
  final f = Db.registro('propriedades', Db.pid) ?? {};
  final nome = _esc(f['nome']);
  String linhas(Map<String, int> m) => m.entries.map((e) => '<tr><td>${_esc(e.key)}</td><td class="n">${e.value}</td></tr>').join();
  final porCategoria = _contar(ativos, (a) => '${a['categoria'] ?? ''}'.trim().isEmpty ? 'Sem categoria' : '${a['categoria']}'.trim());
  final femeas = ativos.where((a) => a['sexo'] == 'F').length;
  // Área digitada ou, sem ela, a do contorno desenhado no mapa (igual à lotação).
  num? areaDe(Reg p) => p['area'] is num ? p['area'] as num : lotacao[p['id']]?.area;
  final areaTotal = piquetes.map(areaDe).whereType<num>().fold<num>(0, (a, b) => a + b);
  final docs = [
    if ('${f['car'] ?? ''}'.isNotEmpty) 'CAR ${_esc(f['car'])}',
    if ('${f['matricula'] ?? ''}'.isNotEmpty) 'Matrícula ${_esc(f['matricula'])}',
    if ('${f['lcdpr_cod_itr'] ?? ''}'.isNotEmpty) 'NIRF/CIB ${_esc(f['lcdpr_cod_itr'])}',
    if ('${f['lcdpr_ie'] ?? ''}'.isNotEmpty) 'IE ${_esc(f['lcdpr_ie'])}',
  ].join(' · ');
  final areas = [
    for (final (k, r) in [
      ('area_pastagem', 'Pastagem'),
      ('area_benfeitoria', 'Benfeitoria'),
      ('area_app', 'Reserva / APP'),
      ('area_agricultura', 'Agricultura'),
    ])
      if (f[k] is num) '$r ${_n1(f[k] as num)} ha',
  ].join(' · ');

  final pq = StringBuffer();
  for (final p in piquetes) {
    final l = lotacao[p['id']];
    pq.write('<tr><td>${_esc(p['nome'])}</td><td class="n">${areaDe(p) == null ? '' : '${_n1(areaDe(p)!)} ha'}</td>'
        '<td>${_esc(p['forrageira'])}</td><td class="n">${p['qtd'] ?? 0}</td>'
        '<td class="n">${l?.uaHa == null ? '' : '${_n1(l!.uaHa!)} UA/ha'}</td></tr>');
  }
  final lt = StringBuffer();
  for (final l in lotes) {
    lt.write('<tr><td>${_esc(l['nome'])}</td><td class="n">${l['qtd'] ?? ''}</td></tr>');
  }

  var financeiro = '';
  if (Db.ehDono) {
    final ano = int.parse(hoje.substring(0, 4));
    final r = relatorioFinanceiro(ano);
    final pm = r.porMes;
    final mes = StringBuffer();
    for (var i = 0; i < 12; i++) {
      if (pm[i].$1 == 0 && pm[i].$2 == 0) continue;
      mes.write('<tr><td>${_meses[i]}</td><td class="n">${_reais(pm[i].$1)}</td><td class="n">${_reais(pm[i].$2)}</td>'
          '<td class="n">${_reais(pm[i].$1 - pm[i].$2)}</td></tr>');
    }
    financeiro = '''<h2>Resultado de $ano</h2>
<table><tr><td>Receitas</td><td class="n">${_reais(r.receitas)}</td></tr>
<tr><td>Despesas</td><td class="n">${_reais(r.despesas)}</td></tr>
<tr><td><b>Resultado</b></td><td class="n"><b>${_reais(r.resultado)}</b></td></tr></table>
<table><tr><th>Mês</th><th class="n">Receitas</th><th class="n">Despesas</th><th class="n">Resultado</th></tr>$mes</table>''';
  }

  return '''<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<title>Relatório da fazenda · $nome</title>
<style>
@page{size:A4;margin:16mm}
body{font-family:-apple-system,"Segoe UI",Roboto,Arial,sans-serif;color:#18201B;font-size:12px;margin:0}
h1{font-size:20px;margin:0 0 2px}h2{font-size:14px;margin:18px 0 6px;text-transform:uppercase;letter-spacing:.04em;color:#2F6A40}
.sub{color:#5A675F;margin-bottom:6px}
.kpis{display:flex;gap:8px;margin-top:10px}.kpi{flex:1;border:1px solid #CDD5C8;border-radius:6px;padding:8px 10px}
.kpi b{display:block;font-size:16px;margin-top:2px}.kpi span{color:#5A675F;font-size:11px}
table{width:100%;border-collapse:collapse;margin-top:4px}td,th{padding:4px 6px;border-bottom:1px solid #E3E8DE;text-align:left}
th{background:#EEF1EA;font-size:11px;color:#5A675F}.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.cols{display:flex;gap:16px}.cols>div{flex:1}.rod{margin-top:20px;color:#5A675F;font-size:10px}
</style></head><body>
<h1>$nome</h1>
<div class="sub">${_esc(f['uf'])}${docs.isEmpty ? '' : ' · $docs'}</div>
<div class="sub">${areas.isEmpty ? '' : '$areas · '}emitido em ${_data(hoje)} pelo Eito</div>
<div class="kpis">
<div class="kpi"><span>Animais ativos</span><b>${ativos.length}</b><span>$femeas fêmeas · ${ativos.length - femeas} machos</span></div>
<div class="kpi"><span>Prenhes</span><b>$prenhes</b><span>$partos90 partos nos próximos 90 dias</span></div>
<div class="kpi"><span>Pastos</span><b>${piquetes.length}</b><span>${areaTotal > 0 ? '${_n1(areaTotal)} ha' : 'sem área informada'}</span></div>
<div class="kpi"><span>Sanidade</span><b>$emCarencia</b><span>em carência · $aplicacoes30 aplicações em 30 dias</span></div>
</div>
<div class="cols">
<div><h2>Rebanho por categoria</h2><table>${linhas(porCategoria)}</table></div>
<div><h2>Lotes</h2><table>${lt.isEmpty ? '<tr><td>Nenhum lote ativo</td></tr>' : lt}</table></div>
</div>
<h2>Pastos e lotação</h2>
<table><tr><th>Piquete</th><th class="n">Área</th><th>Forrageira</th><th class="n">Cab.</th><th class="n">Lotação</th></tr>${pq.isEmpty ? '<tr><td colspan="5">Nenhum piquete cadastrado</td></tr>' : pq}</table>
$financeiro
<div class="rod">Relatório gerado pelo Eito a partir dos lançamentos feitos até hoje.</div>
</body></html>''';
}
