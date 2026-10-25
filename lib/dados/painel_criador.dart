// Contas do Painel do criador que não cabem na tela: saúde da conta, estado
// pelo DDD, pagamentos, histórico de mudanças e tempo de resposta.
//
// Coleções no Firestore (só o administrador, ver firestore.rules):
//   pagamentos/{id}         pagamento registrado à mão (uid, plano, periodo, valor, data)
//   contas_historico/{id}   o que o criador mudou na conta (uid, acao, detalhe, em)
//   respostas_prontas/{id}  textos para responder chamados
//   nps/{uid}               nota de 0 a 10 que o cliente deu ao app (o cliente grava a dele)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'plataforma.dart';
import 'planos.dart';

class PainelCriador {
  PainelCriador._();

  static FirebaseFirestore get _db => Db.banco;
  static CollectionReference<Map<String, dynamic>> get pagamentos => _db.collection('pagamentos');
  static CollectionReference<Map<String, dynamic>> get historico => _db.collection('contas_historico');
  static CollectionReference<Map<String, dynamic>> get respostas => _db.collection('respostas_prontas');
  static CollectionReference<Map<String, dynamic>> get nps => _db.collection('nps');

  /// Anota no histórico da conta o que o criador mudou.
  static Future<void> anotar(String uid, String acao, {String detalhe = '', String? motivo}) => historico.add({
        'uid': uid,
        'acao': acao,
        'detalhe': detalhe,
        'motivo': ?motivo,
        'por': FirebaseAuth.instance.currentUser?.email ?? '',
        'em': FieldValue.serverTimestamp(),
      });

  /// Conta uma ida a uma tela do menu (uma vez por tela em cada sessão).
  static final _telasDaSessao = <String>{};
  static Future<void> contarTela(String tela) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !_telasDaSessao.add(tela)) return;
    try {
      await Plataforma.contas.doc(uid).update({FieldPath(['uso', tela]): FieldValue.increment(1)});
    } catch (_) {
      // Sem conta ainda ou sem rede: não conta.
    }
  }

  /// Identificador deste aparelho (fica guardado no navegador/celular).
  static Future<String> idDoAparelho() async {
    try {
      final p = await SharedPreferences.getInstance();
      var id = p.getString('eito_aparelho');
      if (id == null) {
        id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
        await p.setString('eito_aparelho', id);
      }
      return id;
    } catch (_) {
      return 'desconhecido';
    }
  }
}

/// Aparelhos diferentes no mesmo login a partir dos quais o painel avisa.
const limiteAparelhos = 5;

/// Nota de 0 a 100: quanto a conta usa o app (acesso recente, rebanho, fazenda, telas).
int saudeConta(Map<String, dynamic> c, [DateTime? agora]) {
  final hoje = agora ?? DateTime.now();
  final acesso = dataDe(c['ultimo_acesso']);
  final dias = acesso == null ? 999 : hoje.difference(acesso).inDays;
  final animais = (c['animais'] as num?)?.toInt() ?? 0;
  final telas = (c['uso'] as Map?)?.length ?? 0;
  return (dias <= 2 ? 50 : dias <= 7 ? 40 : dias <= 15 ? 25 : dias <= 30 ? 10 : 0) +
      (animais >= 50 ? 30 : animais >= 10 ? 20 : animais > 0 ? 10 : 0) +
      (((c['propriedades'] as num?) ?? 0) > 0 ? 10 : 0) +
      (telas >= 5 ? 10 : telas >= 2 ? 5 : 0);
}

/// Conta em risco de desistir (nota abaixo de 40).
bool emRisco(Map<String, dynamic> c) => saudeConta(c) < 40;

const _ddds = {
  'SP': [11, 12, 13, 14, 15, 16, 17, 18, 19],
  'RJ': [21, 22, 24],
  'ES': [27, 28],
  'MG': [31, 32, 33, 34, 35, 37, 38],
  'PR': [41, 42, 43, 44, 45, 46],
  'SC': [47, 48, 49],
  'RS': [51, 53, 54, 55],
  'DF': [61],
  'GO': [62, 64],
  'TO': [63],
  'MT': [65, 66],
  'MS': [67],
  'AC': [68],
  'RO': [69],
  'BA': [71, 73, 74, 75, 77],
  'SE': [79],
  'PE': [81, 87],
  'AL': [82],
  'PB': [83],
  'RN': [84],
  'CE': [85, 88],
  'PI': [86, 89],
  'MA': [98, 99],
  'PA': [91, 93, 94],
  'AM': [92, 97],
  'AP': [96],
  'RR': [95],
};

/// Estado pelo DDD do telefone ("(62) 9...." vira GO); null se não der para saber.
String? ufPorTelefone(String? fone) {
  var d = (fone ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('55') && d.length >= 12) d = d.substring(2);
  if (d.startsWith('0')) d = d.substring(1);
  if (d.length < 10) return null;
  final ddd = int.parse(d.substring(0, 2));
  for (final e in _ddds.entries) {
    if (e.value.contains(ddd)) return e.key;
  }
  return null;
}

/// Estado da conta: o da fazenda cadastrada ou, sem ele, o do DDD.
String? ufDaConta(Map<String, dynamic> c) {
  final uf = '${c['uf'] ?? ''}';
  return uf.isNotEmpty ? uf : ufPorTelefone('${c['telefone'] ?? ''}');
}

/// Novo vencimento depois de um pagamento: conta a partir do vencimento atual
/// (se ainda não passou) ou de hoje.
DateTime vencimentoAposPagamento(DateTime? atual, DateTime hoje, String periodo) {
  final base = atual != null && atual.isAfter(hoje) ? atual : hoje;
  return _somaMeses(base, periodo == 'anual' ? 12 : 1);
}

/// Soma meses sem pular para o mês seguinte: 31/01 + 1 mês = 28/02.
DateTime _somaMeses(DateTime d, int n) {
  final m = d.month - 1 + n;
  final ano = d.year + m ~/ 12, mes = m % 12 + 1;
  final ultimo = DateTime(ano, mes + 1, 0).day;
  return DateTime(ano, mes, d.day > ultimo ? ultimo : d.day);
}

/// Valor de tabela do plano no período, com o desconto da indicação quando houver.
double valorSugerido(String plano, String periodo, {int desconto = 0}) {
  final p = PlanoEito.de(plano);
  final tabela = double.tryParse((periodo == 'anual' ? p.ano : p.mes).replaceAll(',', '.')) ?? 0;
  return ((tabela * (100 - desconto)).round()) / 100;
}

/// Tempo médio entre a primeira mensagem do cliente e a primeira resposta do suporte.
Duration? tempoMedioResposta(Iterable<Map<String, dynamic>> chamados) {
  final tempos = <Duration>[];
  for (final c in chamados) {
    final msgs = [for (final m in (c['mensagens'] as List?) ?? const []) if (m is Map) m];
    final cliente = msgs.where((m) => m['de'] == 'cliente').map((m) => DateTime.tryParse('${m['em']}')).firstOrNull;
    if (cliente == null) continue;
    final resposta = msgs
        .where((m) => m['de'] == 'equipe')
        .map((m) => DateTime.tryParse('${m['em']}'))
        .where((d) => d != null && !d.isBefore(cliente))
        .firstOrNull;
    if (resposta != null) tempos.add(resposta.difference(cliente));
  }
  if (tempos.isEmpty) return null;
  return Duration(minutes: tempos.fold<int>(0, (s, t) => s + t.inMinutes) ~/ tempos.length);
}

/// "2 h 15 min", "3 dias".
String textoDuracao(Duration d) {
  if (d.inDays >= 2) return '${d.inDays} dias';
  if (d.inHours >= 1) return '${d.inHours} h${d.inMinutes % 60 == 0 ? '' : ' ${d.inMinutes % 60} min'}';
  return '${d.inMinutes} min';
}

/// NPS: % de notas 9 e 10 menos % de notas de 0 a 6.
int? calcularNps(Iterable<int> notas) {
  final l = notas.toList();
  if (l.isEmpty) return null;
  final promotores = l.where((n) => n >= 9).length, detratores = l.where((n) => n <= 6).length;
  return ((promotores - detratores) * 100 / l.length).round();
}

/// Respostas prontas que já vêm no painel (o criador pode criar outras).
const respostasPadrao = [
  'Olá! Recebemos seu chamado e já estamos olhando. Retornamos em breve.',
  'Pronto, resolvido! Feche e abra o app de novo para atualizar. Se continuar, é só responder aqui.',
  'Para isso, abra o menu (☰), toque no grupo certo e escolha a tela. No Guia do Usuário tem o passo a passo.',
  'Seu plano foi atualizado. Obrigado por usar o Eito Gestão!',
  'Pode mandar um print da tela? Assim conseguimos ver exatamente o que aparece para você.',
];
