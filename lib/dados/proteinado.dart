// Produção de proteinado (como a planilha de cálculo) e cotação da arroba.
import 'db.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _n(Object? v) => v is num ? v.toDouble() : 0;
String _t(Object? v) => v == null ? '' : '$v';

/// Tipos fixos, nesta ordem. A fórmula pode ter outro tipo, digitado.
const tiposProteinado = ['Alto consumo', 'Médio consumo', 'Baixo consumo', 'Ração creep', 'Ração leite'];

/// Tipo da fórmula (nomes antigos viram os atuais).
String tipoFormula(Reg f) {
  final t = _t(f['tipo']).trim();
  if (t.isEmpty) return 'Outras';
  if (t.toLowerCase() == 'creep') return 'Ração creep';
  return tiposProteinado.firstWhere((x) => x.toLowerCase() == t.toLowerCase(), orElse: () => t);
}

/// Tipos em uso: os fixos e os criados pelo usuário, em ordem.
List<String> tiposEmUso() {
  final extras = {for (final f in formulas()) tipoFormula(f)}..removeAll(tiposProteinado);
  return [...tiposProteinado, ...extras.toList()..sort()];
}

/// Matérias-primas da propriedade: preço do saco e peso do saco.
List<Reg> insumos() => [
      for (final i in Db.registros('insumos'))
        if (_int(i['propriedade_id']) == Db.pid) i,
    ]..sort((a, b) => _t(a['nome']).compareTo(_t(b['nome'])));

List<Reg> formulas() => [
      for (final f in Db.registros('formulas'))
        if (_int(f['propriedade_id']) == Db.pid) f,
    ]..sort((a, b) {
        int ordem(Reg f) {
          final i = tiposProteinado.indexOf(tipoFormula(f));
          return i < 0 ? tiposProteinado.length : i;
        }

        final t = ordem(a).compareTo(ordem(b));
        if (t != 0) return t;
        final x = tipoFormula(a).compareTo(tipoFormula(b));
        return x != 0 ? x : _t(a['nome']).compareTo(_t(b['nome']));
      });

/// Preço do quilo de um insumo (preço do saco ÷ peso do saco), ou null sem preço.
double? precoKgInsumo(Reg? i) {
  final kg = _n(i?['kg_saco']);
  if (i == null || i['preco_saco'] is! num || kg <= 0) return null;
  return _n(i['preco_saco']) / kg;
}

class LinhaFormula {
  LinhaFormula(this.insumo, this.nome, this.kg, this.custo);
  final Reg? insumo;
  final String nome;
  final double kg;

  /// Null quando o insumo está sem preço.
  final double? custo;
}

/// Conta de uma fórmula, igual à planilha: batida, preço do quilo e consumo.
class CalculoFormula {
  CalculoFormula(this.formula) {
    for (final it in (formula['itens'] as List?) ?? const []) {
      final m = Map<String, Object?>.from(it as Map);
      final ins = Db.registro('insumos', m['insumo_id']);
      final kg = _n(m['kg']);
      if (kg <= 0) continue;
      final pk = precoKgInsumo(ins);
      linhas.add(LinhaFormula(ins, _t(ins?['nome']).isEmpty ? 'Insumo apagado' : _t(ins!['nome']), kg, pk == null ? null : kg * pk));
    }
  }

  final Reg formula;
  final linhas = <LinhaFormula>[];

  double get kgBatida => linhas.fold(0, (s, l) => s + l.kg);
  double get sacaria => _n(formula['saco_qtd']) * _n(formula['saco_preco']);
  double get maoDeObra => _n(formula['mao_obra']);
  double get custoBatida => linhas.fold<double>(0, (s, l) => s + (l.custo ?? 0)) + sacaria + maoDeObra;
  List<String> get semPreco => [for (final l in linhas) if (l.custo == null) l.nome];

  double? get precoKg => kgBatida <= 0 ? null : custoBatida / kgBatida;
  double get gramasDia => _n(formula['consumo_g']);
  int get cabecas => _int(formula['cabecas']) ?? 1;
  double get meses => _n(formula['meses']);

  /// Consumo do lote (kg) e custo por dia, mês (30 dias) e seca toda.
  double get kgDia => gramasDia * cabecas / 1000;
  double get kgMes => kgDia * 30;
  double get kgSeca => kgMes * meses;
  double get custoCabecaDia => gramasDia / 1000 * (precoKg ?? 0);
  double get custoDia => kgDia * (precoKg ?? 0);
  double get custoMes => kgMes * (precoKg ?? 0);
  double get custoSeca => kgSeca * (precoKg ?? 0);

  /// Batidas para a seca toda.
  double? get batidasSeca => kgBatida <= 0 ? null : kgSeca / kgBatida;
}

/// Lança o custo de [batidas] batidas da fórmula em Custos (Ração e sal) e
/// tira do estoque os insumos usados. Apagar o custo devolve o estoque.
Future<int> registrarBatida(Reg formula, {required String data, double batidas = 1, int? loteId, String? descricao}) async {
  final c = CalculoFormula(formula);
  final id = await Db.inserir('custos', {
    'propriedade_id': Db.pid,
    'lote_id': loteId,
    'categoria': 'Ração e sal',
    'descricao': descricao ??
        'Proteinado ${formula['nome']} · ${_qtd(batidas)} batida${batidas == 1 ? '' : 's'} (${_qtd(c.kgBatida * batidas)} kg)',
    'valor': double.parse((c.custoBatida * batidas).toStringAsFixed(2)),
    'data': data,
  });
  for (final l in c.linhas) {
    if (l.insumo == null) continue;
    await Db.inserir('estoque', {
      'propriedade_id': Db.pid,
      'insumo_id': l.insumo!['id'],
      'data': data,
      'qtd': -double.parse((l.kg * batidas).toStringAsFixed(3)),
      'motivo': descricao ?? 'Batida ${formula['nome']}',
      'grupo': '$id',
    });
  }
  // Batida de verdade (não trato do cocho): fica no histórico, com os preços do dia.
  if (descricao == null) {
    await Db.inserir('batidas', {
      'propriedade_id': Db.pid,
      'formula_id': formula['id'],
      'formula_nome': _t(formula['nome']),
      'tipo': tipoFormula(formula),
      'data': data,
      'batidas': batidas,
      'kg': double.parse((c.kgBatida * batidas).toStringAsFixed(3)),
      'custo_total': double.parse((c.custoBatida * batidas).toStringAsFixed(2)),
      'custo_kg': c.precoKg == null ? null : double.parse(c.precoKg!.toStringAsFixed(4)),
      'lote_id': loteId,
      'custo_id': id,
      'itens': _itensDaBatida(c, batidas),
      'sacaria': double.parse((c.sacaria * batidas).toStringAsFixed(2)),
      'mao_obra': double.parse((c.maoDeObra * batidas).toStringAsFixed(2)),
    });
  }
  return id;
}

/// Ingredientes da batida com o preço do quilo na data.
List<Map<String, Object?>> _itensDaBatida(CalculoFormula c, double batidas) => [
      for (final l in c.linhas)
        {
          'insumo_id': l.insumo?['id'],
          'nome': l.nome,
          'kg': double.parse((l.kg * batidas).toStringAsFixed(3)),
          'preco_kg': l.custo == null ? null : double.parse((l.custo! / l.kg).toStringAsFixed(4)),
          'custo': l.custo == null ? null : double.parse((l.custo! * batidas).toStringAsFixed(2)),
        },
    ];

/// Histórico de batidas (mais recente primeiro), de uma fórmula ou de todas.
List<Reg> batidasFeitas({Object? formulaId}) {
  final fid = _int(formulaId);
  return [
    for (final b in Db.registros('batidas'))
      if (_int(b['propriedade_id']) == Db.pid && (fid == null || _int(b['formula_id']) == fid)) b,
  ]..sort((a, b) {
      final c = _t(b['data']).compareTo(_t(a['data']));
      return c != 0 ? c : (_int(b['id']) ?? 0).compareTo(_int(a['id']) ?? 0);
    });
}

/// Apaga a batida do histórico; o que saiu do estoque volta.
Future<void> excluirBatida(Reg b) async {
  final custo = _int(b['custo_id']);
  if (custo != null) {
    await Db.excluir('custos', custo); // apaga também o histórico e devolve o estoque
    return;
  }
  for (final e in Db.registros('estoque').where((x) => _t(x['grupo']) == _t(b['grupo']) && _t(b['grupo']).isNotEmpty).toList()) {
    await Db.excluir('estoque', _int(e['id'])!);
  }
  await Db.excluir('batidas', _int(b['id'])!);
}

/// Variação em % entre dois valores (null se não dá para comparar).
double? variacaoPct(double? antes, double? depois) =>
    antes == null || depois == null || antes <= 0 ? null : (depois - antes) / antes * 100;

// ---------- Preços dos insumos ----------

/// Preços lançados de um insumo (mais recente primeiro).
List<Reg> historicoPrecos(int insumoId) => [
      for (final p in Db.registros('precos_insumo'))
        if (_int(p['insumo_id']) == insumoId) p,
    ]..sort((a, b) {
        final c = _t(b['data']).compareTo(_t(a['data']));
        return c != 0 ? c : (_int(b['id']) ?? 0).compareTo(_int(a['id']) ?? 0);
      });

/// Lança o preço do insumo na data. O mais recente vira o preço usado nas contas.
Future<void> lancarPrecoInsumo(int insumoId, {required String data, required double precoEmbalagem, required double kgEmbalagem}) async {
  await Db.inserir('precos_insumo', {
    'propriedade_id': Db.pid,
    'insumo_id': insumoId,
    'data': data,
    'preco_saco': precoEmbalagem,
    'kg_saco': kgEmbalagem,
    'preco_kg': kgEmbalagem > 0 ? double.parse((precoEmbalagem / kgEmbalagem).toStringAsFixed(4)) : null,
  });
  final ultimo = historicoPrecos(insumoId).first;
  if (_int(ultimo['id']) == null || _t(ultimo['data']).compareTo(data) <= 0) {
    await Db.atualizar('insumos', insumoId, {'preco_saco': precoEmbalagem, 'kg_saco': kgEmbalagem});
  }
}

String _qtd(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

// ---------- Planilha de cálculo (28/08/2024) ----------

const _insumosPlanilha = <(String, double?, double)>[
  ('Núcleo', 97, 25),
  ('Núcleo Guedcy', 97, 30),
  ('Núcleo creep', 230, 40),
  ('Núcleo leite', null, 25),
  ('Calcário calcítico', null, 25),
  ('Fosfato bicálcico', null, 25),
  ('Sal branco', 20, 25),
  ('Farelo de soja', 150, 60),
  ('Farelo de arroz/torta de algodão', 90, 30),
  ('Milho', 80, 50),
  ('Ureia', 114, 50),
];

/// (nome, tipo, kg por insumo, g/dia, meses de seca, sacos, mão de obra)
const _formulasPlanilha = <(String, String, Map<String, double>, double, double, double, double)>[
  ('Nutroeste', 'Baixo consumo', {'Núcleo': 75, 'Sal branco': 200, 'Farelo de soja': 50, 'Milho': 150, 'Ureia': 25}, 450, 3, 12, 20),
  ('Fortaleza', 'Baixo consumo', {'Núcleo': 40, 'Sal branco': 120, 'Farelo de soja': 80, 'Milho': 140, 'Ureia': 20}, 450, 4, 0, 0),
  ('Guedcy', 'Baixo consumo', {'Núcleo Guedcy': 34.29, 'Sal branco': 114.29, 'Farelo de soja': 57.14, 'Farelo de arroz/torta de algodão': 22.86, 'Milho': 171.43}, 450, 4, 0, 0),
  ('Agrocria', 'Baixo consumo', {'Núcleo': 20, 'Calcário calcítico': 12, 'Fosfato bicálcico': 40, 'Sal branco': 120, 'Farelo de soja': 88, 'Milho': 80, 'Ureia': 40}, 450, 4, 0, 0),
  ('Nutroeste', 'Alto consumo', {'Núcleo': 120, 'Sal branco': 128, 'Farelo de soja': 200, 'Milho': 312, 'Ureia': 40}, 1000, 4, 0, 0),
  ('Guedcy', 'Alto consumo', {'Núcleo Guedcy': 34.29, 'Sal branco': 114.29, 'Farelo de soja': 57.14, 'Farelo de arroz/torta de algodão': 22.86, 'Milho': 171.43}, 2000, 4, 0, 0),
  ('Nutroeste 2', 'Alto consumo', {'Núcleo': 24, 'Sal branco': 28, 'Farelo de soja': 20, 'Milho': 308, 'Ureia': 20}, 2500, 4, 0, 0),
  ('Agrocria', 'Alto consumo', {'Núcleo': 12, 'Calcário calcítico': 6, 'Fosfato bicálcico': 20, 'Sal branco': 100, 'Farelo de soja': 24, 'Milho': 220, 'Ureia': 18}, 1000, 4, 0, 0),
  ('Nutroeste', 'Ração creep', {'Núcleo creep': 40, 'Milho': 360}, 4000, 4, 0, 0),
  // Referências para ajustar com o nutricionista (não vieram da planilha).
  ('Médio consumo', 'Médio consumo', {'Núcleo': 40, 'Sal branco': 60, 'Farelo de soja': 100, 'Milho': 180, 'Ureia': 20}, 700, 4, 0, 0),
  ('Concentrado leite', 'Ração leite', {'Núcleo leite': 12, 'Farelo de soja': 120, 'Milho': 260, 'Ureia': 8}, 3000, 12, 0, 0),
];

/// Cria os insumos e as fórmulas prontas (planilha e referências) que ainda não existem na propriedade.
Future<int> carregarPlanilhaProteinado() async {
  final pid = Db.pid;
  final ids = {for (final i in insumos()) _t(i['nome']).toLowerCase(): _int(i['id'])!};
  for (final (nome, preco, kg) in _insumosPlanilha) {
    if (ids.containsKey(nome.toLowerCase())) continue;
    ids[nome.toLowerCase()] = await Db.inserir('insumos', {
      'propriedade_id': pid,
      'nome': nome,
      'categoria': 'Ração e ingredientes',
      'unidade': 'kg',
      'preco_saco': preco,
      'kg_saco': kg,
    });
  }
  final existentes = {for (final f in formulas()) '${tipoFormula(f)}|${f['nome']}'.toLowerCase()};
  var novas = 0;
  for (final (nome, tipo, itens, g, meses, sacos, mo) in _formulasPlanilha) {
    if (existentes.contains('$tipo|$nome'.toLowerCase())) continue;
    await Db.inserir('formulas', {
      'propriedade_id': pid,
      'nome': nome,
      'tipo': tipo,
      'itens': [for (final e in itens.entries) {'insumo_id': ids[e.key.toLowerCase()], 'kg': e.value}],
      'saco_qtd': sacos,
      'saco_preco': sacos > 0 ? 1.0 : 0.0,
      'mao_obra': mo,
      'consumo_g': g,
      'cabecas': 1,
      'meses': meses,
    });
    novas++;
  }
  return novas;
}

// ---------- Cotação da arroba ----------

const siteCotacaoBoi = 'https://www.noticiasagricolas.com.br/cotacoes/boi-gordo';

/// Cotações lançadas (mais recente primeiro). Valem para todas as propriedades.
List<Reg> cotacoes() => [...Db.registros('cotacoes')]..sort((a, b) {
    final c = _t(b['data']).compareTo(_t(a['data']));
    return c != 0 ? c : (_int(b['id']) ?? 0).compareTo(_int(a['id']) ?? 0);
  });

/// Lança a arroba do dia e passa a usá-la na projeção de abate e nos custos.
Future<int> registrarCotacao({required String data, required double valor, String? praca}) async {
  final id = await Db.inserir('cotacoes', {'data': data, 'valor': valor, 'praca': praca});
  await _usarUltima();
  return id;
}

Future<void> excluirCotacao(int id) async {
  await Db.excluir('cotacoes', id);
  await _usarUltima();
}

Future<void> _usarUltima() async {
  final ultima = cotacoes().firstOrNull;
  if (ultima == null) return;
  final abate = Db.registro('config', 'abate') ?? const {};
  await Db.salvarConfig('abate', {...abate, 'arroba': ultima['valor']}..remove('id'));
}
