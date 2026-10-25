// Estoque de insumos (vacinas, remédios, sal, ração), dieta do cocho e a conta
// de vender agora ou esperar.
import 'db.dart';
import 'gestao.dart' show ajustesArroba;
import 'manejo.dart';
import 'proteinado.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _n(Object? v) => v is num ? v.toDouble() : 0;
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);

int _dias(String de, String ate) {
  final a = DateTime.parse(de.substring(0, 10)), b = DateTime.parse(ate.substring(0, 10));
  return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

String _menosDias(String iso, int dias) => Db.dataEtapa(iso, -dias);

// ---------- Estoque ----------

const categoriasInsumo = ['Vacina', 'Medicamento e vermífugo', 'Sal mineral', 'Ração e ingredientes', 'Outros'];
const unidadesInsumo = ['kg', 'dose', 'ml', 'un'];

/// Estoque de Medicamentos: vacinas, remédios e vermífugos.
const categoriasMedicamento = ['Vacina', 'Medicamento e vermífugo'];

/// Estoque de insumos em geral: sal, milho, sorgo, ração e ingredientes.
const categoriasGeral = ['Sal mineral', 'Ração e ingredientes', 'Outros'];

/// Unidade sugerida para a categoria.
String unidadePadrao(String categoria) => switch (categoria) {
      'Vacina' => 'dose',
      'Medicamento e vermífugo' => 'ml',
      'Outros' => 'un',
      _ => 'kg',
    };

String categoriaInsumo(Reg i) => _t(i['categoria']).isEmpty ? 'Ração e ingredientes' : _t(i['categoria']);
String unidadeInsumo(Reg i) => _t(i['unidade']).isEmpty ? unidadePadrao(categoriaInsumo(i)) : _t(i['unidade']);

List<Reg> movimentos(int insumoId) => [
      for (final e in Db.registros('estoque'))
        if (_int(e['insumo_id']) == insumoId) e,
    ]..sort((a, b) {
        final c = _t(b['data']).compareTo(_t(a['data']));
        return c != 0 ? c : (_int(b['id']) ?? 0).compareTo(_int(a['id']) ?? 0);
      });

/// Saldo do insumo: entradas menos saídas.
double saldo(int insumoId) => movimentos(insumoId).fold(0, (s, e) => s + _n(e['qtd']));

/// Gasto médio por dia nos últimos [janela] dias (só saídas).
double consumoDiario(int insumoId, String hoje, {int janela = 30}) {
  final de = _menosDias(hoje, janela);
  final saidas = movimentos(insumoId).where((e) =>
      _n(e['qtd']) < 0 && e['ajuste'] != true && _dia(e['data']).compareTo(de) > 0 && _dia(e['data']).compareTo(hoje) <= 0);
  return -saidas.fold<double>(0, (s, e) => s + _n(e['qtd'])) / janela;
}

Future<int> entradaEstoque(int insumoId, double qtd, {required String data, String? validade, String? obs}) async {
  final id = await Db.inserir('estoque', {
    'propriedade_id': Db.pid,
    'insumo_id': insumoId,
    'data': data,
    'qtd': qtd,
    'motivo': obs ?? 'Entrada',
  });
  if (validade != null) await Db.atualizar('insumos', insumoId, {'validade': validade});
  return id;
}

/// Acerta o saldo pela contagem feita no depósito.
Future<void> ajustarSaldo(int insumoId, double contado, {required String data}) async {
  final dif = contado - saldo(insumoId);
  if (dif.abs() < 1e-9) return;
  await Db.inserir('estoque', {
    'propriedade_id': Db.pid,
    'insumo_id': insumoId,
    'data': data,
    'qtd': dif,
    'motivo': 'Ajuste de contagem',
    'ajuste': true,
  });
}

class AlertaEstoque {
  AlertaEstoque(this.insumo, this.texto, {this.grave = false});
  final Reg insumo;
  final String texto;
  final bool grave;
}

/// Insumos abaixo do mínimo, acabando em 15 dias, vencidos ou vencendo em 30 dias.
List<AlertaEstoque> alertasEstoque(String hoje) {
  final r = <AlertaEstoque>[];
  for (final i in insumos()) {
    final id = _int(i['id'])!;
    final un = unidadeInsumo(i);
    final s = saldo(id);
    final minimo = i['estoque_min'] is num ? _n(i['estoque_min']) : null;
    final usa = movimentos(id).isNotEmpty;
    if (usa && s <= 0) {
      r.add(AlertaEstoque(i, 'Sem estoque', grave: true));
    } else if (minimo != null && s <= minimo) {
      r.add(AlertaEstoque(i, 'Abaixo do mínimo (${_fmt(s)} de ${_fmt(minimo)} $un)'));
    } else {
      final c = consumoDiario(id, hoje);
      if (c > 0 && s / c < 15) r.add(AlertaEstoque(i, 'Acaba em ${(s / c).floor()} dia(s)'));
    }
    final v = _dia(i['validade']);
    if (v.length == 10 && s > 0) {
      final falta = _dias(hoje, v);
      if (falta < 0) {
        r.add(AlertaEstoque(i, 'Vencido desde ${v.substring(8)}/${v.substring(5, 7)}/${v.substring(0, 4)}', grave: true));
      } else if (falta <= 30) {
        r.add(AlertaEstoque(i, 'Vence em $falta dia(s)'));
      }
    }
  }
  return r;
}

String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

// ---------- Dieta do cocho ----------

/// Animais ativos do lote.
int cabecasDoLote(int? loteId) =>
    Db.registros('animais').where((a) => a['status'] == 'Ativo' && _int(a['lote_id']) == loteId).length;

/// Animais ativos no piquete/pasto.
List<Reg> animaisDoPiquete(int? piqueteId) => [
      for (final a in Db.registros('animais'))
        if (a['status'] == 'Ativo' && piqueteId != null && _int(a['piquete_id']) == piqueteId) a,
    ];

/// Dieta do cocho de um piquete/pasto. Dietas antigas, feitas por lote,
/// continuam valendo pelo lote até serem passadas para um piquete.
class Dieta {
  Dieta(this.reg)
      : piquete = Db.registro('piquetes', reg['piquete_id']),
        lote = reg['piquete_id'] == null ? Db.registro('lotes', reg['lote_id']) : null,
        formula = Db.registro('formulas', reg['formula_id']),
        insumo = Db.registro('insumos', reg['insumo_id']);
  final Reg reg;
  final Reg? piquete, lote, formula, insumo;

  String get nome => formula != null ? 'Proteinado ${formula!['nome']}' : _t(insumo?['nome']);

  /// Onde fica o cocho: o piquete/pasto (ou o lote, nas dietas antigas).
  String get local => piquete != null
      ? _t(piquete!['nome'])
      : lote != null
          ? 'Lote ${_t(lote!['nome'])}'
          : 'Sem piquete';

  int get cabecas =>
      reg['piquete_id'] != null ? animaisDoPiquete(_int(reg['piquete_id'])).length : cabecasDoLote(_int(reg['lote_id']));

  /// Lote que leva o custo do trato: o das dietas antigas ou, no piquete, o lote
  /// de todos os animais que estão nele (se forem de lotes diferentes, nenhum).
  int? get loteDoCusto {
    if (reg['piquete_id'] == null) return _int(reg['lote_id']);
    final lotes = {for (final a in animaisDoPiquete(_int(reg['piquete_id']))) _int(a['lote_id'])};
    return lotes.length == 1 ? lotes.first : null;
  }

  /// Kg por cabeça por dia.
  double get kgCabDia => _n(reg['kg_cab_dia']);
  double get kgDia => kgCabDia * cabecas;
  double get kgMes => kgDia * 30;

  double? get precoKg => formula != null ? CalculoFormula(formula!).precoKg : precoKgInsumo(insumo);
  double get custoDia => kgDia * (precoKg ?? 0);
  double get custoMes => custoDia * 30;
  double get custoCabDia => kgCabDia * (precoKg ?? 0);

  /// Dias que o estoque aguenta (pelo insumo que acaba primeiro), ou null sem estoque lançado.
  double? get diasDeEstoque {
    if (kgDia <= 0) return null;
    if (insumo != null) {
      final id = _int(insumo!['id'])!;
      return movimentos(id).isEmpty ? null : saldo(id) / kgDia;
    }
    if (formula == null) return null;
    final c = CalculoFormula(formula!);
    if (c.kgBatida <= 0) return null;
    double? menor;
    for (final l in c.linhas) {
      final id = _int(l.insumo?['id']);
      if (id == null || movimentos(id).isEmpty) continue;
      final d = saldo(id) / (kgDia * l.kg / c.kgBatida);
      if (menor == null || d < menor) menor = d;
    }
    return menor;
  }

  /// Batidas da fórmula por mês.
  double? get batidasMes {
    if (formula == null) return null;
    final kg = CalculoFormula(formula!).kgBatida;
    return kg <= 0 ? null : kgMes / kg;
  }
}

List<Dieta> dietas() => [
      for (final d in Db.registros('dietas'))
        if (_int(d['propriedade_id']) == Db.pid) Dieta(d),
    ]..sort((a, b) => a.local.toLowerCase().compareTo(b.local.toLowerCase()));

/// Estoque de ração pronta de uma fórmula (criado ao bater a ração).
Reg? racaoPronta(Object? formulaId) {
  final id = _int(formulaId);
  if (id == null) return null;
  for (final i in Db.registros('insumos')) {
    if (_int(i['propriedade_id']) == Db.pid && _int(i['pronta_formula_id']) == id) return i;
  }
  return null;
}

/// Bate [kgBatidos] kg da ração da fórmula: tira os ingredientes do estoque e
/// põe a ração pronta no estoque, pelo custo médio por quilo. O custo só vai para
/// Custos quando a ração é dada no cocho (trato). Devolve o custo do quilo, ou
/// null se a fórmula não tem ingredientes.
/// [foraDoEstoque]: ingredientes que vieram de fora; entram no custo, mas não baixam o estoque.
Future<double?> baterRacao(Reg formula, {required String data, required double kgBatidos, Set<int> foraDoEstoque = const {}, String? fornecedor}) async {
  final c = CalculoFormula(formula);
  if (c.kgBatida <= 0 || kgBatidos <= 0) return null;
  final batidas = kgBatidos / c.kgBatida;
  final grupo = 'racao_${DateTime.now().microsecondsSinceEpoch}';
  for (final l in c.linhas) {
    if (l.insumo == null || foraDoEstoque.contains(_int(l.insumo!['id']))) continue;
    await Db.inserir('estoque', {
      'propriedade_id': Db.pid,
      'insumo_id': l.insumo!['id'],
      'data': data,
      'qtd': -double.parse((l.kg * batidas).toStringAsFixed(3)),
      'motivo': 'Fabricação de ração ${formula['nome']}',
      'grupo': grupo,
    });
  }
  final precoKgNovo = c.precoKg ?? 0;
  final pronta = racaoPronta(formula['id']);
  int insumoId;
  if (pronta == null) {
    insumoId = await Db.inserir('insumos', {
      'propriedade_id': Db.pid,
      'nome': 'Ração pronta · ${formula['nome']}',
      'categoria': 'Ração e ingredientes',
      'unidade': 'kg',
      'kg_saco': 1,
      'preco_saco': double.parse(precoKgNovo.toStringAsFixed(4)),
      'pronta_formula_id': formula['id'],
    });
  } else {
    insumoId = _int(pronta['id'])!;
    final antes = saldo(insumoId).clamp(0, double.infinity);
    final precoAntes = precoKgInsumo(pronta) ?? precoKgNovo;
    final medio = (antes * precoAntes + kgBatidos * precoKgNovo) / (antes + kgBatidos);
    await Db.atualizar('insumos', insumoId, {'preco_saco': double.parse(medio.toStringAsFixed(4))});
  }
  await Db.inserir('estoque', {
    'propriedade_id': Db.pid,
    'insumo_id': insumoId,
    'data': data,
    'qtd': double.parse(kgBatidos.toStringAsFixed(3)),
    'motivo': 'Ração batida ${formula['nome']}',
    'grupo': grupo,
  });
  await Db.inserir('batidas', {
    'propriedade_id': Db.pid,
    'formula_id': formula['id'],
    'formula_nome': _t(formula['nome']),
    'tipo': 'Ração pronta',
    'data': data,
    'batidas': double.parse(batidas.toStringAsFixed(3)),
    'kg': double.parse(kgBatidos.toStringAsFixed(3)),
    'custo_total': double.parse((precoKgNovo * kgBatidos).toStringAsFixed(2)),
    'custo_kg': double.parse(precoKgNovo.toStringAsFixed(4)),
    'grupo': grupo,
    if (fornecedor != null && fornecedor.isNotEmpty) 'fornecedor': fornecedor,
    'itens': [
      for (final l in c.linhas)
        {
          if (foraDoEstoque.contains(_int(l.insumo?['id']))) 'fora_estoque': true,
          'insumo_id': l.insumo?['id'],
          'nome': l.nome,
          'kg': double.parse((l.kg * batidas).toStringAsFixed(3)),
          'preco_kg': l.custo == null ? null : double.parse((l.custo! / l.kg).toStringAsFixed(4)),
          'custo': l.custo == null ? null : double.parse((l.custo! * batidas).toStringAsFixed(2)),
        },
    ],
  });
  return precoKgNovo;
}

/// Lança o trato de [dias] dias: custo em Ração e sal e baixa no estoque.
/// Com ração pronta em estoque, usa ela; senão tira os ingredientes da fórmula.
Future<int?> lancarTrato(Dieta d, {required String data, int dias = 1}) async {
  final kg = d.kgDia * dias;
  if (kg <= 0) return null;
  final texto = 'Trato ${d.nome} · ${d.local} · ${_fmt(kg)} kg em $dias dia(s) (${d.cabecas} cab.)';
  final pronta = racaoPronta(d.formula?['id']);
  if (pronta != null && saldo(_int(pronta['id'])!) >= kg) {
    final id = await Db.inserir('custos', {
      'propriedade_id': Db.pid,
      'lote_id': d.loteDoCusto,
      'categoria': 'Ração e sal',
      'descricao': texto,
      'valor': double.parse((kg * (precoKgInsumo(pronta) ?? 0)).toStringAsFixed(2)),
      'data': data,
    });
    await Db.inserir('estoque', {
      'propriedade_id': Db.pid,
      'insumo_id': pronta['id'],
      'data': data,
      'qtd': -double.parse(kg.toStringAsFixed(3)),
      'motivo': texto,
      'grupo': '$id',
    });
    return id;
  }
  if (d.formula != null) {
    final c = CalculoFormula(d.formula!);
    if (c.kgBatida <= 0) return null;
    return registrarBatida(d.formula!, data: data, batidas: kg / c.kgBatida, loteId: d.loteDoCusto, descricao: texto);
  }
  final ins = d.insumo;
  if (ins == null) return null;
  final id = await Db.inserir('custos', {
    'propriedade_id': Db.pid,
    'lote_id': d.loteDoCusto,
    'categoria': 'Ração e sal',
    'descricao': texto,
    'valor': double.parse((kg * (precoKgInsumo(ins) ?? 0)).toStringAsFixed(2)),
    'data': data,
  });
  await Db.inserir('estoque', {
    'propriedade_id': Db.pid,
    'insumo_id': ins['id'],
    'data': data,
    'qtd': -double.parse(kg.toStringAsFixed(3)),
    'motivo': texto,
    'grupo': '$id',
  });
  return id;
}

// ---------- Vender agora ou esperar ----------

class CenarioVenda {
  CenarioVenda(this.dias, this.peso, this.valor, this.custo, this.ganho, this.arrobaEmpate);
  final int dias;

  /// Peso médio previsto, valor por cabeça, custo por cabeça no período e
  /// ganho de esperar em relação a vender hoje (por cabeça).
  final double peso, valor, custo, ganho;

  /// Arroba mínima na data para esperar não dar prejuízo.
  final double arrobaEmpate;
}

class VendaLote {
  VendaLote(this.lote, this.loteId, this.cabecas, this.peso, this.gmd, this.valorHoje, this.custoDia, this.cenarios);
  final String lote;
  final int? loteId;
  final int cabecas;
  final double peso;
  final double? gmd;
  final double valorHoje, custoDia;
  final List<CenarioVenda> cenarios;

  /// Melhor prazo (0 = vender agora).
  int get melhor {
    var m = 0;
    var g = 0.0;
    for (final c in cenarios) {
      if (c.ganho > g) (m, g) = (c.dias, c.ganho);
    }
    return m;
  }
}

/// Conta de cada lote pesado: vale mais vender hoje ou daqui a 30, 60 e 90 dias,
/// pelo GMD, pelo custo diário (dieta do cocho + [custoFixoDia] por cabeça) e
/// pela arroba (com [variacaoArroba] em % até o fim de cada prazo, proporcional).
List<VendaLote> venderOuEsperar({
  double? arroba,
  double custoFixoDia = 0,
  double variacaoArroba = 0,
  List<int> prazos = const [30, 60, 90],
}) {
  final (rend, arrobaSalva) = ajustesArroba();
  final preco = arroba ?? arrobaSalva;
  if (preco == null || preco <= 0) return [];
  // Custo diário de cocho por cabeça em cada lote: dietas antigas pelo lote;
  // dietas de piquete pela média dos animais do lote que estão nesses piquetes.
  final custoDieta = <int?, double>{};
  final porPiquete = <int, double>{};
  for (final d in dietas()) {
    final q = _int(d.reg['piquete_id']);
    if (q == null) {
      custoDieta[_int(d.reg['lote_id'])] = (custoDieta[_int(d.reg['lote_id'])] ?? 0) + d.custoCabDia;
    } else {
      porPiquete[q] = (porPiquete[q] ?? 0) + d.custoCabDia;
    }
  }
  if (porPiquete.isNotEmpty) {
    final soma = <int?, double>{}, cab = <int?, int>{};
    for (final a in Db.registros('animais')) {
      if (a['status'] != 'Ativo' || _int(a['propriedade_id']) != Db.pid) continue;
      final l = _int(a['lote_id']);
      cab[l] = (cab[l] ?? 0) + 1;
      soma[l] = (soma[l] ?? 0) + (porPiquete[_int(a['piquete_id'])] ?? 0);
    }
    for (final e in soma.entries) {
      custoDieta[e.key] = (custoDieta[e.key] ?? 0) + e.value / cab[e.key]!;
    }
  }
  final lotesPorNome = {for (final l in Db.registros('lotes')) if (_int(l['propriedade_id']) == Db.pid) _t(l['nome']): _int(l['id'])};
  final r = <VendaLote>[];
  for (final p in projecaoAbate(1e9)) {
    final loteId = lotesPorNome[p.nome];
    final peso = p.pesoMedio, gmd = p.gmdMedio;
    final custoDia = (custoDieta[loteId] ?? 0) + custoFixoDia;
    final hoje = valorArroba(peso, rend, preco);
    final cenarios = <CenarioVenda>[];
    if (gmd != null) {
      for (final d in prazos) {
        final pf = peso + gmd * d;
        final pr = preco * (1 + variacaoArroba / 100 * d / prazos.last);
        final v = valorArroba(pf, rend, pr);
        final custo = custoDia * d;
        cenarios.add(CenarioVenda(d, pf, v, custo, v - custo - hoje, (hoje + custo) * 15 / (pf * rend)));
      }
    }
    r.add(VendaLote(p.nome, loteId, p.animais.length, peso, gmd, hoje, custoDia, cenarios));
  }
  return r;
}
