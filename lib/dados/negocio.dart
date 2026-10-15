// Contas da compra e da venda de gado (comissão, nota, frete, Funrural,
// Fundepec) e lucro de cada venda, nas regras da planilha de compra de gado.
import 'db.dart';
import 'gestao.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _num(Object? v) => v is num ? v.toDouble() : null;

/// Compra: subtotal = cabeças × valor por cabeça (ou o valor do lote);
/// total pago = subtotal + comissão do comprador + nota + frete.
class ContaCompra {
  ContaCompra({required this.cabecas, required this.subtotal, this.comissaoPct = 0, this.nota = 0, this.frete = 0});

  final int cabecas;
  final double subtotal, comissaoPct, nota, frete;

  double get comissao => subtotal * comissaoPct / 100;
  double get total => subtotal + comissao + nota + frete;
  double? get media => cabecas > 0 ? total / cabecas : null;
}

/// Venda: bruto por cabeça ou por arroba (peso × rendimento ÷ 15);
/// líquido = bruto − (Funrural + Fundepec + nota + frete + outros).
class ContaVenda {
  ContaVenda({
    required this.cabecas,
    required this.porArroba,
    required this.preco,
    this.pesoTotal,
    this.rendimentoPct = 100,
    this.funruralPct = 0,
    this.fundepec = 0,
    this.nota = 0,
    this.frete = 0,
    this.outros = 0,
  });

  final int cabecas;
  final bool porArroba;

  /// Preço da arroba ou da cabeça.
  final double preco;
  final double? pesoTotal;
  final double rendimentoPct, funruralPct, fundepec, nota, frete, outros;

  double? get arrobas => pesoTotal == null || pesoTotal! <= 0 ? null : pesoTotal! * rendimentoPct / 100 / 15;
  double get bruto => porArroba ? (arrobas ?? 0) * preco : cabecas * preco;
  double get funrural => bruto * funruralPct / 100;
  double get descontos => funrural + fundepec + nota + frete + outros;
  double get liquido => bruto - descontos;
}

/// Últimos percentuais usados (comissão, Funrural, rendimento da venda).
Reg ajustesNegocio() => Db.registro('config', 'negocio') ?? const {};

Future<void> lembrarAjustesNegocio(Reg v) => Db.salvarConfig('negocio', {...ajustesNegocio(), ...v});

double comissaoPadrao() => _num(ajustesNegocio()['comissao_pct']) ?? 2;
double funruralPadrao() => _num(ajustesNegocio()['funrural_pct']) ?? 1.5;
double rendimentoVendaPadrao() => _num(ajustesNegocio()['rendimento_pct']) ?? 100;

/// Custo dos animais de uma venda (custo médio por cabeça do lote de cada um,
/// com compra, custos e sêmen) e o lucro: líquido − custo. Null quando não há
/// custo para comparar.
({double custo, double lucro})? lucroDaVenda(Reg saida) {
  final liquido = _num(saida['valor_total']);
  if (saida['tipo'] != 'Venda' || liquido == null) return null;
  final medias = {
    for (final c in contasPorLote())
      if (c.cabecas > 0) c.loteId: c.custoTotal / c.cabecas,
  };
  var custo = 0.0;
  var algum = false;
  for (final a in Db.registros('animais')) {
    if (_int(a['saida_id']) != _int(saida['id'])) continue;
    final m = medias[_int(a['lote_id'])] ?? medias[null];
    if (m != null && m > 0) {
      custo += m;
      algum = true;
    }
  }
  return algum ? (custo: custo, lucro: liquido - custo) : null;
}

/// Compras e vendas de gado do ano na propriedade aberta, com o lucro das vendas.
class ResumoGado {
  int cabecasCompradas = 0, cabecasVendidas = 0;
  double totalCompras = 0, liquidoVendas = 0, lucroVendas = 0;
  bool temLucro = false;
}

ResumoGado resumoGado(int ano) {
  final r = ResumoGado();
  bool doAno(Reg x) => _int(x['propriedade_id']) == Db.pid && '${x['data'] ?? ''}'.startsWith('$ano-');
  for (final e in Db.registros('entradas')) {
    if (e['tipo'] != 'Compra' || !doAno(e)) continue;
    r.cabecasCompradas += _int(e['quantidade']) ?? 0;
    r.totalCompras += _num(e['valor_total']) ?? 0;
  }
  for (final s in Db.registros('saidas')) {
    if (s['tipo'] != 'Venda' || !doAno(s)) continue;
    r.cabecasVendidas += _int(s['quantidade']) ?? 0;
    r.liquidoVendas += _num(s['valor_total']) ?? 0;
    final l = lucroDaVenda(s);
    if (l != null) {
      r.lucroVendas += l.lucro;
      r.temLucro = true;
    }
  }
  return r;
}
