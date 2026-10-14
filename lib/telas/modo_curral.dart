import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../dados/repositorio.dart';
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../widgets/barra_sincronia.dart';
import '../widgets/botao_curral.dart';
import '../widgets/logo_eito.dart';
import '../widgets/teclado_grande.dart';
import 'dispositivos.dart';
import 'ficha_animal.dart';
import 'manejo_em_serie.dart';
import 'novo_animal.dart';
import 'rebanho.dart';

/// Tela principal. Pensada para o curral: encostou o bastão no brinco,
/// abre a ficha do animal. Tudo o mais em botões grandes.
class ModoCurral extends StatefulWidget {
  const ModoCurral({super.key, required this.usuario});
  final User usuario;

  @override
  State<ModoCurral> createState() => _ModoCurralState();
}

class _ModoCurralState extends State<ModoCurral> {
  late final Repositorio repo = Repositorio(widget.usuario.uid);
  // Mantém o rebanho sempre ouvindo: assim ele fica inteiro no aparelho
  // e a busca por brinco funciona no meio do pasto, sem sinal.
  late final Stream<List<Animal>> _rebanho = repo.rebanhoAtivo();
  VoidCallback? _cancelarLeitor;

  @override
  void initState() {
    super.initState();
    LeitorTeclado.instancia.iniciar();
    _cancelarLeitor = LeitorTeclado.instancia.assinar(_abrirPorCodigo);
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    super.dispose();
  }

  void _ir(Widget tela) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => tela));

  Future<void> _abrirPorCodigo(String codigo) async {
    final animal = await repo.buscarPorCodigo(codigo);
    if (!mounted) return;
    if (animal != null) {
      _ir(FichaAnimal(repo: repo, animalId: animal.id));
      return;
    }
    final cadastrar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Brinco não cadastrado'),
        content: Text('Nenhum animal com o brinco $codigo.', style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('IGNORAR')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CADASTRAR')),
        ],
      ),
    );
    if (cadastrar == true && mounted) _ir(NovoAnimal(repo: repo, codigoLido: codigo));
  }

  Future<void> _digitarBrinco() async {
    final codigo = await pedirNumero(context, titulo: 'Número do brinco');
    if (codigo != null && codigo.trim().isNotEmpty) _abrirPorCodigo(codigo.trim());
  }

  Future<void> _sair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text(
            'Se houver lançamentos ainda sem sinal, entre de novo com esta mesma conta para que sejam enviados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SAIR')),
        ],
      ),
    );
    if (ok == true) await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const Row(children: [
          LogoEito(tamanho: 36),
          SizedBox(width: 10),
          Text('Eito · Modo Curral'),
        ]),
        actions: [
          IconButton(
            tooltip: 'Bastão e balança',
            icon: const Icon(Icons.bluetooth),
            onPressed: () => _ir(const TelaDispositivos()),
          ),
          PopupMenuButton<String>(
            iconSize: 28,
            onSelected: (v) {
              if (v == 'sair') _sair();
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(widget.usuario.email ?? '')),
              const PopupMenuItem(value: 'sair', child: Text('Sair da conta', style: TextStyle(fontSize: 18))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        BarraSincronia(repo: repo),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _PainelLeitura(aoDigitar: _digitarBrinco),
            const SizedBox(height: 16),
            StreamBuilder<List<Animal>>(
              stream: _rebanho,
              builder: (context, snap) {
                final total = snap.data?.length;
                return GridView.count(
                  crossAxisCount: largura >= 720 ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: largura >= 720 ? 1.3 : 1.05,
                  children: [
                    BotaoCurral(
                      icone: Icons.monitor_weight_outlined,
                      rotulo: 'Pesagem\nem série',
                      cor: Cores.laranja,
                      aoTocar: () => _ir(ManejoEmSerie(repo: repo, modo: ModoSerie.pesagem)),
                    ),
                    BotaoCurral(
                      icone: Icons.vaccines_outlined,
                      rotulo: 'Vacinação\nem série',
                      cor: Cores.oliva,
                      aoTocar: () => _ir(ManejoEmSerie(repo: repo, modo: ModoSerie.sanidade)),
                    ),
                    BotaoCurral(
                      icone: Icons.add_circle_outline,
                      rotulo: 'Novo\nanimal',
                      cor: Cores.olivaClaro,
                      aoTocar: () => _ir(NovoAnimal(repo: repo)),
                    ),
                    BotaoCurral(
                      icone: Icons.format_list_numbered,
                      rotulo: 'Rebanho',
                      detalhe: total == null ? null : '$total ${total == 1 ? 'cabeça' : 'cabeças'}',
                      cor: Cores.olivaEscuro,
                      aoTocar: () => _ir(TelaRebanho(repo: repo)),
                    ),
                  ],
                );
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

class _PainelLeitura extends StatelessWidget {
  const _PainelLeitura({required this.aoDigitar});
  final VoidCallback aoDigitar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Cores.olivaEscuro,
        borderRadius: BorderRadius.circular(20),
        // Foto do gado bem escurecida: dá identidade sem atrapalhar a leitura no sol.
        image: DecorationImage(
          image: const AssetImage('assets/imagens/fundo_gado.jpg'),
          fit: BoxFit.cover,
          alignment: const Alignment(0.35, -0.2),
          colorFilter: ColorFilter.mode(Cores.olivaEscuro.withOpacity(0.72), BlendMode.srcATop),
          onError: (_, __) {},
        ),
      ),
      child: Column(children: [
        const Icon(Icons.contactless_outlined, size: 72, color: Cores.laranja),
        const SizedBox(height: 8),
        const Text('Encoste o bastão no brinco',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('A ficha do animal abre sozinha.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 17)),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Cores.laranja, minimumSize: const Size.fromHeight(68)),
          onPressed: aoDigitar,
          icon: const Icon(Icons.dialpad, size: 30),
          label: const Text('DIGITAR Nº DO BRINCO'),
        ),
      ]),
    );
  }
}
