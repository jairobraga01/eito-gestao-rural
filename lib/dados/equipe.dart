// Equipe: várias pessoas trabalhando na mesma fazenda, cada uma com a sua conta.
//
// Os dados ficam sempre em usuarios/{dono}. O dono convida pelo e-mail ou cria
// um login de peão (usuário e senha, sem e-mail de verdade):
// - convites/{email}: quem convidou, nome e papel. O convidado lê o seu ao entrar.
// - usuarios/{dono}/equipe/{uid}: quem faz parte e o papel. É isso que as regras
//   do Firestore conferem para liberar a leitura e a gravação dos dados do dono.
// Papéis: gerente (tudo, menos a equipe) e peão (serviço de campo, sem financeiro).
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'db.dart';

const papeis = {'gerente': 'Gerente', 'peao': 'Peão'};

/// O que cada papel pode fazer (mostrado na tela da equipe).
const descricaoPapel = {
  'gerente': 'Vê e lança tudo, menos a equipe.',
  'peao': 'Lança o serviço de campo (curral, pesagem, sanidade, reprodução, pasto, chuva e tarefas). '
      'Não vê o financeiro e só apaga o que ele mesmo lançou.',
};

/// Domínio dos logins de peão (não recebe e-mail; serve só para entrar).
const dominioPeao = 'peao.eitogestao.com.br';

/// No login, quem digita só o usuário (sem @) é peão.
String emailDoLogin(String digitado) {
  final t = digitado.trim();
  return t.contains('@') ? t : '${t.toLowerCase()}@$dominioPeao';
}

bool ehLoginDePeao(String? email) => (email ?? '').toLowerCase().endsWith('@$dominioPeao');

/// Usuário do peão a partir do nome: primeiro nome sem acento + 4 números.
String usuarioPeao(String nome, [Random? rnd]) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ', para = 'aaaaaeeeeiiiiooooouuuucn';
  var base = '';
  for (final c in (nome.trim().split(RegExp(r'\s+')).first).toLowerCase().split('')) {
    final i = de.indexOf(c);
    final x = i >= 0 ? para[i] : c;
    if (RegExp('[a-z0-9]').hasMatch(x)) base += x;
  }
  if (base.isEmpty) base = 'peao';
  return '$base${1000 + (rnd ?? Random()).nextInt(9000)}';
}

/// Onde a pessoa trabalha, quando entrou por convite.
class Acesso {
  const Acesso({required this.dono, required this.papel, required this.nome, this.donoNome = ''});
  final String dono;
  final String papel;
  final String nome;
  final String donoNome;
}

/// Pessoa da equipe (já entrou) ou convite ainda não usado.
class Membro {
  const Membro({required this.email, required this.nome, required this.papel, this.uid, this.usuario});
  final String email;
  final String nome;
  final String papel;
  final String? uid; // null: ainda não entrou
  final String? usuario; // login de peão
  bool get pendente => uid == null;
}

class Equipe {
  Equipe._();

  static FirebaseFirestore get _banco => Db.banco;
  static DocumentReference<Map<String, dynamic>> _convite(String email) =>
      _banco.collection('convites').doc(email.trim().toLowerCase());
  static CollectionReference<Map<String, dynamic>> _equipe(String dono) =>
      _banco.collection('usuarios').doc(dono).collection('equipe');

  /// Acesso atual (null quando a pessoa usa os próprios dados).
  static Acesso? atual;

  /// Procura um convite para quem entrou. Na primeira vez, entra na equipe.
  static Future<Acesso?> procurarAcesso(String uid, String? email) async {
    atual = null;
    if (email == null || email.isEmpty) return null;
    final Map<String, dynamic>? c;
    try {
      c = (await _convite(email).get()).data();
    } on FirebaseException catch (e) {
      // Sem convite (ou e-mail ainda não confirmado) as regras negam a leitura.
      if (e.code == 'permission-denied') return null;
      if (ehLoginDePeao(email)) rethrow;
      debugPrint('Eito: não deu para ver o convite: $e');
      return null;
    }
    final dono = c?['dono'] as String?;
    if (c == null || dono == null || dono == uid) return null;
    final ref = _equipe(dono).doc(uid);
    var m = (await ref.get()).data();
    if (m == null) {
      m = {
        'uid': uid,
        'email': email.toLowerCase(),
        'nome': c['nome'] ?? email,
        'papel': c['papel'],
        if (c['usuario'] != null) 'usuario': c['usuario'],
        'desde': DateTime.now().toIso8601String(),
      };
      await ref.set(m);
    }
    return atual = Acesso(
      dono: dono,
      papel: '${m['papel']}',
      nome: '${m['nome'] ?? email}',
      donoNome: '${c['dono_nome'] ?? ''}',
    );
  }

  /// Convida pelo e-mail. A pessoa cria a conta com esse e-mail, confirma e entra.
  static Future<void> convidar({
    required String dono,
    required String donoNome,
    required String email,
    required String nome,
    required String papel,
    String? uid,
    String? usuario,
  }) async {
    final e = email.trim().toLowerCase();
    await _convite(e).set({
      'dono': dono,
      'dono_nome': donoNome,
      'email': e,
      'nome': nome.trim(),
      'papel': papel,
      if (uid != null) 'uid': uid,
      if (usuario != null) 'usuario': usuario,
      'criado_em': DateTime.now().toIso8601String(),
    });
    // Login de peão: o dono já sabe o uid e põe a pessoa na equipe direto.
    if (uid != null) {
      await _equipe(dono).doc(uid).set({
        'uid': uid,
        'email': e,
        'nome': nome.trim(),
        'papel': papel,
        if (usuario != null) 'usuario': usuario,
        'desde': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Equipe do dono: quem já entrou e os convites pendentes.
  static Future<List<Membro>> membros(String dono) async {
    final equipe = await _equipe(dono).get();
    final convites = await _banco.collection('convites').where('dono', isEqualTo: dono).get();
    final lista = <Membro>[
      for (final d in equipe.docs)
        Membro(
          email: '${d.data()['email'] ?? ''}',
          nome: '${d.data()['nome'] ?? ''}',
          papel: '${d.data()['papel'] ?? 'peao'}',
          uid: d.id,
          usuario: d.data()['usuario'] as String?,
        ),
    ];
    final emails = {for (final m in lista) m.email};
    for (final c in convites.docs) {
      if (emails.contains(c.id)) continue;
      lista.add(Membro(
        email: c.id,
        nome: '${c.data()['nome'] ?? ''}',
        papel: '${c.data()['papel'] ?? 'peao'}',
        usuario: c.data()['usuario'] as String?,
      ));
    }
    lista.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return lista;
  }

  static Future<void> mudarPapel(String dono, Membro m, String papel) async {
    await _convite(m.email).set({'papel': papel}, SetOptions(merge: true));
    if (m.uid != null) await _equipe(dono).doc(m.uid).update({'papel': papel});
  }

  /// Tira da equipe: some o convite e a ligação. A pessoa perde o acesso na hora.
  static Future<void> remover(String dono, Membro m) async {
    await _convite(m.email).delete();
    if (m.uid != null) await _equipe(dono).doc(m.uid).delete();
  }

  /// Quem está na equipe sai por conta própria.
  static Future<void> sair(String uid, String email) async {
    final a = atual;
    if (a == null) return;
    await _equipe(a.dono).doc(uid).delete();
    await _convite(email).delete();
    atual = null;
  }

  /// Nome de cada pessoa da equipe pelo uid (para filtros e tarefas).
  static Future<Map<String, String>> nomes(String dono) async {
    final r = <String, String>{};
    try {
      for (final d in (await _equipe(dono).get()).docs) {
        r[d.id] = '${d.data()['nome'] ?? ''}';
      }
    } catch (e) {
      debugPrint('Eito: não deu para ler a equipe: $e');
    }
    return r;
  }

  /// Apaga a equipe e os convites do dono (ao excluir a conta).
  static Future<void> apagarTudo(String dono) async {
    for (final d in (await _equipe(dono).get()).docs) {
      await d.reference.delete();
    }
    for (final c in (await _banco.collection('convites').where('dono', isEqualTo: dono).get()).docs) {
      await c.reference.delete();
    }
  }
}
