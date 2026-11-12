// Modo Confinamento: ciclos de engorda no cocho, como as planilhas de
// confinamento (Embrapa, Scot) e os apps do mercado. Cada ciclo é um curral
// (ou baia) com um lote; a leitura de cocho de cada manhã sugere o trato do
// dia, e o trato fornecido dá baixa no estoque e lança o custo.
//
// Tabelas: confinamentos (o ciclo) e cocho (uma leitura/trato por ciclo e dia).
import 'db.dart';
import 'estoque.dart';
import 'gestao.dart' show ajustesArroba;
import 'proteinado.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', '.'));
double _n(Object? v) => _num(v) ?? 0;
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);

int _dias(String de, String ate) {
  final a = DateTime.parse(de.substring(0, 10)), b = DateTime.parse(ate.substring(0, 10));
  return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

String _somaDias(String iso, int dias) {
  final d = DateTime.parse(iso.substring(0, 10));
  final r = DateTime.utc(d.year, d.month, d.day).add(Duration(days: dias));
  return '${r.year.toString().padLeft(4, '0')}-${r.month.toString().padLeft(2, '0')}-${r.day.toString().padLeft(2, '0')}';
}

String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

/// Escala da leitura de cocho (0 a 4) e o ajuste do trato do dia.
const notasCocho = <int, (String, double)>{
  0: ('Cocho lambido, sem sobra', 0.10),
  1: ('Limpo, só farelos', 0.05),
  2: ('Pouca sobra (até 5%)', 0.0),
  3: ('Sobra média (5 a 25%)', -0.05),
  4: ('Muita sobra (mais de 25%)', -0.10),
};

/// Ajuste do trato pela nota (ex.: +0,10 = 10% a mais).
double ajusteDaNota(int? nota) => notasCocho[nota]?.$2 ?? 0;

String textoAjuste(int? nota) {
  final a = ajusteDaNota(nota);
  if (nota == null) return '';
  if (a == 0) return 'mantém o trato';
  return '${a > 0 ? 'aumenta' : 'reduz'} ${(a.abs() * 100).round()}%';
}

/// Ciclos da propriedade: abertos primeiro, depois pela entrada mais recente.
List<Ciclo> ciclos({bool soAbertos = false}) => [
      for (final c in Db.registros('confinamentos'))
        if (_int(c['propriedade_id']) == Db.pid && (!soAbertos || c['encerrado'] != true)) Ciclo(c),
    ]..sort((a, b) {
        final x = (a.aberto ? 0 : 1).compareTo(b.aberto ? 0 : 1);
        if (x != 0) return x;
        final d = _t(b.reg['data_entrada']).compareTo(_t(a.reg['data_entrada']));
        return d != 0 ? d : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });

/// Um ciclo de confinamento (curral/baia + lote) e as contas dele.
class Ciclo {
  Ciclo(this.reg)
      : lote = Db.registro('lotes', reg['lote_id']),
        formula = Db.registro('formulas', reg['formula_id']),
        insumo = Db.registro('insumos', reg['insumo_id']);

  final Reg reg;
  final Reg? lote, formula, insumo;

  int get id => _int(reg['id'])!;
  String get nome => _t(reg['nome']).isEmpty ? 'Curral' : _t(reg['nome']);
  bool get aberto => reg['encerrado'] != true;
  String get entrada => _dia(reg['data_entrada']);
  int? get loteId => _int(reg['lote_id']);

  /// Nome da dieta do cocho.
  String get dieta => formula != null ? _t(formula!['nome']) : (insumo != null ? _t(insumo!['nome']) : 'Sem dieta');

  /// Matéria seca da dieta (fração; 0,88 = 88%).
  double get ms => (_num(reg['ms']) ?? 88) / 100;

  double? get precoKg => formula != null ? CalculoFormula(formula!).precoKg : precoKgInsumo(insumo);

  /// Animais do lote (ativos e os que saíram depois da entrada).
  List<Reg> get _animaisDoLote => loteId == null
      ? const []
      : [
          for (final a in Db.registros('animais'))
            if (_int(a['lote_id']) == loteId) a,
        ];

  int get cabecasEntrada => _int(reg['cabecas']) ?? (loteId == null ? 0 : _animaisDoLote.length);

  /// Mortes no ciclo: animais do lote mortos (ou as lançadas à mão, sem lote).
  int get mortes {
    if (loteId == null || (!aberto && reg['mortes'] != null)) return _int(reg['mortes']) ?? 0;
    var n = 0;
    for (final a in _animaisDoLote) {
      if (a['status'] != 'Morto') continue;
      final s = Db.registro('saidas', a['saida_id']);
      if (s == null || _dia(s['data']).compareTo(entrada) >= 0) n++;
    }
    return n;
  }

  /// Cabeças no cocho hoje.
  int get cabecas {
    if (!aberto && reg['cabecas_saida'] != null) return _int(reg['cabecas_saida'])!;
    if (loteId != null && aberto) return _animaisDoLote.where((a) => a['status'] == 'Ativo').length;
    return (cabecasEntrada - mortes).clamp(0, 1 << 30);
  }

  /// Último dia do ciclo nas contas: a saída, se encerrado, ou [hoje].
  String fim(String hoje) => aberto ? hoje : (_dia(reg['data_saida']).isEmpty ? hoje : _dia(reg['data_saida']));

  /// Dias de cocho até [hoje] (ou até a saída).
  int diasDeCocho(String hoje) => entrada.isEmpty ? 0 : _dias(entrada, fim(hoje)).clamp(0, 100000);

  /// Leituras/tratos do ciclo, do mais novo para o mais antigo.
  List<Reg> get leituras => [
        for (final r in Db.registros('cocho'))
          if (_int(r['confinamento_id']) == id) r,
      ]..sort((a, b) => _t(b['data']).compareTo(_t(a['data'])));

  Reg? leituraDoDia(String data) {
    for (final r in leituras) {
      if (_dia(r['data']) == data) return r;
    }
    return null;
  }

  // ---------- Trato ----------

  /// Trato sugerido (kg do curral) para [data] com a [nota] da leitura: o último
  /// trato fornecido por cabeça, ajustado pela nota; sem trato anterior, o
  /// trato inicial do ciclo (kg/cab/dia).
  double trato(String data, int? nota) {
    Reg? anterior;
    for (final r in leituras) {
      if (_dia(r['data']).compareTo(data) < 0 && _n(r['kg_fornecido']) > 0) {
        anterior = r;
        break;
      }
    }
    final cab = cabecas;
    final porCab = anterior != null && (_int(anterior['cabecas']) ?? 0) > 0
        ? _n(anterior['kg_fornecido']) / _int(anterior['cabecas'])!
        : _n(reg['kg_cab_dia']);
    return porCab * cab * (1 + ajusteDaNota(nota));
  }

  // ---------- Pesos ----------

  double get pesoEntrada => _n(reg['peso_entrada']);
  double get gmdPrevisto => _num(reg['gmd_previsto']) ?? 1.5;

  /// Peso médio da última pesagem do lote depois da entrada (e a data dela).
  (double, String)? get pesagem {
    if (loteId == null || entrada.isEmpty) return null;
    final ultimas = <int, Reg>{};
    final ativos = {
      for (final a in _animaisDoLote)
        if (a['status'] == 'Ativo' || !aberto) _int(a['id'])!,
    };
    for (final p in Db.registros('pesagens')) {
      final a = _int(p['animal_id']);
      if (!ativos.contains(a) || _dia(p['data']).compareTo(entrada) <= 0) continue;
      if (!aberto && _dia(reg['data_saida']).isNotEmpty && _dia(p['data']).compareTo(_dia(reg['data_saida'])) > 0) continue;
      final u = ultimas[a!];
      if (u == null || _t(p['data']).compareTo(_t(u['data'])) > 0) ultimas[a] = p;
    }
    if (ultimas.isEmpty) return null;
    final soma = ultimas.values.fold<double>(0, (s, p) => s + _n(p['peso']));
    final data = ultimas.values.map((p) => _dia(p['data'])).reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    return (soma / ultimas.length, data);
  }

  /// GMD do ciclo: pela pesagem (real) ou o previsto.
  double gmd(String hoje) {
    if (!aberto && _n(reg['peso_saida']) > 0 && pesoEntrada > 0) {
      final d = diasDeCocho(hoje);
      if (d > 0) return (_n(reg['peso_saida']) - pesoEntrada) / d;
    }
    final p = pesagem;
    if (p != null && pesoEntrada > 0) {
      final d = _dias(entrada, p.$2);
      if (d > 0) return (p.$1 - pesoEntrada) / d;
    }
    return gmdPrevisto;
  }

  bool gmdReal(String hoje) => (!aberto && _n(reg['peso_saida']) > 0) || pesagem != null;

  /// Peso médio hoje: a saída, a pesagem mais o GMD desde ela, ou a entrada mais o GMD.
  double pesoAtual(String hoje) {
    if (!aberto && _n(reg['peso_saida']) > 0) return _n(reg['peso_saida']);
    final p = pesagem;
    if (p != null) return p.$1 + gmd(hoje) * _dias(p.$2, hoje).clamp(0, 100000);
    return pesoEntrada + gmd(hoje) * diasDeCocho(hoje);
  }

  // ---------- Consumo ----------

  /// Cabeças × dias com trato lançado.
  double get cabecaDias => leituras.fold(0, (s, r) => s + (_int(r['cabecas']) ?? 0) * (_n(r['kg_fornecido']) > 0 ? 1 : 0));
  double get kgFornecido => leituras.fold(0, (s, r) => s + _n(r['kg_fornecido']));

  /// Consumo de matéria natural e de matéria seca (kg por cabeça por dia).
  double? get consumoMN => cabecaDias <= 0 ? null : kgFornecido / cabecaDias;
  double? get consumoMS => consumoMN == null ? null : consumoMN! * ms;

  /// Consumo de MS em % do peso vivo médio.
  double? consumoPV(String hoje) {
    final cms = consumoMS;
    final pm = (pesoEntrada + pesoAtual(hoje)) / 2;
    return cms == null || pm <= 0 ? null : cms / pm * 100;
  }

  /// Conversão alimentar: kg de MS para cada kg ganho.
  double? conversao(String hoje) {
    final cms = consumoMS, g = gmd(hoje);
    return cms == null || g <= 0 ? null : cms / g;
  }

  // ---------- Custos ----------

  /// Custo da ração fornecida: os custos lançados pelo trato (ou kg × preço).
  double get custoAlimentar {
    var s = 0.0;
    for (final r in leituras) {
      final c = Db.registro('custos', r['custo_id']);
      s += c != null ? _n(c['valor']) : _n(r['kg_fornecido']) * (precoKg ?? 0);
    }
    return s;
  }

  /// Custo operacional fixo por cabeça por dia (mão de obra, máquinas, etc.).
  double get custoFixoDia => _n(reg['custo_fixo_dia']);

  /// Diária: custo por cabeça por dia (ração + operacional). Sem trato lançado,
  /// usa o trato inicial pelo preço da dieta.
  double get diaria {
    final alim = cabecaDias > 0 ? custoAlimentar / cabecaDias : _n(reg['kg_cab_dia']) * (precoKg ?? 0);
    return alim + custoFixoDia;
  }

  double get valorCompra => _n(reg['valor_compra']);

  /// Rendimento de carcaça na entrada e na saída (fração).
  double get rendEntrada => (_num(reg['rend_entrada']) ?? 50) / 100;
  double get rendSaida => (_num(reg['rend_real']) ?? _num(reg['rend_saida']) ?? ajustesArroba().$1 * 100) / 100;

  /// Arroba de venda: a do encerramento, a do ciclo ou a da cotação salva.
  double? get arroba => _num(reg['arroba_venda']) ?? ajustesArroba().$2;

  /// Conta do ciclo num dia: hoje (até agora) ou na saída prevista.
  Resultado resultado(String hoje, {bool naSaida = false}) {
    final g = gmd(hoje);
    final dias = naSaida ? diasPrevistos(hoje) : diasDeCocho(hoje);
    final peso = naSaida ? pesoNaSaida(hoje) : pesoAtual(hoje);
    return Resultado(
      dias: dias,
      peso: peso,
      gmd: g,
      custoCab: diaria * dias,
      arrobasProduzidas: (peso * rendSaida - pesoEntrada * rendEntrada) / 15,
      arrobasSaida: peso * rendSaida / 15,
      valorCompra: valorCompra,
      arroba: arroba,
    );
  }

  // ---------- Projeção de saída ----------

  double? get metaPeso => _num(reg['meta_peso']);
  int? get metaDias => _int(reg['meta_dias']);

  /// Dias de cocho previstos no total: até a meta de peso pelo GMD, ou a meta de dias.
  int diasPrevistos(String hoje) {
    if (!aberto) return diasDeCocho(hoje);
    final g = gmd(hoje);
    if (metaPeso != null && metaPeso! > 0 && g > 0) {
      final falta = ((metaPeso! - pesoAtual(hoje)) / g).ceil();
      return diasDeCocho(hoje) + falta.clamp(0, 100000);
    }
    return metaDias ?? diasDeCocho(hoje);
  }

  String? saidaPrevista(String hoje) => entrada.isEmpty ? null : _somaDias(entrada, diasPrevistos(hoje));

  double pesoNaSaida(String hoje) {
    if (!aberto) return pesoAtual(hoje);
    final faltam = diasPrevistos(hoje) - diasDeCocho(hoje);
    return pesoAtual(hoje) + gmd(hoje) * faltam;
  }

  /// Mensagem curta do trato de hoje, para o tratorista.
  String linhaTrato(double kg) => '• $nome: ${_fmt(kg)} kg de $dieta ($cabecas cab.)';
}

/// Conta do ciclo por cabeça.
class Resultado {
  Resultado({
    required this.dias,
    required this.peso,
    required this.gmd,
    required this.custoCab,
    required this.arrobasProduzidas,
    required this.arrobasSaida,
    required this.valorCompra,
    required this.arroba,
  });

  final int dias;
  final double peso, gmd, custoCab, arrobasProduzidas, arrobasSaida, valorCompra;
  final double? arroba;

  /// Custo de cada arroba produzida no cocho.
  double? get custoArroba => arrobasProduzidas <= 0 ? null : custoCab / arrobasProduzidas;

  /// Arroba de venda que paga o boi magro e o custo (ponto de equilíbrio).
  double? get equilibrio => arrobasSaida <= 0 ? null : (valorCompra + custoCab) / arrobasSaida;

  double? get receita => arroba == null ? null : arrobasSaida * arroba!;

  /// Lucro por cabeça na arroba informada.
  double? get margem => receita == null ? null : receita! - valorCompra - custoCab;
}

/// Grava a leitura e o trato do dia. Se já houver lançamento no dia, troca (o
/// custo antigo é apagado e o estoque volta). Com [baixar], o trato fornecido
/// lança o custo e tira do estoque.
Future<int> registrarCocho(Ciclo c,
    {required String data, int? nota, required double kgPrevisto, required double kgFornecido, bool baixar = true, String? obs}) async {
  final antes = c.leituraDoDia(data);
  if (antes != null) await Db.excluir('cocho', _int(antes['id'])!);
  int? custo;
  if (baixar && kgFornecido > 0) {
    custo = await baixarTrato(
      formula: c.formula,
      insumo: c.insumo,
      kg: kgFornecido,
      loteId: c.loteId,
      data: data,
      texto: 'Confinamento ${c.nome} · trato de ${_fmt(kgFornecido)} kg (${c.cabecas} cab.)',
    );
  }
  return Db.inserir('cocho', {
    'propriedade_id': Db.pid,
    'confinamento_id': c.id,
    'data': data,
    'nota': nota,
    'cabecas': c.cabecas,
    'kg_previsto': double.parse(kgPrevisto.toStringAsFixed(1)),
    'kg_fornecido': double.parse(kgFornecido.toStringAsFixed(1)),
    'custo_id': custo,
    if (obs != null && obs.isNotEmpty) 'obs': obs,
  });
}

/// Encerra o ciclo com o peso de saída, o rendimento de carcaça do abate e a
/// arroba de venda.
Future<void> encerrarCiclo(Ciclo c, {required String data, double? pesoSaida, double? rendReal, double? arroba}) =>
    Db.atualizar('confinamentos', c.id, {
      'encerrado': true,
      'data_saida': data,
      'cabecas_saida': c.cabecas,
      if (c.loteId != null) 'mortes': c.mortes,
      'peso_saida': pesoSaida,
      'rend_real': rendReal,
      'arroba_venda': arroba,
    });

/// Texto do trato do dia para o tratorista (WhatsApp).
String textoTratoWhats(List<(Ciclo, double)> tratos, String data, {String? fazenda}) {
  final d = data.length >= 10 ? '${data.substring(8, 10)}/${data.substring(5, 7)}' : data;
  final total = tratos.fold<double>(0, (s, t) => s + t.$2);
  return [
    'Trato do confinamento · $d${fazenda == null || fazenda.isEmpty ? '' : ' · $fazenda'}',
    '',
    for (final (c, kg) in tratos) c.linhaTrato(kg),
    '',
    'Total: ${_fmt(total)} kg',
  ].join('\n');
}
