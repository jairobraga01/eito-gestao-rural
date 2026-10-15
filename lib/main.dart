import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dados/db.dart';
import 'dados/equipe.dart';
import 'dispositivos/leitor_teclado.dart';
import 'firebase_options.dart';
import 'marca.dart';
import 'tema.dart';
import 'telas/backup.dart';
import 'telas/base.dart';
import 'telas/ficha_animal.dart';
import 'telas/chuva.dart';
import 'telas/custos.dart';
import 'telas/cotacao_arroba.dart';
import 'telas/dividas.dart';
import 'telas/dieta.dart';
import 'telas/entradas.dart';
import 'telas/equipe.dart';
import 'telas/estoque.dart';
import 'telas/inicio.dart';
import 'telas/login.dart';
import 'telas/financeiro.dart';
import 'telas/lotes.dart';
import 'telas/mapa.dart';
import 'telas/animais.dart';
import 'telas/piquetes.dart';
import 'telas/producao_leite.dart';
import 'telas/propriedades.dart';
import 'telas/proteinado.dart';
import 'telas/relatorios.dart';
import 'telas/reproducao.dart';
import 'telas/sanidade.dart';
import 'telas/vendas.dart';
import 'telas/vender_esperar.dart';
import 'widgets/logo_eito.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Modo offline obrigatório: tudo é gravado primeiro no aparelho e a
  // nuvem recebe sozinha quando o celular pega sinal.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  // E-mails de verificação e recuperação de senha em português.
  await FirebaseAuth.instance.setLanguageCode('pt');

  // Bastão RFID e balança no modo teclado: escuta o app inteiro.
  LeitorTeclado.instancia.iniciar();

  runApp(const EitoApp());
}

class EitoApp extends StatelessWidget {
  const EitoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Marca.nome,
      debugShowCheckedModeBanner: false,
      theme: temaEito(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const TelaCarregando();
          }
          final usuario = snap.data;
          if (usuario == null) return const TelaLogin();
          // A key garante dados novos se outra pessoa entrar.
          return CarregarDados(key: ValueKey(usuario.uid), usuario: usuario);
        },
      ),
    );
  }
}

/// Liga os dados do usuário (cópia no aparelho + nuvem) antes de abrir o app.
class CarregarDados extends StatefulWidget {
  const CarregarDados({super.key, required this.usuario});
  final User usuario;

  @override
  State<CarregarDados> createState() => _CarregarDadosState();
}

class _CarregarDadosState extends State<CarregarDados> {
  late Future<void> _pronto;

  @override
  void initState() {
    super.initState();
    Nav.secao.value = secPainel;
    _pronto = _iniciar();
  }

  /// Abre os dados do próprio usuário ou, se ele está numa equipe, os do dono.
  Future<void> _iniciar() async {
    var u = widget.usuario;
    final peao = ehLoginDePeao(u.email);
    // Quem acabou de confirmar o e-mail precisa de um token novo para ler o convite.
    if (!peao && !u.emailVerified) {
      try {
        await u.reload();
        u = FirebaseAuth.instance.currentUser ?? u;
        if (u.emailVerified) await u.getIdToken(true);
      } catch (_) {}
    }
    final acesso = await Equipe.procurarAcesso(u.uid, u.email);
    if (acesso == null && peao) {
      throw 'Este login não está ligado a nenhuma fazenda. Fale com o dono.';
    }
    await Db.iniciar(u.uid,
        dono: acesso?.dono, papel: acesso?.papel ?? 'dono', nome: acesso?.nome ?? u.displayName ?? u.email ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _pronto,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const TelaCarregando(mensagem: 'Carregando o rebanho…');
        }
        if (s.hasError || Db.prop.value == null) {
          return Scaffold(
            backgroundColor: Cores.olivaEscuro,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const LogoEito(tamanho: 88),
                  const SizedBox(height: 16),
                  Text('Não foi possível abrir os dados.\n${s.error ?? ''}',
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Cores.laranja, foregroundColor: Cores.azul),
                    onPressed: () => setState(() => _pronto = _iniciar()),
                    child: const Text('TENTAR DE NOVO'),
                  ),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('Sair da conta', style: TextStyle(color: Colors.white70)),
                  ),
                ]),
              ),
            ),
          );
        }
        return Inicio(usuario: widget.usuario);
      },
    );
  }
}

/// Mostra a seção escolhida no menu lateral. O botão Voltar leva ao Painel.
/// Encostar o bastão no brinco em qualquer seção abre a ficha rápida do animal.
class Inicio extends StatefulWidget {
  const Inicio({super.key, required this.usuario});
  final User usuario;

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  VoidCallback? _cancelarLeitor;

  @override
  void initState() {
    super.initState();
    Nav.usuario = widget.usuario;
    _cancelarLeitor = LeitorTeclado.instancia.assinar(_aoLer);
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    super.dispose();
  }

  Future<void> _aoLer(String codigo) async {
    // Só age se nenhuma outra tela estiver aberta por cima.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    await abrirPorCodigo(context, codigo);
  }

  static Widget _pagina(int i) => switch (i) {
        secPropriedades => const PropriedadesPage(),
        secLotes => const LotesPage(),
        secRebanho => const AnimaisPage(),
        secReproducao => const ReproducaoPage(),
        secSanidade => const SanidadePage(),
        secLeite => const ProducaoLeitePage(),
        secPiquetes => const PiquetesPage(),
        secPastagem => const PastagemPage(),
        secMapa => const MapaPage(),
        secEntradas => const EntradasPage(),
        secVendas => const SaidasPage(),
        secCustos => const CustosPage(),
        secDividas => const DividasPage(),
        secContas => const ContasPage(),
        secProteinado => const ProteinadoPage(),
        secEstoque => const EstoquePage(),
        secDieta => const DietaPage(),
        secCotacao => const CotacaoArrobaPage(),
        secVender => const VenderEsperarPage(),
        secChuva => const ChuvaPage(),
        secRelatorios => const RelatoriosPage(),
        secExportacoes => const ExportacoesPage(doMenu: true),
        secBackup => const BackupPage(),
        secTarefas => const TarefasPage(),
        secHistorico => const HistoricoPage(doMenu: true),
        _ => const InicioPage(),
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Nav.secao,
      builder: (context, i, _) => PopScope(
        canPop: i == secPainel,
        onPopInvokedWithResult: (saiu, _) {
          if (!saiu) Nav.ir(secPainel);
        },
        child: KeyedSubtree(key: ValueKey(i), child: _pagina(podeVer(i) ? i : secPainel)),
      ),
    );
  }
}
