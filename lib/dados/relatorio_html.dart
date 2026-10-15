// Relatório financeiro em página para imprimir ou salvar em PDF
// (para mandar ao contador ou ao banco).
import 'db.dart';
import 'financeiro.dart';
import 'negocio.dart';

const _meses = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

String _reais(double v) {
  final partes = v.abs().toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${v < 0 ? '−' : ''}R\$ $inteiro,${partes[1]}';
}

String _esc(Object? v) =>
    '${v ?? ''}'.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _var(double atual, double anterior) {
  if (anterior == 0) return '';
  final v = (atual - anterior) / anterior.abs() * 100;
  return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)}%';
}

String htmlRelatorioFinanceiro(int ano, String hoje) {
  final r = relatorioFinanceiro(ano), a = relatorioFinanceiro(ano - 1);
  final p = PosicaoFinanceira(hoje);
  final g = resumoGado(ano);
  final prop = _esc(Db.registro('propriedades', Db.pid)?['nome']);
  final cpf = _esc(dadosLcdpr()['cpf']);
  String cls(double v) => v < 0 ? ' class="neg"' : '';
  String linhas(Map<String, double> m) =>
      m.entries.map((e) => '<tr><td>${_esc(e.key)}</td><td class="n">${_reais(e.value)}</td></tr>').join();
  final pm = r.porMes, pa = a.porMes;
  final mes = StringBuffer();
  for (var i = 0; i < 12; i++) {
    if (pm[i].$1 == 0 && pm[i].$2 == 0 && pa[i].$1 == 0 && pa[i].$2 == 0) continue;
    final res = pm[i].$1 - pm[i].$2, resA = pa[i].$1 - pa[i].$2;
    mes.write('<tr><td>${_meses[i]}</td><td class="n">${_reais(pm[i].$1)}</td><td class="n">${_reais(pm[i].$2)}</td>'
        '<td class="n"${cls(res)}>${_reais(res)}</td><td class="n muted">${_reais(resA)}</td></tr>');
  }
  final d = hoje.length >= 10 ? '${hoje.substring(8, 10)}/${hoje.substring(5, 7)}/${hoje.substring(0, 4)}' : hoje;
  return '''<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<title>Relatório financeiro $ano · $prop</title>
<style>
@page{size:A4;margin:16mm}
body{font-family:-apple-system,"Segoe UI",Roboto,Arial,sans-serif;color:#18201B;font-size:12px;margin:0}
h1{font-size:20px;margin:0 0 2px}h2{font-size:14px;margin:18px 0 6px;text-transform:uppercase;letter-spacing:.04em;color:#2F6A40}
.sub{color:#5A675F;margin-bottom:12px}
.kpis{display:flex;gap:8px}.kpi{flex:1;border:1px solid #CDD5C8;border-radius:6px;padding:8px 10px}
.kpi b{display:block;font-size:16px;margin-top:2px}.kpi span{color:#5A675F;font-size:11px}
table{width:100%;border-collapse:collapse;margin-top:4px}td,th{padding:4px 6px;border-bottom:1px solid #E3E8DE;text-align:left}
th{background:#EEF1EA;font-size:11px;color:#5A675F}.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.neg{color:#AE3A2C}.muted{color:#5A675F}.cols{display:flex;gap:16px}.cols>div{flex:1}
.rod{margin-top:20px;color:#5A675F;font-size:10px}
</style></head><body>
<h1>Relatório financeiro $ano</h1>
<div class="sub">$prop${cpf.isEmpty ? '' : ' · CPF $cpf'} · emitido em $d pelo Eito</div>
<div class="kpis">
<div class="kpi"><span>Receitas</span><b>${_reais(r.receitas)}</b><span>Em ${ano - 1}: ${_reais(a.receitas)} ${_var(r.receitas, a.receitas)}</span></div>
<div class="kpi"><span>Despesas</span><b>${_reais(r.despesas)}</b><span>Em ${ano - 1}: ${_reais(a.despesas)} ${_var(r.despesas, a.despesas)}</span></div>
<div class="kpi"><span>Resultado</span><b${cls(r.resultado)}>${_reais(r.resultado)}</b><span>Em ${ano - 1}: ${_reais(a.resultado)} ${_var(r.resultado, a.resultado)}</span></div>
</div>
<div class="cols">
<div><h2>Receitas por categoria</h2><table>${linhas(r.receitasPorCategoria)}</table></div>
<div><h2>Despesas por categoria</h2><table>${linhas(r.despesasPorCategoria)}</table></div>
</div>
<h2>Mês a mês</h2>
<table><tr><th>Mês</th><th class="n">Receitas</th><th class="n">Despesas</th><th class="n">Resultado</th><th class="n">Resultado ${ano - 1}</th></tr>$mes</table>
${g.cabecasCompradas > 0 || g.cabecasVendidas > 0 ? '''<h2>Compra e venda de gado</h2><table>
<tr><td>Compras · ${g.cabecasCompradas} cab.</td><td class="n">${_reais(g.totalCompras)}</td></tr>
<tr><td>Vendas (líquido) · ${g.cabecasVendidas} cab.</td><td class="n">${_reais(g.liquidoVendas)}</td></tr>
${g.temLucro ? '<tr><td>Lucro das vendas (custo por cabeça-dia)</td><td class="n"${cls(g.lucroVendas)}>${_reais(g.lucroVendas)}</td></tr>' : ''}
</table>''' : ''}
<h2>Posição em $d</h2><table>
<tr><td>Contas a receber em aberto</td><td class="n">${_reais(p.aReceber)}</td></tr>
<tr><td>Contas a pagar em aberto${p.atrasadas > 0 ? ' (${p.atrasadas} atrasada(s))' : ''}</td><td class="n">${_reais(p.aPagar)}</td></tr>
<tr><td>Saldo devedor das dívidas</td><td class="n">${_reais(p.saldoDividas)}</td></tr>
<tr><td>Dívidas que vencem nos próximos 12 meses</td><td class="n">${_reais(p.parcelas12meses)}</td></tr>
</table>
<div class="rod">Entram as contas pagas no ano e as vendas, compras e custos lançados no rebanho que ainda não viraram conta.</div>
</body></html>''';
}
