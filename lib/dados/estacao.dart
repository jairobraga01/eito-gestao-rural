// Estação de monta (resultado acumulado, custo por bezerro desmamado),
// vacas problema e previsão de partos pela sexagem fetal.
import 'db.dart';
import 'iatf.dart';
import 'indicadores.dart' show eccEm;
import 'manejo.dart' show partosDaVaca;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _n(Object? v) => v is num ? v.toDouble() : 0;
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);

int _dias(String de, String ate) {
  final a = DateTime.parse(_dia(de)), b = DateTime.parse(_dia(ate));
  return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

int? _meses(Object? nascimento, String data) {
  final n = DateTime.tryParse(_dia(nascimento)), d = DateTime.tryParse(_dia(data));
  if (n == null || d == null) return null;
  var m = (d.year - n.year) * 12 + d.month - n.month;
  if (d.day < n.day) m--;
  return m;
}

bool _entre(Object? data, String de, String ate) => _dia(data).compareTo(de) >= 0 && _dia(data).compareTo(ate) <= 0;

/// Duração de um ciclo estral (dias): a estação é contada em ciclos de 21 dias.
const diasCiclo = 21;

List<Reg> estacoes() => [
      for (final e in Db.registros('estacoes'))
        if (_int(e['propriedade_id']) == Db.pid) e,
    ]..sort((a, b) => _dia(b['inicio']).compareTo(_dia(a['inicio'])));

Future<int> salvarEstacao(Reg v, {int? id}) async {
  if (id != null) {
    await Db.atualizar('estacoes', id, v);
    return id;
  }
  return Db.inserir('estacoes', {...v, 'propriedade_id': Db.pid});
}

class CicloEstacao {
  CicloEstacao(this.numero, this.de, this.ate);
  final int numero;
  final String de, ate;
  int prenhes = 0;
  int acumulado = 0;
}

class ResultadoEstacao {
  ResultadoEstacao(this.estacao);
  final Reg estacao;
  String get inicio => _dia(estacao['inicio']);
  String get fim => _dia(estacao['fim']);

  /// Fêmeas aptas: ativas (ou que saíram depois do início), com 12 meses ou mais
  /// no início (ou categoria Novilha/Vaca) e que não estavam prenhes ao começar.
  final aptas = <int, Reg>{};
  final servidas = <int>{};
  final prenhes = <int, Reg>{}; // vaca → serviço que emprenhou
  final vazias = <int>{};
  final aguardando = <int>{};
  final ciclos = <CicloEstacao>[];
  int prenhesIatf = 0, prenhesRepasse = 0;

  List<Reg> get naoServidas => [for (final e in aptas.entries) if (!servidas.contains(e.key)) e.value];
  double? _sobreAptas(int n) => aptas.isEmpty ? null : n / aptas.length;
  double? get taxaServico => _sobreAptas(servidas.length);
  double? get taxaPrenhez => _sobreAptas(prenhes.length);

  // ---- Custos ----
  double custoSemen = 0, custoHormonios = 0;
  double get outrosCustos => _n(estacao['outros_custos']);
  double get custoTotal => custoSemen + custoHormonios + outrosCustos;
  int bezerrosNascidos = 0, bezerrosDesmamados = 0;
  double? get custoPorPrenhez => prenhes.isEmpty ? null : custoTotal / prenhes.length;
  double? get custoPorDesmamado => bezerrosDesmamados == 0 ? null : custoTotal / bezerrosDesmamados;
}

/// Serviço prenhe (ou que pariu) da fêmea, ainda sem parto, feito antes de [data].
bool _prenheAntes(int vaca, String data) => Db.registros('reproducoes').any((r) =>
    _int(r['femea_id']) == vaca &&
    _dia(r['data']).compareTo(data) < 0 &&
    situacaoServico(r) == SituacaoIatf.prenhe &&
    (r['parto_data'] == null || _dia(r['parto_data']).compareTo(data) >= 0));

ResultadoEstacao resultadoEstacao(Reg estacao) {
  final r = ResultadoEstacao(estacao);
  final de = r.inicio, ate = r.fim.isEmpty ? '9999-12-31' : r.fim;

  final servicos = <int, List<Reg>>{};
  for (final s in Db.registros('reproducoes')) {
    if (_entre(s['data'], de, ate)) servicos.putIfAbsent(_int(s['femea_id'])!, () => []).add(s);
  }

  for (final a in Db.registros('animais')) {
    if (_int(a['propriedade_id']) != Db.pid || a['sexo'] != 'F') continue;
    final id = _int(a['id'])!;
    final saida = a['saida_id'] == null ? null : _dia(Db.registro('saidas', a['saida_id'])?['data']);
    if (a['status'] != 'Ativo' && (saida == null || saida.compareTo(de) < 0) && !servicos.containsKey(id)) continue;
    final idade = _meses(a['nascimento'], de);
    final idadeOk = idade == null ? (a['categoria'] == 'Vaca' || a['categoria'] == 'Novilha') : idade >= 12;
    if (!idadeOk && !servicos.containsKey(id)) continue;
    if (_prenheAntes(id, de)) continue;
    r.aptas[id] = a;
  }

  for (final e in servicos.entries) {
    if (!r.aptas.containsKey(e.key)) continue;
    r.servidas.add(e.key);
    final lista = e.value..sort((x, y) => _dia(x['data']).compareTo(_dia(y['data'])));
    final prenhe = lista.where((s) => situacaoServico(s) == SituacaoIatf.prenhe).firstOrNull;
    if (prenhe != null) {
      r.prenhes[e.key] = prenhe;
      prenhe['tipo'] == 'Monta natural' ? r.prenhesRepasse++ : r.prenhesIatf++;
    } else if (lista.any((s) => situacaoServico(s) == SituacaoIatf.aguardando)) {
      r.aguardando.add(e.key);
    } else {
      r.vazias.add(e.key);
    }
    for (final s in lista) {
      if (s['custo_dose'] is num) r.custoSemen += (s['custo_dose'] as num).toDouble();
    }
  }

  // Prenhez acumulada por ciclo de 21 dias, pela data do serviço que emprenhou.
  final ultimo = r.fim.isEmpty
      ? [for (final s in r.prenhes.values) _dia(s['data'])].fold(de, (m, d) => d.compareTo(m) > 0 ? d : m)
      : r.fim;
  var acumulado = 0;
  for (var i = 0; Db.dataEtapa(de, i * diasCiclo).compareTo(ultimo) <= 0; i++) {
    final c = CicloEstacao(i + 1, Db.dataEtapa(de, i * diasCiclo), Db.dataEtapa(de, (i + 1) * diasCiclo - 1));
    c.prenhes = r.prenhes.values.where((s) => _entre(s['data'], c.de, c.ate)).length;
    acumulado += c.prenhes;
    c.acumulado = acumulado;
    r.ciclos.add(c);
  }

  // Hormônios dos protocolos com D0 dentro da estação.
  for (final p in Db.registros('protocolos')) {
    if (_int(p['propriedade_id']) == Db.pid && _entre(p['inicio'], de, ate)) r.custoHormonios += custoHormonal(p).$2;
  }

  // Bezerros: crias dos serviços que emprenharam; desmamados = com pesagem de desmama.
  final desmamados = {
    for (final p in Db.registros('pesagens'))
      if (p['evento'] == 'Desmama') _int(p['animal_id']),
  };
  for (final s in r.prenhes.values) {
    final cria = _int(s['cria_id']);
    if (cria == null) continue;
    r.bezerrosNascidos++;
    if (desmamados.contains(cria)) r.bezerrosDesmamados++;
  }
  return r;
}

// ---------- Previsão de partos (sexagem fetal) ----------

class MesPartos {
  MesPartos(this.mes);

  /// yyyy-mm
  final String mes;
  int femeas = 0, machos = 0, semSexagem = 0;
  int get total => femeas + machos + semSexagem;
}

/// Partos previstos das prenhes ainda sem parto, por mês, com o sexo do feto quando sexado.
List<MesPartos> previsaoPartos() {
  final meses = <String, MesPartos>{};
  for (final r in Db.registros('reproducoes')) {
    if (r['parto_data'] != null || situacaoServico(r) != SituacaoIatf.prenhe) continue;
    final a = Db.registro('animais', r['femea_id']);
    if (a == null || _int(a['propriedade_id']) != Db.pid || a['status'] != 'Ativo') continue;
    final parto = _dia(r['parto_previsto']).isEmpty ? _t(Db.partoPrevisto(r['data'])) : _dia(r['parto_previsto']);
    if (parto.length < 7) continue;
    final m = meses.putIfAbsent(parto.substring(0, 7), () => MesPartos(parto.substring(0, 7)));
    switch (r['sexo_feto']) {
      case 'Fêmea':
        m.femeas++;
      case 'Macho':
        m.machos++;
      default:
        m.semSexagem++;
    }
  }
  return meses.values.toList()..sort((a, b) => a.mes.compareTo(b.mes));
}

// ---------- Vacas problema ----------

class VacaProblema {
  VacaProblema(this.vaca, this.motivos);
  final Reg vaca;
  final List<String> motivos;
}

/// Fêmeas que pedem atenção ou descarte: falhas seguidas, muito tempo sem
/// parir, novilha passada da idade, ECC baixo ou perda embrionária.
List<VacaProblema> vacasProblema(String hoje) {
  final r = <VacaProblema>[];
  final porVaca = <int, List<Reg>>{};
  for (final s in Db.registros('reproducoes')) {
    porVaca.putIfAbsent(_int(s['femea_id'])!, () => []).add(s);
  }
  for (final a in Db.registros('animais')) {
    if (_int(a['propriedade_id']) != Db.pid || a['status'] != 'Ativo' || a['sexo'] != 'F') continue;
    final id = _int(a['id'])!;
    final idade = _meses(a['nascimento'], hoje);
    if (a['categoria'] == 'Bezerra' || (idade != null && idade < 18)) continue;
    final servicos = porVaca[id] ?? const [];
    final prenhe = servicos.any((s) => s['parto_data'] == null && situacaoServico(s) == SituacaoIatf.prenhe);
    final partos = partosDaVaca(id);
    final desde = partos.isEmpty ? '' : partos.last;
    final motivos = <String>[];

    final falhas = servicos
        .where((s) => _dia(s['data']).compareTo(desde) > 0 && situacaoServico(s) == SituacaoIatf.vazia)
        .length;
    if (falhas >= 2 && !prenhe) motivos.add('$falhas serviços vazios desde o último parto');
    if (!prenhe && partos.isNotEmpty && _dias(desde, hoje) > 365) {
      motivos.add('${_dias(desde, hoje)} dias sem parir e não está prenhe');
    }
    if (!prenhe && partos.isEmpty && idade != null && idade >= 30) {
      motivos.add('novilha com $idade meses e não emprenhou');
    }
    final ecc = eccEm(id, hoje);
    if (ecc != null && ecc <= 2) motivos.add('ECC baixo (${ecc.toStringAsFixed(1).replaceAll('.', ',')})');
    final perdas = servicos.where((s) => s['perda'] == true).length;
    if (perdas > 0) motivos.add(perdas == 1 ? 'teve perda embrionária' : '$perdas perdas embrionárias');
    if (a['descarte'] == true) motivos.add('já marcada para descarte');
    if (motivos.isNotEmpty) r.add(VacaProblema(a, motivos));
  }
  return r..sort((a, b) => b.motivos.length.compareTo(a.motivos.length));
}
