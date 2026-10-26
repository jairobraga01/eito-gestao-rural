// Registro de quem lançou o quê: cada gravação leva criado_por/criado_nome/
// criado_em (ou alterado_*) — veja Db._carimbar.
import 'db.dart';

const nomesTabela = {
  'propriedades': 'Propriedade',
  'lotes': 'Lote',
  'piquetes': 'Piquete/Pasto',
  'pastagens': 'Pastagem',
  'pontos': 'Ponto do mapa',
  'ocorrencias': 'Ocorrência',
  'contagens': 'Contagem',
  'saidas': 'Saída',
  'entradas': 'Entrada',
  'semens': 'Sêmen',
  'protocolos': 'Protocolo',
  'estacoes': 'Estação de monta',
  'custos': 'Custo',
  'chuvas': 'Chuva',
  'insumos': 'Insumo',
  'formulas': 'Fórmula',
  'dividas': 'Dívida',
  'contas': 'Conta',
  'cotacoes': 'Cotação',
  'estoque': 'Estoque',
  'dietas': 'Dieta',
  'tarefas': 'Tarefa',
  'animais': 'Animal',
  'reproducoes': 'Reprodução',
  'sanidade': 'Sanidade',
  'pesagens': 'Pesagem',
  'escores': 'Escore (ECC)',
  'ordenhas': 'Ordenha',
};

class Lancamento {
  const Lancamento({
    required this.tabela,
    required this.registro,
    required this.quando,
    required this.quem,
    required this.quemUid,
    required this.alterou,
  });
  final String tabela;
  final Reg registro;
  final String quando;
  final String quem;
  final String quemUid;
  final bool alterou;

  String get oQue => nomesTabela[tabela] ?? tabela;

  /// Brinco, nome ou título que identifica o registro.
  String get detalhe {
    final r = registro;
    final animal = r['animal_id'] ?? r['femea_id'];
    if (animal != null) {
      final a = Db.registro('animais', animal);
      if (a != null) return 'Brinco ${a['brinco'] ?? '-'}';
    }
    for (final c in ['brinco', 'nome', 'titulo', 'descricao', 'tipo', 'produto']) {
      final v = r[c];
      if (v != null && '$v'.trim().isNotEmpty) return c == 'brinco' ? 'Brinco $v' : '$v';
    }
    return '';
  }
}

/// Lançamentos mais recentes da propriedade aberta, de todos ou de [uid].
List<Lancamento> lancamentos({String? uid, int limite = 300}) {
  final pid = Db.pid;
  final daProp = <int>{
    for (final a in Db.registros('animais'))
      if (a['propriedade_id'] == pid) a['id'] as int,
  };
  final lista = <Lancamento>[];
  for (final t in nomesTabela.keys) {
    for (final r in Db.registros(t)) {
      final prop = r['propriedade_id'];
      final animal = r['animal_id'] ?? r['femea_id'];
      if (t == 'propriedades') {
        if (r['id'] != pid) continue;
      } else if (prop != null) {
        if (prop != pid) continue;
      } else if (animal != null) {
        if (!daProp.contains(animal)) continue;
      } else if (r['piquete_id'] != null) {
        // Pastagens só guardam o piquete: a fazenda vem dele.
        if (Db.registro('piquetes', r['piquete_id'])?['propriedade_id'] != pid) continue;
      }
      final alterou = r['alterado_em'] != null;
      final quando = '${r[alterou ? 'alterado_em' : 'criado_em'] ?? ''}';
      if (quando.isEmpty) continue;
      final quemUid = '${r[alterou ? 'alterado_por' : 'criado_por'] ?? ''}';
      if (uid != null && quemUid != uid) continue;
      lista.add(Lancamento(
        tabela: t,
        registro: r,
        quando: quando,
        quem: '${r[alterou ? 'alterado_nome' : 'criado_nome'] ?? ''}',
        quemUid: quemUid,
        alterou: alterou,
      ));
    }
  }
  lista.sort((a, b) => b.quando.compareTo(a.quando));
  return lista.take(limite).toList();
}
