// Painel do gado no formato do app Gado Guaraí: rebanho, custos, caixa,
// compras, vendas com lucro, saídas, despesas por mês e pesagens.
import 'db.dart';
import 'gestao.dart';
import 'negocio.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _n(Object? v) => v is num ? v.toDouble() : 0;
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);

class CompraPainel {
  CompraPainel(this.entrada, this.n);
  final Reg entrada;
  final int n;

  int get qtd => _int(entrada['quantidade']) ?? 0;
  String get data => _dia(entrada['data']);
  double get total => _n(entrada['valor_total']);
  double get subtotal => entrada['subtotal'] is num ? _n(entrada['subtotal']) : total;
  double get comissaoPct => _n(entrada['comissao_pct']);
  double get comissaoVendPct => _n(entrada['comissao_vend_pct']);
  double get comissao => _n(entrada['comissao']);
  double get nota => _n(entrada['nota']);
  double get frete => _n(entrada['frete']);
  double get media => qtd > 0 ? total / qtd : 0;

  /// Lotes da compra (qtd, valor por cabeça, data), quando vieram do Guaraí.
  List<Map<String, Object?>> get lotes => [
        for (final l in (entrada['lotes'] as List?) ?? const []) Map<String, Object?>.from(l as Map),
      ];
}

class VendaPainel {
  VendaPainel(this.saida, this.custo);
  final Reg saida;
  final double custo;

  int get qtd => _int(saida['quantidade']) ?? 0;
  String get data => _dia(saida['data']);
  double get liquido => _n(saida['valor_total']);
  double get bruto => saida['bruto'] is num ? _n(saida['bruto']) : liquido;
  double get descontos => bruto - liquido;
  double get peso => _n(saida['peso_total']);
  double get arrobas => saida['arrobas'] is num ? _n(saida['arrobas']) : (peso > 0 ? peso / 15 : 0);
  double get lucro => liquido - custo;
  double get margem => custo > 0 ? lucro / custo : 0;
}

/// Filtro do período: tudo, um ano ('2026') ou um mês ('2026-08').
bool noPeriodo(String filtro, String data) => filtro.isEmpty || data.startsWith(filtro);

class PainelGado {
  PainelGado({String? hoje}) {
    final pid = Db.pid;
    final entradas = [
      for (final e in Db.registros('entradas'))
        if (_int(e['propriedade_id']) == pid && e['tipo'] == 'Compra') e,
    ]..sort((a, b) => _dia(a['data']).compareTo(_dia(b['data'])));
    compras = [for (final (i, e) in entradas.indexed) CompraPainel(e, i + 1)];
    final cpa = custoPorAnimal(hoje: hoje);
    final animais = [
      for (final a in Db.registros('animais'))
        if (_int(a['propriedade_id']) == pid) a,
    ];
    final custoSaida = <int?, double>{};
    for (final a in animais) {
      if (a['saida_id'] != null) {
        custoSaida[_int(a['saida_id'])] = (custoSaida[_int(a['saida_id'])] ?? 0) + (cpa[_int(a['id'])] ?? 0);
      }
    }
    final saidas = [
      for (final s in Db.registros('saidas'))
        if (_int(s['propriedade_id']) == pid) s,
    ]..sort((a, b) => _dia(a['data']).compareTo(_dia(b['data'])));
    vendas = [
      for (final s in saidas)
        if (s['tipo'] == 'Venda') VendaPainel(s, custoSaida[_int(s['id'])] ?? 0),
    ];
    outrasSaidas = [for (final s in saidas) if (s['tipo'] != 'Venda') s];
    despesas = [
      for (final c in Db.registros('custos'))
        if (_int(c['propriedade_id']) == pid && c['valor'] is num) c,
    ]..sort((a, b) => _dia(b['data']).compareTo(_dia(a['data'])));
    totalCab = animais.length;
    noPasto = animais.where((a) => a['status'] == 'Ativo').length;
    comprado = compras.fold(0, (s, c) => s + c.qtd);
    outrasEntradas = totalCab - comprado < 0 ? 0 : totalCab - comprado;
    pesagens = _pesagens(animais);
  }

  late final List<CompraPainel> compras;
  late final List<VendaPainel> vendas;
  late final List<Reg> outrasSaidas, despesas;
  late final int totalCab, noPasto, comprado, outrasEntradas;
  late final List<PesagemPainel> pesagens;

  int get vendido => vendas.fold(0, (s, v) => s + v.qtd);
  int get saidasCab => outrasSaidas.fold(0, (s, x) => s + (_int(x['quantidade']) ?? 0));
  double get gastoCompra => compras.fold(0, (s, c) => s + c.total);
  double get custeio => despesas.fold(0, (s, d) => s + _n(d['valor']));
  double get custoTotal => gastoCompra + custeio;
  double get custoCab => totalCab > 0 ? custoTotal / totalCab : 0;
  double get mediaCompra => comprado > 0 ? gastoCompra / comprado : 0;
  double get custeioCab => noPasto > 0 ? custeio / noPasto : 0;
  double get liquidoVendas => vendas.fold(0, (s, v) => s + v.liquido);
  double get brutoVendas => vendas.fold(0, (s, v) => s + v.bruto);
  double get custoVendidas => vendas.fold(0, (s, v) => s + v.custo);
  double get lucro => vendas.fold(0, (s, v) => s + v.lucro);
  double get caixa => liquidoVendas - gastoCompra - custeio;

  /// Resultado de um período ('' = tudo, '2026' ou '2026-08').
  ({int qc, int qv, int qs, double compras, double despesas, double vendas, double lucro, double caixa}) periodo(
      String f) {
    final cs = compras.where((c) => noPeriodo(f, c.data));
    final vs = vendas.where((v) => noPeriodo(f, v.data));
    final ds = despesas.where((d) => noPeriodo(f, _dia(d['data'])));
    final ss = outrasSaidas.where((s) => noPeriodo(f, _dia(s['data'])));
    final gc = cs.fold(0.0, (s, c) => s + c.total), de = ds.fold(0.0, (s, d) => s + _n(d['valor']));
    final en = vs.fold(0.0, (s, v) => s + v.liquido);
    return (
      qc: cs.fold(0, (s, c) => s + c.qtd),
      qv: vs.fold(0, (s, v) => s + v.qtd),
      qs: ss.fold(0, (s, x) => s + (_int(x['quantidade']) ?? 0)),
      compras: gc,
      despesas: de,
      vendas: en,
      lucro: vs.fold(0.0, (s, v) => s + v.lucro),
      caixa: en - gc - de,
    );
  }

  /// Anos e meses com lançamento, do mais novo ao mais velho.
  List<String> get meses => {
        ...compras.map((c) => c.data),
        ...vendas.map((v) => v.data),
        ...despesas.map((d) => _dia(d['data'])),
      }.where((d) => d.length >= 7).map((d) => d.substring(0, 7)).toSet().toList()
        ..sort((a, b) => b.compareTo(a));

  /// Despesas por categoria em cada mês do exercício que começa em [inicio] ('2026-07').
  Map<String, List<double>> despesasExercicio(String inicio) {
    final ms = mesesExercicio(inicio);
    final r = <String, List<double>>{};
    for (final d in despesas) {
      final i = ms.indexOf(_dia(d['data']).length >= 7 ? _dia(d['data']).substring(0, 7) : '');
      if (i < 0) continue;
      final cat = _t(d['categoria']).isEmpty ? 'Outros' : _t(d['categoria']);
      (r[cat] ??= List.filled(12, 0))[i] += _n(d['valor']);
    }
    return r;
  }

  List<PesagemPainel> _pesagens(List<Reg> animais) {
    final (rend, _) = ajustesArroba();
    final lote = {for (final a in animais) _int(a['id']): _int(a['lote_id'])};
    final grupos = <(String, int?), List<double>>{};
    for (final p in Db.registros('pesagens')) {
      final id = _int(p['animal_id']);
      if (!lote.containsKey(id) || p['peso'] is! num) continue;
      grupos.putIfAbsent((_dia(p['data']), lote[id]), () => []).add(_n(p['peso']));
    }
    final chaves = grupos.keys.toList()..sort((a, b) => a.$1.compareTo(b.$1));
    final anterior = <int?, (String, double)>{};
    final r = <PesagemPainel>[];
    for (final k in chaves) {
      final ps = grupos[k]!;
      final medio = ps.fold(0.0, (s, x) => s + x) / ps.length;
      final ant = anterior[k.$2];
      int? dias;
      double? ganho;
      if (ant != null) {
        dias = DateTime.parse(k.$1).difference(DateTime.parse(ant.$1)).inDays;
        ganho = medio - ant.$2;
      }
      anterior[k.$2] = (k.$1, medio);
      r.add(PesagemPainel(k.$1, k.$2, ps.length, ps.fold(0.0, (s, x) => s + x), medio, rend, dias, ganho));
    }
    return r.reversed.toList();
  }
}

class PesagemPainel {
  PesagemPainel(this.data, this.loteId, this.qtd, this.pesoTotal, this.medio, this.rend, this.dias, this.ganho);
  final String data;
  final int? loteId;
  final int qtd;
  final double pesoTotal, medio, rend;
  final int? dias;
  final double? ganho;

  double get arrCab => medio * rend / 15;
  double? get gmd => ganho != null && dias != null && dias! > 0 ? ganho! / dias! : null;
  double? get arrProduzidas => ganho == null ? null : ganho! * rend / 15;
}

/// Os 12 meses ('2026-07' ... '2027-06') do exercício que começa em [inicio].
List<String> mesesExercicio(String inicio) {
  var y = int.parse(inicio.substring(0, 4)), m = int.parse(inicio.substring(5, 7));
  return [
    for (var i = 0; i < 12; i++)
      () {
        final s = '$y-${m.toString().padLeft(2, '0')}';
        if (++m > 12) {
          m = 1;
          y++;
        }
        return s;
      }(),
  ];
}

/// Mês de início do exercício (1 a 12), guardado nos ajustes; janeiro se não houver.
int mesInicioExercicio() => _int(ajustesNegocio()['exercicio_mes']) ?? 1;

/// Exercício que contém [hoje] ('2026-07' quando começa em julho).
String exercicioAtual(String hoje) {
  final m0 = mesInicioExercicio();
  final y = int.parse(hoje.substring(0, 4)), m = int.parse(hoje.substring(5, 7));
  return '${m >= m0 ? y : y - 1}-${m0.toString().padLeft(2, '0')}';
}
