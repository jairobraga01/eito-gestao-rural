// Minha conta: trocar senha, trocar e-mail e excluir a conta com todos os dados.
//
// O Firebase só deixa mudar senha, e-mail ou excluir a conta logo depois de
// um login recente; por isso cada ação pede a senha atual antes (reautenticação).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/equipe.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart' show encerrarSessao;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
    } on FirebaseAuthMultiFactorException catch (e) {
      // Conta com verificação em duas etapas: pede o código do app autenticador.
      final hint = e.resolver.hints.whereType<TotpMultiFactorInfo>().firstOrNull;
      if (hint == null) {
        if (mounted) avisar(context, 'Esta conta usa um segundo passo que o Eito ainda não aceita.');
        return false;
      }
      final cod = await _pedirTexto('Verificação em duas etapas', 'Código de 6 dígitos do app autenticador',
          numero: true);
      if (cod == null || cod.trim().isEmpty) return false;
      try {
        await e.resolver.resolveSignIn(await TotpMultiFactorGenerator.getAssertionForSignIn(hint.uid, cod.trim()));
        return true;
      } on FirebaseAuthException catch (x) {
        if (mounted) {
          avisar(context, x.code == 'invalid-verification-code' ? 'Código errado ou vencido.' : mensagemConta(x));
        }
        return false;
      }
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

  /// Fatores de segundo passo já ativados nesta conta.
  List<MultiFactorInfo> _fatores = const [];

  @override
  void initState() {
    super.initState();
    _carregarFatores();
  }

  Future<void> _carregarFatores() async {
    try {
      final f = await _usuario?.multiFactor.getEnrolledFactors() ?? const [];
      if (mounted) setState(() => _fatores = f);
    } catch (_) {
      // Sem internet ou recurso desligado: a tela segue sem o estado.
    }
  }

  Future<void> _duasEtapas() => _executar(() async {
        final u = _usuario!;
        if (_fatores.isNotEmpty) {
          if (!await confirmar(context, 'Desligar a verificação em duas etapas?',
              'A conta volta a entrar só com e-mail e senha.',
              ok: 'Desligar')) {
            return;
          }
          if (!await _reautenticar()) return;
          await u.multiFactor.unenroll(factorUid: _fatores.first.uid);
          await _carregarFatores();
          if (mounted) avisar(context, 'Verificação em duas etapas desligada.');
          return;
        }
        if (!u.emailVerified) {
          await u.sendEmailVerification();
          if (mounted) {
            avisar(context, 'Primeiro confirme seu e-mail: enviamos um link para ${u.email}. Depois volte aqui.');
          }
          return;
        }
        if (!await _reautenticar()) return;
        final segredo = await TotpMultiFactorGenerator.generateSecret(await u.multiFactor.getSession());
        final url = await segredo.generateQrCodeUrl(accountName: u.email, issuer: 'Eito');
        if (!mounted) return;
        final codigo = await showDialog<String>(
          context: context,
          builder: (c) {
            final ctrl = TextEditingController();
            return AlertDialog(
              title: const Text('Ligar a verificação em duas etapas'),
              content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('1. Instale um app autenticador (Google Authenticator, Microsoft Authenticator ou Authy).'),
                  gap,
                  const Text('2. Neste celular, toque em "Abrir no autenticador". Em outro aparelho, copie a chave e digite no app.'),
                  gap,
                  FilledButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir no autenticador'),
                    onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar a chave'),
                    onPressed: () => Clipboard.setData(ClipboardData(text: segredo.secretKey)),
                  ),
                  gap,
                  const Text('3. Digite o código de 6 dígitos que o app mostrar:'),
                  TextField(controller: ctrl, keyboardType: TextInputType.number, maxLength: 6),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Ligar')),
              ],
            );
          },
        );
        if (codigo == null || codigo.trim().isEmpty) return;
        final prova = await TotpMultiFactorGenerator.getAssertionForEnrollment(segredo, codigo.trim());
        await u.multiFactor.enroll(prova, displayName: 'App autenticador');
        await _carregarFatores();
        if (mounted) avisar(context, 'Verificação em duas etapas ligada. No próximo login o Eito pede o código.');
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
        if (Equipe.atual != null) await Equipe.sair(u.uid, u.email ?? '');
        await apagarDadosDoUsuario(u.uid);
        await encerrarSessao(sair: false);
        await u.delete();
        // O login volta sozinho: main.dart escuta authStateChanges().
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });

  Future<void> _sairDaEquipe() => _executar(() async {
        final a = Equipe.atual!;
        final ok = await confirmar(
          context,
          'Sair da equipe?',
          'Você deixa de ver os dados da fazenda de ${a.donoNome}. Para voltar, o dono precisa convidar de novo.',
          ok: 'Sair da equipe',
        );
        if (!ok) return;
        final u = _usuario!;
        await Equipe.sair(u.uid, u.email ?? '');
        await encerrarSessao();
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });

  Future<String?> _pedirTexto(String titulo, String rotulo, {bool senha = false, bool email = false, bool numero = false}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: senha,
          keyboardType: email
              ? TextInputType.emailAddress
              : numero
                  ? TextInputType.number
                  : TextInputType.text,
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
    final peao = ehLoginDePeao(email);
    final acesso = Equipe.atual;
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
          if (acesso != null) ...[
            ListTile(
              leading: const Icon(Icons.group_outlined, color: Cores.oliva),
              title: Text('${papeis[acesso.papel] ?? acesso.papel} na fazenda de '
                  '${acesso.donoNome.isEmpty ? 'outra conta' : acesso.donoNome}'),
              subtitle: Text(descricaoPapel[acesso.papel] ?? ''),
            ),
            ListTile(
              leading: const Icon(Icons.group_remove_outlined, color: Cores.alerta),
              title: const Text('Sair da equipe'),
              onTap: _sairDaEquipe,
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_reset, color: Cores.oliva),
            title: const Text('Trocar a senha'),
            onTap: _trocarSenha,
          ),
          // Quem é da equipe entra pelo convite do e-mail: trocar o e-mail tira a pessoa da fazenda.
          if (!peao && Equipe.atual == null)
          ListTile(
            leading: const Icon(Icons.alternate_email, color: Cores.oliva),
            title: const Text('Trocar o e-mail'),
            subtitle: const Text('Você confirma pelo link enviado ao novo e-mail.'),
            onTap: _trocarEmail,
          ),
          if (!peao)
            ListTile(
              leading: const Icon(Icons.verified_user_outlined, color: Cores.oliva),
              title: const Text('Verificação em duas etapas'),
              subtitle: Text(_fatores.isEmpty
                  ? 'Desligada. Ligue para pedir um código do celular a cada login.'
                  : 'Ligada (app autenticador). Toque para desligar.'),
              onTap: _duasEtapas,
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Cores.alerta),
            title: Text(acesso == null ? 'Excluir a conta e todos os dados' : 'Excluir a minha conta',
                style: const TextStyle(color: Cores.alerta, fontWeight: FontWeight.w700)),
            subtitle: const Text('Não dá para desfazer. Precisa de internet.'),
            onTap: _excluirConta,
          ),
        ]),
      ),
    );
  }
}

/// Apaga todos os documentos de usuarios/{uid}/{tabela} (inclusive as fotos),
/// os pedidos de cotação da conta e o próprio usuarios/{uid}.
Future<void> apagarDadosDoUsuario(String uid) async {
  final banco = FirebaseFirestore.instance;
  final raiz = banco.collection('usuarios').doc(uid);
  await Equipe.apagarTudo(uid);
  Future<void> apagar(List<QueryDocumentSnapshot> docs) async {
    // Um lote do Firestore aceita no máximo 500 operações.
    for (var i = 0; i < docs.length; i += 400) {
      final lote = banco.batch();
      for (final d in docs.skip(i).take(400)) {
        lote.delete(d.reference);
      }
      await lote.commit();
    }
  }

  for (final t in [...Db.tabelas, 'fotos']) {
    await apagar((await raiz.collection(t).get(const GetOptions(source: Source.server))).docs);
  }
  try {
    await apagar((await banco
            .collection('pedidos_cotacao')
            .where('dono', isEqualTo: uid)
            .get(const GetOptions(source: Source.server)))
        .docs);
  } catch (_) {
    // Membro da equipe não tem pedidos próprios; a regra pode negar a consulta.
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
