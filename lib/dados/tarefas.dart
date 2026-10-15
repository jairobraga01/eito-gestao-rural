// Tarefas para a equipe: o dono ou o gerente cria e escolhe quem faz;
// o peão vê as dele (e as de qualquer um) e marca como feita.
import 'db.dart';

String _hoje() => DateTime.now().toIso8601String().substring(0, 10);

/// Tarefas da propriedade aberta. [paraUid]: só as dessa pessoa e as sem responsável.
List<Reg> tarefas({bool? feitas, String? paraUid}) {
  final lista = Db.registros('tarefas').where((t) {
    if (t['propriedade_id'] != Db.pid) return false;
    if (feitas != null && (t['feita'] == true) != feitas) return false;
    if (paraUid != null && t['responsavel'] != null && t['responsavel'] != paraUid) return false;
    return true;
  }).toList();
  // Abertas: prazo mais perto primeiro (sem prazo no fim). Feitas: as mais recentes.
  lista.sort((a, b) {
    if (feitas == true) return '${b['feita_em'] ?? ''}'.compareTo('${a['feita_em'] ?? ''}');
    final x = '${a['prazo'] ?? '9999'}', y = '${b['prazo'] ?? '9999'}';
    return x.compareTo(y);
  });
  return lista;
}

bool tarefaAtrasada(Reg t, [String? hoje]) =>
    t['feita'] != true && t['prazo'] != null && '${t['prazo']}'.compareTo(hoje ?? _hoje()) < 0;

Future<int> salvarTarefa(Reg v, {int? id}) async {
  if (id != null) {
    await Db.atualizar('tarefas', id, v);
    return id;
  }
  return Db.inserir('tarefas', {'feita': false, ...v, 'propriedade_id': Db.pid});
}

Future<void> concluirTarefa(int id, bool feita) => Db.atualizar('tarefas', id, {
      'feita': feita,
      'feita_em': feita ? DateTime.now().toIso8601String() : null,
      'feita_nome': feita ? Db.autor?.nome : null,
    });
