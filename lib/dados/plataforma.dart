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

import '../marca.dart';
import 'db.dart';
import 'equipe.dart';
import 'painel_criador.dart';
import 'planos.dart';

// O painel do criador abre para quem está em admins/{uid} (o mesmo
// administrador dos códigos de indicação, ver Indicacoes.souAdmin).

/// Planos que o criador pode dar a uma conta. Essencial, Profissional e Completa são os nomes antigos de Simples, Média e Plus.
const planos = ['Teste', 'Simples', 'Média', 'Plus', 'Cortesia'];
const planosPagos = ['Simples', 'Média', 'Plus', 'Essencial', 'Profissional', 'Completa'];
const categoriasChamado = ['Dúvida', 'Problema no app', 'Sugestão', 'Financeiro / plano', 'Outro'];

/// Preço mensal de tabela do plano (0 para Teste e Cortesia).
double precoMensal(Object? plano) =>
    planosPagos.contains(plano) ? double.parse(PlanoEito.de(plano).mes.replaceAll(',', '.')) : 0;

/// Nome atual do plano (os antigos viram Simples, Média e Plus).
String nomePlano(Object? plano) => planosPagos.contains(plano) ? PlanoEito.de(plano).nome : '${plano ?? 'Teste'}';

/// Link do cadastro da conta no console do Firebase (Firestore).
String linkFirebaseConta(String uid) =>
    'https://console.firebase.google.com/project/caderneta-rebanho/firestore/databases/-default-/data/~2Fcontas~2F$uid';

/// Dados da fazenda da conta no console do Firebase (usuarios/{uid}).
String linkFirebaseDados(String uid) =>
    'https://console.firebase.google.com/project/caderneta-rebanho/firestore/databases/-default-/data/~2Fusuarios~2F$uid';

/// Lista de logins no console do Firebase (Authentication).
const linkFirebaseLogins = 'https://console.firebase.google.com/project/caderneta-rebanho/authentication/users';

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
    final criado = dataDe(c['criado_em']);
    // Vence 30 dias depois do cadastro ou na data do painel, a mais tarde.
    final fim = [?ate, if (criado != null) criado.add(const Duration(days: diasDeTeste))]
        .fold<DateTime?>(null, (m, d) => m == null || d.isAfter(m) ? d : m);
    if (fim == null) return 'Teste';
    final d = '${fim.day.toString().padLeft(2, '0')}/${fim.month.toString().padLeft(2, '0')}';
    return fim.isBefore(DateTime.now()) ? 'Teste vencido em $d (vale como Simples)' : 'Teste até $d';
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

  /// Telefone digitado no cadastro; vai para a conta no primeiro acesso.
  static String? telefoneNovo;

  /// A conta foi criada agora (mostra as boas-vindas no app).
  static final contaNova = ValueNotifier<bool>(false);

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
      'aparelhos': FieldValue.arrayUnion([await PainelCriador.idDoAparelho()]),
    };
    final uf = Db.registros('propriedades').map((p) => '${p['uf'] ?? ''}').where((u) => u.isNotEmpty).firstOrNull;
    if (uf != null) resumo['uf'] = uf;
    Map<String, dynamic>? c;
    final fone = telefoneNovo;
    if (fone != null) resumo['telefone'] = fone;
    try {
      final s = await ref.get();
      if (!s.exists) {
        await ref.set({
          ...resumo,
          'uid': u.uid,
          'criado_em': FieldValue.serverTimestamp(),
          'plano': 'Teste',
          'teste_ate': Timestamp.fromDate(DateTime.now().add(const Duration(days: diasDeTeste))),
          'status': 'ativa',
          'boas_vindas_whats': 'pendente',
        });
        contaNova.value = papel == 'dono';
        if (papel == 'dono') await _emailBoasVindas(u);
      } else {
        await ref.update(resumo);
      }
      telefoneNovo = null;
      c = (await ref.get()).data();
    } catch (e) {
      debugPrint('Eito: não deu para registrar a conta: $e');
      return null;
    }
    if (c?['status'] == 'suspensa') {
      throw 'Esta conta está suspensa. Fale com o suporte do Eito.';
    }
    Db.planoDaFazenda.value = planoEfetivo(c, DateTime.now());
    if (dono != null && dono != u.uid) {
      try {
        final d = (await contas.doc(dono).get()).data();
        if (d?['status'] == 'suspensa') throw 'A conta da fazenda está suspensa. Fale com o dono.';
        Db.planoDaFazenda.value = planoEfetivo(d, DateTime.now()); // a equipe segue o plano do dono
      } on FirebaseException catch (_) {
        // Sem permissão para ler a conta do dono: segue.
      }
    }
    conta.value = c;
    return c;
  }

  /// Põe o e-mail de boas-vindas na fila mail/{uid}: a extensão "Trigger Email"
  /// do Firebase envia (sem ela instalada, fica só guardado).
  static Future<void> _emailBoasVindas(User u) async {
    final email = u.email;
    if (email == null || email.isEmpty) return;
    try {
      await _db.collection('mail').doc(u.uid).set({
        'to': email,
        'message': {
          'subject': 'Bem-vindo ao Eito Gestão',
          'text': textoBoasVindas(u.displayName ?? ''),
          'html': htmlBoasVindas(u.displayName ?? ''),
        },
      });
    } catch (e) {
      debugPrint('Eito: e-mail de boas-vindas: $e');
    }
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
      'Simples' || 'Média' || 'Plus' => nomePlano(plano) == a['publico'],
      'uf' => '${a['uf'] ?? ''}'.toUpperCase() == (ufDaConta(conta.value ?? const {}) ?? ''),
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

// ---------- Boas-vindas ----------

const _site = 'https://eitogestao.com.br';

String _primeiroNome(String nome) => nome.trim().isEmpty ? '' : ', ${nome.trim()}';

/// Mensagem de boas-vindas (WhatsApp e texto do e-mail).
String textoBoasVindas(String nome) => 'Olá${_primeiroNome(nome)}! Sua conta no Eito Gestão está pronta. 🐂\n\n'
    'Você tem 30 dias com tudo liberado para testar.\n\n'
    'Comece cadastrando a fazenda e os pastos; depois monte os lotes e lance o rebanho. '
    'Funciona no curral mesmo sem sinal.\n\n'
    'Se precisar, fale com a gente pela Ajuda dentro do app ou pelo e-mail ${Marca.email}.\n\n'
    'Abrir o Eito: $_site';

String _ddmm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Mensagem pronta para quem está com o teste terminando ou vencido.
String textoCobrancaTeste(String nome, DateTime? ate) {
  final quando = ate == null
      ? 'Seu teste do Eito Gestão está no fim'
      : ate.isBefore(DateTime.now())
          ? 'Seu teste do Eito Gestão terminou em ${_ddmm(ate)}'
          : 'Seu teste do Eito Gestão termina em ${_ddmm(ate)}';
  final tabela = PlanoEito.todos.map((p) => '• ${p.nome}: R\$ ${p.mes}/mês ou R\$ ${p.ano}/ano (${p.resumoLimite})').join('\n');
  return 'Olá${_primeiroNome(nome)}! $quando. 🐂\n\n'
      'Para continuar com o rebanho no app, é só escolher um plano:\n$tabela\n\n'
      'Qualquer dúvida, responda aqui que a gente ajuda.';
}

/// Mensagem pronta para quem não abre o app há um tempo.
String textoSumido(String nome) => 'Olá${_primeiroNome(nome)}! Faz uns dias que você não aparece no Eito Gestão. 🐂\n\n'
    'Ficou alguma dúvida para lançar o rebanho? Se quiser, a gente te ajuda a deixar tudo pronto.\n\n'
    'Abrir o Eito: $_site';

String _esc(String t) => t.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// E-mail de boas-vindas em HTML.
String htmlBoasVindas(String nome) {
  final n = nome.trim().isEmpty ? '' : ', ${_esc(nome.trim())}';
  return '''<div style="background:#f3f5f0;padding:32px 16px;font-family:Arial,Helvetica,sans-serif;color:#0B1F14">
<div style="max-width:560px;margin:0 auto">
<div style="font-family:Georgia,serif;font-size:28px;font-weight:bold;color:#00602A;margin:0 0 20px">Eito Gestão</div>
<div style="background:#fff;border:1px solid #dfe5da;border-radius:14px;padding:28px">
<h1 style="font-size:24px;margin:0 0 16px">Sua conta está pronta</h1>
<p style="font-size:16px;line-height:1.6">Olá$n. Você tem 30 dias com tudo liberado para testar.</p>
<p style="font-size:16px;line-height:1.6">Comece cadastrando a fazenda e os pastos no mapa; depois monte os lotes do rebanho.
Se precisar, fale com a gente pela Ajuda dentro do app.</p>
<p style="margin:28px 0 8px"><a href="$_site" style="background:#00602A;color:#fff;text-decoration:none;font-weight:bold;font-size:17px;padding:14px 26px;border-radius:10px;display:inline-block">Abrir o Eito Gestão</a></p>
</div>
<p style="font-size:13px;color:#6b7468;margin:16px 4px">Você recebeu este e-mail porque tem uma conta no Eito Gestão. Dúvidas: <a href="mailto:${Marca.email}" style="color:#00602A">${Marca.email}</a></p>
</div></div>''';
}
