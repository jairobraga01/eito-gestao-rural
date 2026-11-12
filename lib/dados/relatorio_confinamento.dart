// Relatório do ciclo de confinamento em página para imprimir ou salvar em PDF.
import 'confinamento.dart';
import 'db.dart';

String _esc(Object? v) =>
    '${v ?? ''}'.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _reais(double? v) {
  if (v == null) return '-';
  final partes = v.abs().toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${v < 0 ? '−' : ''}R\$ $inteiro,${partes[1]}';
}

String _n(double? v, [int casas = 1]) => v == null ? '-' : v.toStringAsFixed(casas).replaceAll('.', ',');

String _br(String iso) => iso.length >= 10 ? '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}' : iso;

String htmlRelatorioConfinamento(Ciclo c, String hoje) {
  final r = c.resultado(hoje, naSaida: c.aberto);
  final agora = c.resultado(hoje);
  final prop = _esc(Db.registro('propriedades', Db.pid)?['nome']);
  final saida = c.aberto ? c.saidaPrevista(hoje) : '${c.reg['data_saida'] ?? ''}';
  String kpi(String rotulo, String valor) => '<div class="kpi"><span>$rotulo</span><b>$valor</b></div>';
  String linha(String a, String b) => '<tr><td>$a</td><td class="n">$b</td></tr>';
  final leituras = StringBuffer();
  for (final l in c.leituras.reversed) {
    final nota = l['nota'] is num ? '${l['nota']}' : '-';
    leituras.write('<tr><td>${_br('${l['data']}')}</td><td class="n">$nota</td><td class="n">${l['cabecas'] ?? '-'}</td>'
        '<td class="n">${_n((l['kg_previsto'] as num?)?.toDouble())}</td><td class="n">${_n((l['kg_fornecido'] as num?)?.toDouble())}</td></tr>');
  }
  return '''<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<title>Confinamento ${_esc(c.nome)} · $prop</title>
<style>
@page{size:A4;margin:16mm}
body{font-family:-apple-system,"Segoe UI",Roboto,Arial,sans-serif;color:#18201B;font-size:12px;margin:0}
h1{font-size:20px;margin:0 0 2px}h2{font-size:14px;margin:18px 0 6px;text-transform:uppercase;letter-spacing:.04em;color:#2F6A40}
.sub{color:#5A675F;margin-bottom:12px}
.kpis{display:flex;flex-wrap:wrap;gap:8px}.kpi{flex:1 1 22%;border:1px solid #CDD5C8;border-radius:6px;padding:8px 10px}
.kpi b{display:block;font-size:16px;margin-top:2px}.kpi span{color:#5A675F;font-size:11px}
table{width:100%;border-collapse:collapse;margin-top:4px}td,th{padding:4px 6px;border-bottom:1px solid #E3E8DE;text-align:left}
th{background:#EEF1EA;font-size:11px;color:#5A675F}.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.cols{display:flex;gap:16px}.cols>div{flex:1}.rod{margin-top:20px;color:#5A675F;font-size:10px}
</style></head><body>
<h1>Confinamento · ${_esc(c.nome)}</h1>
<div class="sub">$prop · ${c.lote == null ? 'sem lote' : 'lote ${_esc(c.lote!['nome'])}'} · dieta ${_esc(c.dieta)} · emitido em ${_br(hoje)} pelo Eito</div>
<div class="kpis">
${kpi('Entrada', _br(c.entrada))}
${kpi(c.aberto ? 'Saída prevista' : 'Saída', saida == null || saida.isEmpty ? '-' : _br(saida))}
${kpi('Dias de cocho', '${r.dias}')}
${kpi('Cabeças', '${c.cabecasEntrada} entraram · ${c.cabecas} ${c.aberto ? 'no cocho' : 'saíram'}')}
</div>
<div class="cols"><div>
<h2>Desempenho</h2>
<table>
${linha('Peso de entrada', '${_n(c.pesoEntrada)} kg')}
${linha(c.aberto ? 'Peso na saída prevista' : 'Peso de saída', '${_n(r.peso)} kg')}
${linha('GMD ${c.gmdReal(hoje) ? '(pesagem)' : '(previsto)'}', '${_n(r.gmd, 3)} kg/dia')}
${linha('Consumo de matéria natural', '${_n(c.consumoMN, 2)} kg/cab/dia')}
${linha('Consumo de matéria seca', '${_n(c.consumoMS, 2)} kg/cab/dia')}
${linha('Consumo de MS em % do peso vivo', '${_n(c.consumoPV(hoje), 2)}%')}
${linha('Conversão alimentar', '${_n(c.conversao(hoje), 2)} kg MS/kg')}
${linha('Mortes', '${c.mortes}')}
${linha('Rendimento de carcaça', '${_n(c.rendSaida * 100)}%')}
</table>
</div><div>
<h2>Custos e resultado por cabeça</h2>
<table>
${linha('Diária (ração + operacional)', _reais(c.diaria))}
${linha('Ração fornecida no ciclo (total)', _reais(c.custoAlimentar))}
${linha('Custo do cocho por cabeça', _reais(r.custoCab))}
${linha('Arrobas produzidas', _n(r.arrobasProduzidas, 2))}
${linha('Custo da arroba produzida', _reais(r.custoArroba))}
${linha('Boi magro (compra)', _reais(c.valorCompra))}
${linha('Ponto de equilíbrio', '${_reais(r.equilibrio)}/@')}
${linha('Arroba de venda', r.arroba == null ? '-' : '${_reais(r.arroba)}/@')}
${linha('Receita', _reais(r.receita))}
${linha('Margem por cabeça', _reais(r.margem))}
${linha('Margem do ciclo', r.margem == null ? '-' : _reais(r.margem! * c.cabecas))}
</table>
${c.aberto ? '<p class="sub">Até hoje: ${agora.dias} dias, ${_n(agora.peso)} kg, custo de ${_reais(agora.custoCab)} por cabeça.</p>' : ''}
</div></div>
<h2>Leituras de cocho e tratos</h2>
<table><tr><th>Data</th><th class="n">Nota</th><th class="n">Cabeças</th><th class="n">Previsto (kg)</th><th class="n">Fornecido (kg)</th></tr>
${leituras.isEmpty ? '<tr><td colspan="5">Nenhuma leitura lançada.</td></tr>' : leituras}
</table>
<div class="rod">Nota de cocho: 0 lambido (+10%), 1 limpo (+5%), 2 pouca sobra (mantém), 3 sobra média (−5%), 4 muita sobra (−10%).
Arroba produzida = (peso final × rendimento final − peso inicial × rendimento inicial) ÷ 15.</div>
</body></html>''';
}
