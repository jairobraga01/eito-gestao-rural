import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../dados/equipe.dart';
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
  bool _criando = false;
  bool _ocupado = false;
  bool _verSenha = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
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
        final cred = await auth.createUserWithEmailAndPassword(email: email, password: senha);
        await cred.user?.sendEmailVerification();
      } else {
        // Peão entra só com o usuário (sem @).
        await auth.signInWithEmailAndPassword(email: emailDoLogin(email), password: senha);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _erro = _mensagem(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
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

/// Logomarca com as frases, num cartão claro igual ao fundo da imagem.
class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) {
    const frase = TextStyle(color: Cores.tinta, fontSize: 17, height: 1.35);
    return Container(
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
    );
  }
}
