// Contas da compra e da venda de gado (comissão, nota, frete, Funrural,
// Fundepec), lucro de cada venda com custo por cabeça-dia e parcelas a prazo.
import 'db.dart';
import 'dividas.dart';

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

String _dia(Object? v) {
  final t = v == null ? '' : '$v';
  return t.length >= 10 ? t.substring(0, 10) : t;
}

int _dias(String de, String ate) {
  final a = DateTime.tryParse(de), b = DateTime.tryParse(ate);
  if (a == null || b == null) return 1;
  final d = DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  return d < 1 ? 1 : d;
}

String _hojeIso() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Dias que o animal ficou (ou está) na fazenda: da entrada (ou nascimento,
/// ou cadastro) até a saída ou [hoje].
int diasNaFazenda(Reg a, String hoje) {
  final e = Db.registro('entradas', a['entrada_id']);
  final de = [_dia(e?['data']), _dia(a['nascimento']), _dia(a['criado_em'])].firstWhere((x) => x.length == 10,
      orElse: () => hoje);
  final s = Db.registro('saidas', a['saida_id']);
  return _dias(de, s != null && _dia(s['data']).length == 10 ? _dia(s['data']) : hoje);
}

/// Custo de cada animal da propriedade aberta: a compra dele, o sêmen e as
/// despesas divididas por cabeça-dia (as do lote entre os animais do lote,
/// as gerais entre todos), de modo que quem ficou mais tempo leva mais custo.
Map<int, double> custoPorAnimal({String? hoje}) {
  final h = hoje ?? _hojeIso();
  final animais = [
    for (final a in Db.registros('animais'))
      if (_int(a['propriedade_id']) == Db.pid && _int(a['id']) != null) a,
  ];
  final dias = {for (final a in animais) _int(a['id'])!: diasNaFazenda(a, h)};
  final custo = <int, double>{};
  for (final a in animais) {
    final id = _int(a['id'])!;
    final e = Db.registro('entradas', a['entrada_id']);
    final q = _int(e?['quantidade']) ?? 0;
    custo[id] = e != null && e['tipo'] == 'Compra' && q > 0 ? (_num(e['valor_total']) ?? 0) / q : 0;
  }
  for (final r in Db.registros('reproducoes')) {
    final f = _int(r['femea_id']);
    if (custo.containsKey(f) && r['custo_dose'] is num) custo[f!] = custo[f]! + (r['custo_dose'] as num);
  }
  final porLote = <int?, double>{};
  for (final c in Db.registros('custos')) {
    if (_int(c['propriedade_id']) == Db.pid && c['valor'] is num) {
      porLote[_int(c['lote_id'])] = (porLote[_int(c['lote_id'])] ?? 0) + (c['valor'] as num);
    }
  }
  for (final MapEntry(key: lote, value: total) in porLote.entries) {
    var grupo = lote == null ? animais : animais.where((a) => _int(a['lote_id']) == lote).toList();
    if (grupo.isEmpty) grupo = animais; // lote sem animais: entra como custo geral
    final somaDias = grupo.fold<int>(0, (s, a) => s + dias[_int(a['id'])]!);
    if (somaDias == 0) continue;
    for (final a in grupo) {
      final id = _int(a['id'])!;
      custo[id] = custo[id]! + total * dias[id]! / somaDias;
    }
  }
  return custo;
}

/// Custo dos animais de uma venda (compra + despesas por cabeça-dia + sêmen)
/// e o lucro: líquido − custo. Null quando não há custo para comparar.
({double custo, double lucro})? lucroDaVenda(Reg saida, {Map<int, double>? custos, String? hoje}) {
  final liquido = _num(saida['valor_total']);
  if (saida['tipo'] != 'Venda' || liquido == null) return null;
  final cpa = custos ?? custoPorAnimal(hoje: hoje);
  var custo = 0.0;
  for (final a in Db.registros('animais')) {
    if (_int(a['saida_id']) == _int(saida['id'])) custo += cpa[_int(a['id'])] ?? 0;
  }
  return custo > 0 ? (custo: custo, lucro: liquido - custo) : null;
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
  final custos = custoPorAnimal();
  for (final s in Db.registros('saidas')) {
    if (s['tipo'] != 'Venda' || !doAno(s)) continue;
    r.cabecasVendidas += _int(s['quantidade']) ?? 0;
    r.liquidoVendas += _num(s['valor_total']) ?? 0;
    final l = lucroDaVenda(s, custos: custos);
    if (l != null) {
      r.lucroVendas += l.lucro;
      r.temLucro = true;
    }
  }
  return r;
}

// ---------- Venda e compra a prazo ----------

/// Cria as parcelas (em aberto) de uma venda ou compra a prazo nas contas a
/// receber ou a pagar, uma por mês a partir de [primeiro]. A [origem]
/// (saida:id / entrada:id) evita que o "trazer do rebanho" conte de novo.
Future<void> lancarParcelas({
  required bool receita,
  required String origem,
  required double total,
  required int parcelas,
  required String primeiro,
  required String descricao,
  String? participante,
}) async {
  final ps = gerarParcelas(total, parcelas, primeiro, intervaloMeses: 1);
  for (final (i, p) in ps.indexed) {
    await Db.inserir('contas', {
      'propriedade_id': Db.pid,
      'tipo': receita ? 'Receita' : 'Despesa',
      'categoria': receita ? 'Venda de gado' : 'Compra de gado',
      'descricao': ps.length > 1 ? '$descricao (${i + 1}/${ps.length})' : descricao,
      'participante': participante,
      'valor': p['valor'],
      'vencimento': p['vencimento'],
      'pago': false,
      'tipo_doc': 1,
      'origem': origem,
    });
  }
}

/// Apaga as parcelas ainda em aberto de uma venda ou compra excluída.
Future<int> apagarParcelasAbertas(String origem) async {
  var n = 0;
  for (final c in Db.registros('contas')) {
    if ('${c['origem'] ?? ''}' == origem && c['pago'] != true && _int(c['id']) != null) {
      await Db.excluir('contas', _int(c['id'])!);
      n++;
    }
  }
  return n;
}
