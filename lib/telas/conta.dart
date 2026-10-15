// Minha conta: trocar senha, trocar e-mail e excluir a conta com todos os dados.
//
// O Firebase só deixa mudar senha, e-mail ou excluir a conta logo depois de
// um login recente; por isso cada ação pede a senha atual antes (reautenticação).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../tema.dart';
import '../util/util.dart';

class TelaConta extends StatefulWidget {
  const TelaConta({super.key});

  @override
  State<TelaConta> createState() => _TelaContaState();
}

class _TelaContaState extends State<TelaConta> {
  bool _ocupado = false;

  User? get _usuario => FirebaseAuth.instance.currentUser;

  /// Pede a senha atual e reautentica. Devolve false se cancelou ou errou.
  Future<bool> _reautenticar() async {
    final u = _usuario;
    if (u?.email == null) return false;
    final senha = await _pedirTexto('Confirme sua senha atual', 'Senha atual', senha: true);
    if (senha == null || senha.isEmpty) return false;
    try {
      await u!.reauthenticateWithCredential(EmailAuthProvider.credential(email: u.email!, password: senha));
      return true;
    } on FirebaseAuthException catch (e) {
      if (mounted) avisar(context, mensagemConta(e));
      return false;
    }
  }

  Future<void> _executar(Future<void> Function() acao) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await acao();
    } on FirebaseAuthException catch (e) {
      if (mounted) avisar(context, mensagemConta(e));
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível concluir: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _trocarSenha() => _executar(() async {
        final nova = await _pedirTexto('Nova senha', 'Nova senha (mínimo 6 caracteres)', senha: true);
        if (nova == null || nova.isEmpty) return;
        if (nova.length < 6) {
          if (mounted) avisar(context, 'A senha precisa ter pelo menos 6 caracteres.');
          return;
        }
        if (!await _reautenticar()) return;
        await _usuario!.updatePassword(nova);
        if (mounted) avisar(context, 'Senha alterada.');
      });

  Future<void> _trocarEmail() => _executar(() async {
        final novo = (await _pedirTexto('Novo e-mail', 'Novo e-mail', email: true))?.trim();
        if (novo == null || novo.isEmpty) return;
        if (!await _reautenticar()) return;
        await _usuario!.verifyBeforeUpdateEmail(novo);
        if (mounted) {
          avisar(context, 'Enviamos um link para $novo. O e-mail muda quando você abrir o link.');
        }
      });

  Future<void> _excluirConta() => _executar(() async {
        final ok = await confirmar(
          context,
          'Excluir a conta?',
          'Todos os dados (propriedades, animais, lotes, pesagens, sanidade, reprodução, vendas) '
              'serão apagados para sempre, em todos os aparelhos. Faça um Backup antes, se quiser guardar.',
          ok: 'Continuar',
        );
        if (!ok || !mounted) return;
        final digitado = await _pedirTexto('Para confirmar, digite EXCLUIR', 'EXCLUIR');
        if (digitado?.trim().toUpperCase() != 'EXCLUIR') return;
        if (!await _reautenticar()) return;
        final u = _usuario!;
        await apagarDadosDoUsuario(u.uid);
        await Db.encerrar();
        await u.delete();
        // O login volta sozinho: main.dart escuta authStateChanges().
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });

  Future<String?> _pedirTexto(String titulo, String rotulo, {bool senha = false, bool email = false}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: senha,
          keyboardType: email ? TextInputType.emailAddress : TextInputType.text,
          decoration: InputDecoration(labelText: rotulo),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _usuario?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Minha conta')),
      body: AbsorbPointer(
        absorbing: _ocupado,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_ocupado) const LinearProgressIndicator(),
          ListTile(
            leading: const Icon(Icons.email_outlined, color: Cores.oliva),
            title: const Text('E-mail'),
            subtitle: Text(email, style: const TextStyle(fontSize: 16)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_reset, color: Cores.oliva),
            title: const Text('Trocar a senha'),
            onTap: _trocarSenha,
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email, color: Cores.oliva),
            title: const Text('Trocar o e-mail'),
            subtitle: const Text('Você confirma pelo link enviado ao novo e-mail.'),
            onTap: _trocarEmail,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Cores.alerta),
            title: const Text('Excluir a conta e todos os dados',
                style: TextStyle(color: Cores.alerta, fontWeight: FontWeight.w700)),
            subtitle: const Text('Não dá para desfazer. Precisa de internet.'),
            onTap: _excluirConta,
          ),
        ]),
      ),
    );
  }
}

/// Apaga todos os documentos de usuarios/{uid}/{tabela} e o próprio usuarios/{uid}.
Future<void> apagarDadosDoUsuario(String uid) async {
  final banco = FirebaseFirestore.instance;
  final raiz = banco.collection('usuarios').doc(uid);
  for (final t in Db.tabelas) {
    final docs = (await raiz.collection(t).get(const GetOptions(source: Source.server))).docs;
    // Um lote do Firestore aceita no máximo 500 operações.
    for (var i = 0; i < docs.length; i += 400) {
      final lote = banco.batch();
      for (final d in docs.skip(i).take(400)) {
        lote.delete(d.reference);
      }
      await lote.commit();
    }
  }
  await raiz.delete();
}

String mensagemConta(FirebaseAuthException e) => switch (e.code) {
      'wrong-password' || 'invalid-credential' => 'Senha atual incorreta.',
      'invalid-email' => 'E-mail inválido.',
      'email-already-in-use' => 'Já existe uma conta com este e-mail.',
      'weak-password' => 'A senha precisa ter pelo menos 6 caracteres.',
      'requires-recent-login' => 'Por segurança, saia e entre de novo antes de fazer isso.',
      'network-request-failed' => 'Sem internet. Esta ação precisa de sinal.',
      'too-many-requests' => 'Muitas tentativas. Aguarde alguns minutos.',
      _ => 'Não foi possível concluir (${e.code}).',
    };
