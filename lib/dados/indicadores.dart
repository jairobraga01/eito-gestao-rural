// Carência na venda, declaração de rebanho, escore de condição corporal (ECC),
// indicadores de cria e fluxo de caixa projetado da propriedade aberta.
import 'db.dart';
import 'dividas.dart' show dividas, parcelas;
import 'gestao.dart' show ajustesArroba;
import 'manejo.dart' show projetarAnimal, valorArroba;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _num(Object? v) => v is num ? v.toDouble() : null;
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);
String _dois(int n) => n.toString().padLeft(2, '0');
String _iso(DateTime d) => '${d.year}-${_dois(d.month)}-${_dois(d.day)}';
String _somaDias(String iso, int dias) => _iso(DateTime.parse(iso).add(Duration(days: dias)));

/// Idade em meses na data [em], ou null sem nascimento.
int? _meses(Reg a, String em) {
  final n = DateTime.tryParse(_dia(a['nascimento']));
  if (n == null) return null;
  final h = DateTime.parse(em);
  var m = (h.year - n.year) * 12 + h.month - n.month;
  if (h.day < n.day) m--;
  return m < 0 ? 0 : m;
}

Iterable<Reg> _animaisDaProp() => Db.registros('animais').where((a) => _int(a['propriedade_id']) == Db.pid);

// ---------- Carência ----------

class Carencia {
  Carencia(this.animal, this.produto, this.libera);
  final Reg animal;
  final String produto;

  /// Primeiro dia em que o animal pode ser vendido para abate (yyyy-mm-dd).
  final String libera;
}

/// Animais de [animalIds] que ainda estarão em carência na data [data].
/// Vale o produto com a carência mais longa de cada animal.
List<Carencia> emCarencia(Iterable<int> animalIds, String data) {
  final ids = animalIds.toSet();
  final pior = <int, Carencia>{};
  for (final s in Db.registros('sanidade')) {
    final id = _int(s['animal_id']);
    final dias = _int(s['carencia']) ?? 0;
    if (id == null || !ids.contains(id) || dias <= 0 || _dia(s['data']).length < 10) continue;
    final libera = _somaDias(_dia(s['data']), dias + 1);
    if (libera.compareTo(data) <= 0) continue;
    final a = Db.registro('animais', id);
    if (a == null) continue;
    if (pior[id] == null || libera.compareTo(pior[id]!.libera) > 0) pior[id] = Carencia(a, _t(s['produto']), libera);
  }
  return pior.values.toList()..sort((a, b) => a.libera.compareTo(b.libera));
}

// ---------- Declaração de rebanho ----------

/// Faixas de idade usadas nas declarações de rebanho e de vacinação dos estados.
const faixasDeclaracao = ['0 a 12 meses', '13 a 24 meses', '25 a 36 meses', 'Acima de 36 meses', 'Sem nascimento'];

String _faixa(int? meses) {
  if (meses == null) return faixasDeclaracao[4];
  if (meses <= 12) return faixasDeclaracao[0];
  if (meses <= 24) return faixasDeclaracao[1];
  if (meses <= 36) return faixasDeclaracao[2];
  return faixasDeclaracao[3];
}

class LinhaDeclaracao {
  LinhaDeclaracao(this.faixa);
  final String faixa;
  int machos = 0, femeas = 0;
  int get total => machos + femeas;
}

/// Animais ativos da propriedade por faixa de idade e sexo na data [data].
List<LinhaDeclaracao> declaracaoRebanho(String data) {
  final linhas = {for (final f in faixasDeclaracao) f: LinhaDeclaracao(f)};
  for (final a in _animaisDaProp()) {
    if (a['status'] != 'Ativo') continue;
    final l = linhas[_faixa(_meses(a, data))]!;
    if (a['sexo'] == 'M') {
      l.machos++;
    } else {
      l.femeas++;
    }
  }
  return linhas.values.where((l) => l.total > 0 || l.faixa != faixasDeclaracao[4]).toList();
}

/// Texto da declaração para copiar ou mandar ao escritório.
String textoDeclaracao(String data, List<LinhaDeclaracao> linhas) {
  final nome = _t(Db.prop.value?['nome']);
  final b = StringBuffer('Declaração de rebanho${nome.isEmpty ? '' : ' – $nome'}\n'
      'Data: ${data.substring(8, 10)}/${data.substring(5, 7)}/${data.substring(0, 4)}\n\n');
  var m = 0, f = 0;
  for (final l in linhas) {
    b.writeln('${l.faixa}: ${l.machos} machos, ${l.femeas} fêmeas (${l.total})');
    m += l.machos;
    f += l.femeas;
  }
  b.write('\nTotal: $m machos, $f fêmeas (${m + f} cabeças)');
  return b.toString();
}

// ---------- Escore de condição corporal ----------

/// Notas de ECC na escala de 1 a 5, de meio em meio ponto.
const notasEcc = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0];

Future<int> lancarEcc(int animalId, String data, double ecc) =>
    Db.inserir('escores', {'animal_id': animalId, 'data': data, 'ecc': ecc});

List<Reg> escoresDoAnimal(int animalId) => [
      for (final e in Db.registros('escores'))
        if (_int(e['animal_id']) == animalId) e,
    ]..sort((a, b) => _dia(b['data']).compareTo(_dia(a['data'])));

/// Último ECC do animal até a data, se lançado nos [janela] dias antes dela.
double? eccEm(int animalId, String data, {int janela = 90}) {
  final inicio = _somaDias(data, -janela);
  for (final e in escoresDoAnimal(animalId)) {
    final d = _dia(e['data']);
    if (d.compareTo(data) > 0) continue;
    return d.compareTo(inicio) >= 0 ? _num(e['ecc']) : null;
  }
  return null;
}

const faixasEcc = ['Até 2,5', '3,0', '3,5 ou mais'];

String _faixaEcc(double ecc) => ecc <= 2.5 ? faixasEcc[0] : (ecc < 3.5 ? faixasEcc[1] : faixasEcc[2]);

/// Prenhez dos serviços já diagnosticados pelo ECC da fêmea no dia do serviço:
/// faixa → (prenhes, diagnosticadas).
Map<String, (int, int)> prenhezPorEcc() {
  final r = {for (final f in faixasEcc) f: (0, 0)};
  for (final s in Db.registros('reproducoes')) {
    final d = s['diagnostico'];
    if (d != 'Prenhe' && d != 'Vazia') continue;
    final f = Db.registro('animais', s['femea_id']);
    if (f == null || _int(f['propriedade_id']) != Db.pid) continue;
    final ecc = eccEm(_int(f['id'])!, _dia(s['data']));
    if (ecc == null) continue;
    final k = _faixaEcc(ecc);
    final (p, n) = r[k]!;
    r[k] = (p + (d == 'Prenhe' ? 1 : 0), n + 1);
  }
  return r;
}

// ---------- Indicadores de cria ----------

class IndicadoresCria {
  IndicadoresCria(this.ano);
  final int ano;

  /// Fêmeas com 24 meses ou mais (ou categoria Vaca) no rebanho em 1º de janeiro.
  int matrizes = 0;
  int nascimentos = 0, mortesBezerros = 0, desmamados = 0;
  double kgDesmamados = 0;

  /// Mortes do ano (todas as idades) pela causa informada na saída.
  final mortesPorCausa = <String, int>{};

  double? _por(num v) => matrizes == 0 ? null : v / matrizes;
  double? get natalidade => _por(nascimentos);
  double? get taxaDesmame => _por(desmamados);
  double? get kgPorMatriz => _por(kgDesmamados);
  double? get pesoMedioDesmama => desmamados == 0 ? null : kgDesmamados / desmamados;
  double? get mortalidadeBezerros => nascimentos == 0 ? null : mortesBezerros / nascimentos;
}

IndicadoresCria indicadoresCria(int ano) {
  final r = IndicadoresCria(ano);
  final inicio = '$ano-01-01', fim = '$ano-12-31';
  bool dentro(Object? d) => _dia(d).compareTo(inicio) >= 0 && _dia(d).compareTo(fim) <= 0;
  final animais = {for (final a in _animaisDaProp()) _int(a['id']): a};
  String? saiuEm(Reg a) => a['saida_id'] == null ? null : _dia(Db.registro('saidas', a['saida_id'])?['data']);

  for (final a in animais.values) {
    final saida = saiuEm(a);
    if (a['sexo'] == 'F' && (saida == null || saida.compareTo(inicio) >= 0)) {
      final n = _dia(a['nascimento']);
      final nascida = n.isEmpty || n.compareTo(inicio) < 0;
      final meses = _meses(a, inicio);
      if (nascida && ((meses != null && meses >= 24) || (meses == null && a['categoria'] == 'Vaca'))) r.matrizes++;
    }
    if (a['mae_id'] != null && dentro(a['nascimento'])) {
      r.nascimentos++;
      if (a['status'] == 'Morto' && saida != null) {
        final idade = _meses(a, saida);
        if (idade != null && idade < 12) r.mortesBezerros++;
      }
    }
  }
  final desmamas = <int?, double>{};
  for (final p in Db.registros('pesagens')) {
    final id = _int(p['animal_id']);
    if (p['evento'] != 'Desmama' || !animais.containsKey(id) || !dentro(p['data']) || p['peso'] is! num) continue;
    desmamas[id] = (p['peso'] as num).toDouble(); // uma desmama por bezerro
  }
  r.desmamados = desmamas.length;
  r.kgDesmamados = desmamas.values.fold(0.0, (s, v) => s + v);

  for (final s in Db.registros('saidas')) {
    if (s['tipo'] != 'Morte' || _int(s['propriedade_id']) != Db.pid || !dentro(s['data'])) continue;
    final causa = _t(s['destino']).trim().isEmpty ? 'Sem causa informada' : _t(s['destino']).trim();
    final n = animais.values.where((a) => _int(a['saida_id']) == _int(s['id'])).length;
    r.mortesPorCausa[causa] = (r.mortesPorCausa[causa] ?? 0) + (n == 0 ? 1 : n);
  }
  return r;
}

// ---------- Fluxo de caixa projetado ----------

class MesCaixa {
  MesCaixa(this.mes);

  /// yyyy-mm
  final String mes;
  double vendas = 0, parcelas = 0, custos = 0;
  int cabecas = 0;
  double get saldo => vendas - parcelas - custos;
}

class FluxoCaixa {
  FluxoCaixa(this.meses, this.custoMensal, this.semArroba);
  final List<MesCaixa> meses;

  /// Média mensal dos custos lançados nos 3 meses completos anteriores.
  final double custoMensal;

  /// Sem preço da arroba na projeção de abate as vendas não entram.
  final bool semArroba;
}

/// Próximos [quantos] meses a partir de [hoje]: vendas pela projeção de abate
/// (peso alvo × arroba salvos), parcelas de dívidas em aberto (as vencidas
/// entram no primeiro mês) e a média dos custos recentes.
FluxoCaixa fluxoCaixa(String hoje, {int quantos = 6}) {
  final h = DateTime.parse(hoje);
  final meses = [
    for (var i = 0; i < quantos; i++) MesCaixa('${DateTime(h.year, h.month + i).year}-${_dois(DateTime(h.year, h.month + i).month)}'),
  ];
  final porMes = {for (final m in meses) m.mes: m};
  MesCaixa? mesDe(String iso) {
    if (iso.length < 7) return null;
    final k = iso.substring(0, 7);
    if (k.compareTo(meses.first.mes) < 0) return meses.first;
    return porMes[k];
  }

  // Custos: média dos 3 meses completos antes deste.
  final de = _iso(DateTime(h.year, h.month - 3, 1)), ate = _iso(DateTime(h.year, h.month, 0));
  var soma = 0.0;
  for (final c in Db.registros('custos')) {
    if (_int(c['propriedade_id']) != Db.pid) continue;
    final d = _dia(c['data']);
    if (d.compareTo(de) >= 0 && d.compareTo(ate) <= 0) soma += _num(c['valor']) ?? 0;
  }
  final custoMensal = soma / 3;
  for (final m in meses) {
    m.custos = custoMensal;
  }

  for (final d in dividas()) {
    for (final p in parcelas(d)) {
      if (p['pago'] == true) continue;
      final m = mesDe(_dia(p['vencimento']));
      m?.parcelas += _num(p['valor']) ?? 0;
    }
  }

  final (rend, arroba) = ajustesArroba();
  final alvo = _num(Db.registro('config', 'abate')?['alvo']) ?? 540;
  if (arroba != null) {
    final pesagens = <int?, List<Reg>>{};
    for (final p in Db.registros('pesagens')) {
      pesagens.putIfAbsent(_int(p['animal_id']), () => []).add(p);
    }
    for (final a in _animaisDaProp()) {
      if (a['status'] != 'Ativo') continue;
      final pr = projetarAnimal(a, pesagens[_int(a['id'])] ?? const [], alvo);
      if (pr?.dias == null) continue;
      final m = mesDe(_somaDias(hoje, pr!.dias!));
      if (m == null) continue;
      m.vendas += valorArroba(alvo, rend, arroba);
      m.cabecas++;
    }
  }
  return FluxoCaixa(meses, custoMensal, arroba == null);
}
