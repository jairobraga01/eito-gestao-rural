// Parte "empresa" do Eito (vinda do BovinoTech): cadastro das contas,
// chamados de suporte, comunicados no topo do app e o painel do criador.
//
// Coleções no Firestore (fora de usuarios/, ver firestore.rules):
//   contas/{uid}         quem usa o app, plano, teste e situação
//   contas_notas/{uid}   anotações internas do criador (o cliente não vê)
//   chamados/{id}        pedidos de ajuda com a conversa
//   comunicados/{id}     faixa no topo do app
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'db.dart';
import 'equipe.dart';

// O painel do criador abre para quem está em admins/{uid} (o mesmo
// administrador dos códigos de indicação, ver Indicacoes.souAdmin).

/// Planos que o criador pode dar a uma conta. Essencial, Profissional e Completa são os nomes antigos de Simples, Média e Plus.
const planos = ['Teste', 'Simples', 'Média', 'Plus', 'Cortesia'];
const planosPagos = ['Simples', 'Média', 'Plus', 'Essencial', 'Profissional', 'Completa'];
const categoriasChamado = ['Dúvida', 'Problema no app', 'Sugestão', 'Financeiro / plano', 'Outro'];

DateTime? dataDe(Object? v) => switch (v) {
      Timestamp t => t.toDate(),
      DateTime d => d,
      String s => DateTime.tryParse(s),
      _ => null,
    };

/// Situação da conta para mostrar: "Teste até 01/11", "Essencial", "Suspensa".
String situacaoConta(Map<String, dynamic> c) {
  if (c['status'] == 'suspensa') return 'Suspensa';
  final plano = '${c['plano'] ?? 'Teste'}';
  if (plano == 'Teste') {
    final ate = dataDe(c['teste_ate']);
    if (ate == null) return 'Teste';
    final d = '${ate.day.toString().padLeft(2, '0')}/${ate.month.toString().padLeft(2, '0')}';
    return ate.isBefore(DateTime.now()) ? 'Teste vencido em $d' : 'Teste até $d';
  }
  final fim = dataDe(c['plano_ate']);
  if (fim == null) return plano;
  return '$plano até ${fim.day.toString().padLeft(2, '0')}/${fim.month.toString().padLeft(2, '0')}/${fim.year}';
}

class Plataforma {
  Plataforma._();

  static FirebaseFirestore get _db => Db.banco;
  static CollectionReference<Map<String, dynamic>> get contas => _db.collection('contas');
  static CollectionReference<Map<String, dynamic>> get notas => _db.collection('contas_notas');
  static CollectionReference<Map<String, dynamic>> get chamados => _db.collection('chamados');
  static CollectionReference<Map<String, dynamic>> get comunicados => _db.collection('comunicados');

  /// Conta de quem entrou (atualizada a cada acesso).
  static final conta = ValueNotifier<Map<String, dynamic>?>(null);

  /// Chamados do usuário com resposta ainda não lida.
  static final naoLidos = ValueNotifier<int>(0);

  /// Comunicados que valem agora para este usuário.
  static final avisos = ValueNotifier<List<Map<String, dynamic>>>(const []);

  /// Comunicados que a pessoa fechou nesta sessão.
  static final fechados = <String>{};

  static final List<StreamSubscription<Object?>> _subs = [];
  static List<Map<String, dynamic>> _todosAvisos = const [];

  /// Registra o acesso e devolve a conta. Lança erro se a conta (ou a do
  /// dono, para quem é da equipe) estiver suspensa.
  static Future<Map<String, dynamic>?> registrarAcesso(User u, {String? dono, required String papel}) async {
    final ref = contas.doc(u.uid);
    final resumo = <String, dynamic>{
      'email': (u.email ?? '').toLowerCase(),
      'nome': u.displayName ?? '',
      'papel': papel,
      'dono': dono,
      'ultimo_acesso': FieldValue.serverTimestamp(),
      'animais': Db.registros('animais').where((a) => (a['status'] ?? 'Ativo') == 'Ativo').length,
      'propriedades': Db.registros('propriedades').length,
    };
    Map<String, dynamic>? c;
    try {
      final s = await ref.get();
      if (!s.exists) {
        await ref.set({
          ...resumo,
          'uid': u.uid,
          'criado_em': FieldValue.serverTimestamp(),
          'plano': 'Teste',
          'teste_ate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 14))),
          'status': 'ativa',
        });
      } else {
        await ref.update(resumo);
      }
      c = (await ref.get()).data();
    } catch (e) {
      debugPrint('Eito: não deu para registrar a conta: $e');
      return null;
    }
    if (c?['status'] == 'suspensa') {
      throw 'Esta conta está suspensa. Fale com o suporte do Eito.';
    }
    Db.planoDaFazenda.value = c?['plano'] as String?;
    if (dono != null && dono != u.uid) {
      try {
        final d = (await contas.doc(dono).get()).data();
        if (d?['status'] == 'suspensa') throw 'A conta da fazenda está suspensa. Fale com o dono.';
        Db.planoDaFazenda.value = d?['plano'] as String?; // a equipe segue o plano do dono
      } on FirebaseException catch (_) {
        // Sem permissão para ler a conta do dono: segue.
      }
    }
    conta.value = c;
    return c;
  }

  /// Liga o sininho (respostas dos chamados) e os comunicados.
  static void iniciarAvisos(String uid) {
    pararAvisos();
    _subs.add(chamados.where('uid', isEqualTo: uid).snapshots().listen((s) {
      naoLidos.value = s.docs.where((d) => d.data()['lido_cliente'] == false).length;
    }, onError: (Object e) => debugPrint('Eito: chamados: $e')));
    _subs.add(comunicados.where('ativo', isEqualTo: true).snapshots().listen((s) {
      _todosAvisos = [for (final d in s.docs) {...d.data(), 'id': d.id}];
      _filtrarAvisos();
    }, onError: (Object e) => debugPrint('Eito: comunicados: $e')));
    _subs.add(contas.doc(uid).snapshots().listen((s) {
      if (s.exists) {
        conta.value = s.data();
        if (Equipe.atual == null) Db.planoDaFazenda.value = s.data()?['plano'] as String?;
        _filtrarAvisos();
      }
    }, onError: (Object e) => debugPrint('Eito: conta: $e')));
  }

  static void _filtrarAvisos() {
    final agora = DateTime.now();
    final c = conta.value ?? const {};
    final plano = '${c['plano'] ?? 'Teste'}';
    avisos.value = [
      for (final a in _todosAvisos)
        if (!fechados.contains(a['id']) && _vale(a, agora, plano)) a,
    ];
  }

  static bool _vale(Map<String, dynamic> a, DateTime agora, String plano) {
    final ini = dataDe(a['inicio']), fim = dataDe(a['fim']);
    if (ini != null && agora.isBefore(ini)) return false;
    if (fim != null && agora.isAfter(fim.add(const Duration(days: 1)))) return false;
    return switch ('${a['publico'] ?? 'todos'}') {
      'teste' => plano == 'Teste',
      'pagantes' => plano != 'Teste' && plano != 'Cortesia',
      _ => true,
    };
  }

  static void fecharAviso(String id) {
    fechados.add(id);
    _filtrarAvisos();
  }

  static void pararAvisos() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    naoLidos.value = 0;
    avisos.value = const [];
  }

  // ---------- Chamados ----------

  static Map<String, dynamic> mensagem(String de, String nome, String texto) => {
        'de': de,
        'nome': nome,
        'texto': texto,
        'em': DateTime.now().toIso8601String(),
      };

  static Future<String> abrirChamado(User u, {required String assunto, required String categoria, required String texto}) async {
    final plano = '${conta.value?['plano'] ?? 'Teste'}';
    final ref = await chamados.add({
      'uid': u.uid,
      'email': (u.email ?? '').toLowerCase(),
      'nome': u.displayName ?? u.email ?? '',
      'assunto': assunto,
      'categoria': categoria,
      'prioridade': plano == 'Completa' || plano == 'Plus' ? 'alta' : 'normal',
      'status': 'aberto',
      'criado_em': FieldValue.serverTimestamp(),
      'atualizado_em': FieldValue.serverTimestamp(),
      'mensagens': [mensagem('cliente', u.displayName ?? u.email ?? 'Cliente', texto)],
      'lido_cliente': true,
      'lido_equipe': false,
    });
    return ref.id;
  }

  /// Resposta na conversa. [equipe] = resposta do criador.
  static Future<void> responder(String id, String texto, {required bool equipe, required String nome}) =>
      chamados.doc(id).update({
        'mensagens': FieldValue.arrayUnion([mensagem(equipe ? 'equipe' : 'cliente', nome, texto)]),
        'atualizado_em': FieldValue.serverTimestamp(),
        'status': equipe ? 'respondido' : 'aberto',
        'lido_cliente': !equipe,
        'lido_equipe': equipe,
      });

  static Future<void> marcarLido(String id, {required bool equipe}) =>
      chamados.doc(id).update({equipe ? 'lido_equipe' : 'lido_cliente': true});

  static Future<void> mudarStatus(String id, String status) =>
      chamados.doc(id).update({'status': status, 'atualizado_em': FieldValue.serverTimestamp()});
}
