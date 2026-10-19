import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/equipe.dart';
import '../dados/indicacoes.dart';
import '../dados/planos.dart';
import '../marca.dart';
import '../tema.dart';
import '../widgets/fundo_foto.dart';
import '../widgets/logo_eito.dart';

class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key});

  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _indicacao = TextEditingController();
  bool _criando = false;
  bool _ocupado = false;
  bool _verSenha = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    _indicacao.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final email = _email.text.trim(), senha = _senha.text;
    if (email.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Preencha o e-mail e a senha.');
      return;
    }
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (_criando) {
        // Código de indicação: só passa um código já cadastrado.
        Indicacao? indicacao;
        if (codigoIndicacao(_indicacao.text).isNotEmpty) {
          try {
            indicacao = await Indicacoes.buscar(_indicacao.text);
          } catch (e) {
            setState(() => _erro = 'Sem internet para conferir o código de indicação. Tente de novo.');
            return;
          }
          if (indicacao == null) {
            setState(() => _erro = 'Código inexistente, deixe em branco.');
            return;
          }
        }
        final cred = await auth.createUserWithEmailAndPassword(email: email, password: senha);
        await cred.user?.sendEmailVerification();
        if (indicacao != null) await _guardarIndicacao(cred.user, indicacao);
      } else {
        // Peão entra só com o usuário (sem @).
        await auth.signInWithEmailAndPassword(email: emailDoLogin(email), password: senha);
      }
    } on FirebaseAuthMultiFactorException catch (e) {
      await _segundaEtapa(e);
    } on FirebaseAuthException catch (e) {
      setState(() => _erro = _mensagem(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Verificação em duas etapas: pede o código de 6 dígitos do app autenticador.
  Future<void> _segundaEtapa(FirebaseAuthMultiFactorException e) async {
    final hint = e.resolver.hints.whereType<TotpMultiFactorInfo>().firstOrNull;
    if (hint == null) {
      setState(() => _erro = 'Esta conta usa um segundo passo que o Eito ainda não aceita.');
      return;
    }
    final ctrl = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Verificação em duas etapas'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'Código de 6 dígitos do app autenticador'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Entrar')),
        ],
      ),
    );
    ctrl.dispose();
    if (codigo == null || codigo.trim().isEmpty) return;
    try {
      final prova = await TotpMultiFactorGenerator.getAssertionForSignIn(hint.uid, codigo.trim());
      await e.resolver.resolveSignIn(prova);
    } on FirebaseAuthException catch (x) {
      setState(() => _erro = x.code == 'invalid-verification-code' ? 'Código errado ou vencido.' : _mensagem(x));
    }
  }

  /// Guarda o código de indicação no perfil, para contar as adesões por código.
  Future<void> _guardarIndicacao(User? user, Indicacao indicacao) async {
    if (user == null) return;
    try {
      await Indicacoes.registrarAdesao(user.uid, user.email, indicacao);
    } catch (e) {
      // A conta já foi criada; sem o código ela continua valendo.
      debugPrint('Eito: não deu para guardar a indicação: $e');
    }
  }

  Future<void> _esqueciSenha() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _erro = 'Digite seu e-mail acima para receber o link de nova senha.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _erro = 'Login de peão: peça ao dono da fazenda uma senha nova.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enviamos um link para $email. Confira também o spam.')),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _erro = _mensagem(e));
    }
  }

  String _mensagem(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'E-mail inválido.',
        'user-disabled' => 'Esta conta foi desativada.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' => 'E-mail ou senha incorretos.',
        'email-already-in-use' => 'Já existe uma conta com este e-mail. Toque em "Já tenho conta".',
        'weak-password' => 'A senha precisa ter pelo menos 6 caracteres.',
        'network-request-failed' =>
          'Sem internet. O primeiro acesso precisa de sinal; depois o Eito funciona sem internet.',
        'too-many-requests' => 'Muitas tentativas. Aguarde alguns minutos.',
        _ => 'Não foi possível entrar (${e.code}).',
      };

  @override
  Widget build(BuildContext context) {
    final largo = MediaQuery.sizeOf(context).width >= 900;
    if (largo) {
      // Computador: foto no painel lateral, formulário à direita.
      return Scaffold(
        backgroundColor: Cores.olivaEscuro,
        body: Row(children: [
          Expanded(
            flex: 6,
            child: FundoFoto(
              escurecer: 0.15,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: const _Marca(),
                  ),
                ),
              ),
            ),
          ),
          Expanded(flex: 4, child: _conteudo(mostrarMarca: false)),
        ]),
      );
    }
    // Celular: foto de fundo inteira, escurecida para o formulário aparecer.
    return Scaffold(
      backgroundColor: Cores.olivaEscuro,
      body: FundoFoto(escurecer: 0.55, child: _conteudo(mostrarMarca: true)),
    );
  }

  Widget _conteudo({required bool mostrarMarca}) {
    return SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(children: [
                if (mostrarMarca) ...[
                  const _Marca(),
                  const SizedBox(height: 20),
                ] else ...[
                  const LogoEito(tamanho: 72),
                  const SizedBox(height: 20),
                ],
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Cores.palha, borderRadius: BorderRadius.circular(20)),
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(_criando ? 'Criar conta' : 'Entrar',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(fontSize: 20),
                        decoration: const InputDecoration(labelText: 'E-mail (peão: usuário)', prefixIcon: Icon(Icons.email_outlined)),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _senha,
                        obscureText: !_verSenha,
                        autofillHints: [_criando ? AutofillHints.newPassword : AutofillHints.password],
                        onSubmitted: (_) => _enviar(),
                        style: const TextStyle(fontSize: 20),
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _verSenha ? 'Esconder senha' : 'Mostrar senha',
                            icon: Icon(_verSenha ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _verSenha = !_verSenha),
                          ),
                        ),
                      ),
                      if (_criando) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _indicacao,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          onSubmitted: (_) => _enviar(),
                          style: const TextStyle(fontSize: 20),
                          decoration: const InputDecoration(
                            labelText: 'Código de indicação (opcional)',
                            hintText: 'Ex.: pequeno',
                            helperText: 'Com código: $descontoIndicacao% de desconto na assinatura.',
                            prefixIcon: Icon(Icons.card_giftcard_outlined),
                          ),
                        ),
                      ],
                      if (_erro != null) ...[
                        const SizedBox(height: 12),
                        Text(_erro!, style: const TextStyle(color: Cores.alerta, fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Cores.laranja, foregroundColor: Cores.azul),
                        onPressed: _ocupado ? null : _enviar,
                        child: _ocupado
                            ? const SizedBox(
                                width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                            : Text(_criando ? 'CRIAR CONTA' : 'ENTRAR'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _ocupado ? null : () => setState(() {
                              _criando = !_criando;
                              _erro = null;
                            }),
                        child: Text(_criando ? 'Já tenho conta' : 'Criar uma conta nova',
                            style: const TextStyle(fontSize: 17)),
                      ),
                      if (!_criando)
                        TextButton(
                          onPressed: _ocupado ? null : _esqueciSenha,
                          child: const Text('Esqueci a senha', style: TextStyle(fontSize: 17)),
                        ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
    );
  }
}

/// Promoção, logomarca e frases, em cartões claros como o fundo da imagem.
class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) {
    const frase = TextStyle(color: Cores.tinta, fontSize: 17, height: 1.35);
    return Column(children: [
      const _Promocao(),
      const SizedBox(height: 8),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFAFBFA), foregroundColor: Cores.olivaEscuro),
        onPressed: () => launchUrl(Uri.base.resolve('/folder.html'), webOnlyWindowName: '_blank'),
        icon: const Icon(Icons.menu_book_outlined),
        label: const Text('Conheça o Eito: folder com todas as funções', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(color: const Color(0xFFFAFBFA), borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          Image.asset('assets/logo/eito_logomarca.png', width: 230, semanticLabel: Marca.nome),
          const SizedBox(height: 14),
          Container(width: 56, height: 3, decoration: BoxDecoration(color: Cores.laranja, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          const Text(Marca.slogan,
              textAlign: TextAlign.center,
              style: TextStyle(color: Cores.olivaEscuro, fontSize: 20, height: 1.3, fontWeight: FontWeight.w700)),
          for (final t in Marca.apresentacao) ...[
            const SizedBox(height: 12),
            Text(t, textAlign: TextAlign.center, style: frase),
          ],
          const SizedBox(height: 14),
          const Text(Marca.fechamento,
              textAlign: TextAlign.center,
              style: TextStyle(color: Cores.olivaEscuro, fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
      ),
    ]);
  }
}

/// Faixa da promoção de assinatura, no topo da tela de login.
class _Promocao extends StatelessWidget {
  const _Promocao();

  @override
  Widget build(BuildContext context) {
    Widget plano(PlanoEito p) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text('Fazenda ${p.nome}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Cores.tinta, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(p.maxAnimais == null ? 'sem limite' : 'até ${p.maxAnimais} animais',
                  textAlign: TextAlign.center, style: const TextStyle(color: Cores.tinta, fontSize: 12)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('R\$ ${p.mes}',
                    style: const TextStyle(color: Cores.olivaEscuro, fontSize: 22, fontWeight: FontWeight.w900)),
              ),
              const Text('por mês', style: TextStyle(color: Cores.tinta, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('ou R\$ ${p.ano}/ano',
                    style: const TextStyle(color: Cores.tinta, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Cores.laranja, borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        const Text('ASSINE HOJE',
            style: TextStyle(color: Cores.olivaEscuro, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        const SizedBox(height: 10),
        Row(children: [
          for (final (i, p) in PlanoEito.todos.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            plano(p),
          ],
        ]),
        const SizedBox(height: 10),
        const Text('Com código de indicação: $descontoIndicacao% de desconto.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Cores.olivaEscuro, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Promoção por tempo limitado.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Cores.olivaEscuro, fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

