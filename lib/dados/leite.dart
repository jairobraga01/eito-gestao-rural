// Produção leiteira: litros por vaca e por dia, e o relatório do mês ou do ano.
import 'db.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _n(Object? v) => v is num ? v.toDouble() : 0;
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);
String _dois(int n) => n.toString().padLeft(2, '0');

int _porBrinco(Reg a, Reg b) {
  final x = int.tryParse(_t(a['brinco'])), y = int.tryParse(_t(b['brinco']));
  return x != null && y != null ? x.compareTo(y) : _t(a['brinco']).compareTo(_t(b['brinco']));
}

/// Fêmeas ativas marcadas como leiteiras na propriedade aberta.
List<Reg> vacasLeiteiras() => [
      for (final a in Db.registros('animais'))
        if (_int(a['propriedade_id']) == Db.pid && a['status'] == 'Ativo' && a['sexo'] == 'F' && a['leiteira'] == true) a,
    ]..sort(_porBrinco);

/// Marca como leiteiras só as fêmeas de [ids]; as demais deixam de ser.
Future<void> definirLeiteiras(Iterable<int> ids) async {
  final marcar = ids.toSet();
  for (final a in Db.registros('animais')) {
    if (_int(a['propriedade_id']) != Db.pid) continue;
    final id = _int(a['id'])!;
    final deve = marcar.contains(id) && a['sexo'] == 'F';
    if ((a['leiteira'] == true) != deve) await Db.atualizar('animais', id, {'leiteira': deve});
  }
}

Reg? _ordenha(int animalId, String data) {
  for (final o in Db.registros('ordenhas')) {
    if (_int(o['animal_id']) == animalId && _dia(o['data']) == data) return o;
  }
  return null;
}

/// Litros de cada vaca no dia.
Map<int, double> ordenhasDoDia(String data) => {
      for (final o in Db.registros('ordenhas'))
        if (_dia(o['data']) == data && _int(o['propriedade_id']) == Db.pid) _int(o['animal_id'])!: _n(o['litros']),
    };

/// Grava os litros do dia da vaca (um lançamento por vaca e dia; vazio apaga).
Future<void> lancarOrdenha(int animalId, String data, double? litros) async {
  final atual = _ordenha(animalId, data);
  if (litros == null || litros <= 0) {
    if (atual != null) await Db.excluir('ordenhas', _int(atual['id'])!);
  } else if (atual == null) {
    await Db.inserir('ordenhas', {'propriedade_id': Db.pid, 'animal_id': animalId, 'data': data, 'litros': litros});
  } else if (_n(atual['litros']) != litros) {
    await Db.atualizar('ordenhas', _int(atual['id'])!, {'litros': litros});
  }
}

class LeiteVaca {
  LeiteVaca(this.vaca);
  final Reg vaca;
  double litros = 0;
  final dias = <String>{};
  double get media => dias.isEmpty ? 0 : litros / dias.length;
}

/// Produção do período (datas ISO incluídas): por vaca, total e por mês.
class ProducaoLeite {
  ProducaoLeite(this.de, this.ate) {
    final porVaca = <int, LeiteVaca>{};
    for (final o in Db.registros('ordenhas')) {
      final d = _dia(o['data']);
      if (_int(o['propriedade_id']) != Db.pid || d.compareTo(de) < 0 || d.compareTo(ate) > 0) continue;
      final id = _int(o['animal_id'])!;
      final vaca = Db.registro('animais', id);
      if (vaca == null) continue;
      final l = _n(o['litros']);
      porVaca.putIfAbsent(id, () => LeiteVaca(vaca))
        ..litros += l
        ..dias.add(d);
      total += l;
      diasComOrdenha.add(d);
      porMes[int.parse(d.substring(5, 7)) - 1] += l;
    }
    vacas = porVaca.values.toList()..sort((a, b) => b.litros.compareTo(a.litros));
  }

  factory ProducaoLeite.mes(int ano, int mes) =>
      ProducaoLeite('$ano-${_dois(mes)}-01', '$ano-${_dois(mes)}-${_dois(DateTime(ano, mes + 1, 0).day)}');
  factory ProducaoLeite.ano(int ano) => ProducaoLeite('$ano-01-01', '$ano-12-31');

  final String de, ate;
  double total = 0;
  final diasComOrdenha = <String>{};
  final porMes = List<double>.filled(12, 0);
  late final List<LeiteVaca> vacas;

  /// Litros por vaca ordenhada por dia (soma dos dias de cada vaca).
  double get mediaVacaDia {
    final diasVaca = vacas.fold<int>(0, (s, v) => s + v.dias.length);
    return diasVaca == 0 ? 0 : total / diasVaca;
  }

  /// Litros do rebanho por dia de ordenha.
  double get mediaDia => diasComOrdenha.isEmpty ? 0 : total / diasComOrdenha.length;
}
