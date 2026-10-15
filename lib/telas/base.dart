// Estrutura comum: menu lateral, faixa da propriedade e botão + com atalhos.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../marca.dart';
import '../tema.dart';
import '../util/util.dart';
import '../widgets/barra_sincronia.dart';
import '../widgets/logo_eito.dart';
import 'animais.dart';
import 'conta.dart';
import 'dispositivos.dart';
import 'lotes.dart';
import 'modo_curral.dart';
import 'propriedades.dart';
import 'reproducao.dart';
import 'sanidade.dart';

/// Seção mostrada pelo menu lateral (índice em [itensMenu]).
class Nav {
  Nav._();
  static final secao = ValueNotifier<int>(0);
  static void ir(int i) => secao.value = i;

  /// Usuário logado (mostrado no menu).
  static User? usuario;
}

const itensMenu = <(String, IconData)>[
  ('Painel', Icons.dashboard_outlined),
  ('Propriedades', Icons.home_work_outlined),
  ('Lotes', Icons.workspaces_outline),
  ('Rebanho', Icons.pets_outlined),
  ('Reprodução', Icons.favorite_border),
  ('Sanidade e pesagens', Icons.vaccines_outlined),
  ('Piquetes', Icons.fence),
  ('Pastagem', Icons.grass),
  ('Vendas e saídas', Icons.sell_outlined),
  ('Relatórios', Icons.bar_chart),
  ('Backup', Icons.backup_outlined),
];

// Índices usados pelos atalhos.
const secPainel = 0, secPropriedades = 1, secLotes = 2, secRebanho = 3, secReproducao = 4,
    secSanidade = 5, secPiquetes = 6, secPastagem = 7, secVendas = 8, secRelatorios = 9, secBackup = 10;

/// Abre o Modo Curral (atalho para lançar o serviço do curral).
void abrirModoCurral(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ModoCurral()));

Future<void> sairDaConta(BuildContext context) async {
  final pendentes = Db.pendentes.value;
  final ok = await confirmar(
    context,
    'Sair da conta?',
    pendentes == 0
        ? 'Para voltar, entre de novo com o mesmo e-mail e senha.'
        : 'Há $pendentes lançamento(s) ainda sem sinal. Entre de novo com esta mesma conta para que sejam enviados.',
    ok: 'Sair',
  );
  if (!ok) return;
  await Db.encerrar();
  await FirebaseAuth.instance.signOut();
}

class MenuLateral extends StatelessWidget {
  const MenuLateral({super.key, this.fixo = false});

  /// Menu sempre aberto ao lado (telas largas, como no computador).
  final bool fixo;

  @override
  Widget build(BuildContext context) {
    void fechar() {
      if (!fixo) Navigator.pop(context);
    }

    Widget item(IconData icone, String texto, VoidCallback onTap, {bool atual = false, Color? cor}) {
      return ListTile(
        leading: Icon(icone, color: cor ?? (atual ? Cores.laranja : Cores.oliva)),
        title: Text(texto,
            style: TextStyle(
              fontSize: 16,
              color: cor ?? (atual ? Cores.oliva : Cores.tinta),
              fontWeight: atual ? FontWeight.w800 : FontWeight.w500,
            )),
        selected: atual,
        selectedTileColor: Cores.oliva.withValues(alpha: 0.10),
        onTap: onTap,
      );
    }

    return Drawer(
      backgroundColor: Cores.palha,
      shape: fixo ? const RoundedRectangleBorder() : null,
      child: ValueListenableBuilder<int>(
        valueListenable: Nav.secao,
        builder: (context, atual, _) => ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              color: Cores.olivaEscuro,
              padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 20, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    LogoEito(tamanho: 48),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(Marca.nome,
                          style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<Reg?>(
                    valueListenable: Db.prop,
                    builder: (c, p, _) => Text(txt(p?['nome']),
                        style: const TextStyle(color: Cores.laranja, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  if (Nav.usuario?.email != null)
                    Text(Nav.usuario!.email!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            item(itensMenu[0].$2, itensMenu[0].$1, () {
              fechar();
              Nav.ir(0);
            }, atual: atual == 0),
            // Modo Curral: atalho, abre por cima do app.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Material(
                color: Cores.laranja,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.contactless_outlined, color: Colors.white),
                  title: const Text('Modo Curral',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  subtitle: const Text('Lançar o serviço do curral', style: TextStyle(color: Colors.white70)),
                  onTap: () {
                    fechar();
                    abrirModoCurral(context);
                  },
                ),
              ),
            ),
            for (var i = 1; i < itensMenu.length; i++)
              item(itensMenu[i].$2, itensMenu[i].$1, () {
                fechar();
                Nav.ir(i);
              }, atual: i == atual),
            const Divider(),
            item(Icons.bluetooth, 'Bastão e balança', () {
              fechar();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaDispositivos()));
            }),
            item(Icons.manage_accounts_outlined, 'Minha conta', () {
              fechar();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaConta()));
            }),
            item(Icons.logout, 'Sair da conta', () {
              fechar();
              sairDaConta(context);
            }, cor: Cores.alerta),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Faixa com a propriedade atual; tocar troca de propriedade.
class PropriedadeBar extends StatelessWidget {
  const PropriedadeBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Reg?>(
      valueListenable: Db.prop,
      builder: (context, p, _) => Material(
        color: Cores.oliva,
        child: InkWell(
          onTap: () => escolherPropriedade(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.home_work_outlined, color: Colors.white70),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    txt(p?['nome']).toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, letterSpacing: 0.4, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, color: Cores.laranja, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> escolherPropriedade(BuildContext context) async {
  final props = await Db.propriedades();
  if (!context.mounted) return;
  final op = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Escolha a propriedade', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final p in props)
            ListTile(
              leading: Icon(p['id'] == Db.pid ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: Cores.oliva),
              title: Text(txt(p['nome'])),
              subtitle: Text('${p['qtd']} animal(is)${txt(p['uf']).isEmpty ? '' : ' · ${p['uf']}'}'),
              onTap: () => Navigator.pop(c, p['id']),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Adicionar propriedade'),
            onTap: () => Navigator.pop(c, 'nova'),
          ),
        ],
      ),
    ),
  );
  if (op is int) {
    await Db.selecionarPropriedade(op);
  } else if (op == 'nova' && context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PropriedadeFormPage()));
  }
}

/// Tela principal de uma seção: barra do Eito, menu lateral e faixa da propriedade.
/// Em telas largas (computador), o menu fica sempre aberto à esquerda.
class Pagina extends StatelessWidget {
  const Pagina({super.key, required this.titulo, required this.corpo, this.fab, this.acoes});
  final String titulo;
  final Widget corpo;
  final Widget? fab;
  final List<Widget>? acoes;

  @override
  Widget build(BuildContext context) {
    final largo = MediaQuery.sizeOf(context).width >= 1000;
    final conteudo = Column(children: [
      const BarraSincronia(),
      const PropriedadeBar(),
      Expanded(child: corpo),
    ]);
    return Scaffold(
      drawer: largo ? null : const MenuLateral(),
      appBar: AppBar(
        automaticallyImplyLeading: !largo,
        title: Text(titulo),
        actions: [
          ...?acoes,
          IconButton(
            tooltip: 'Modo Curral',
            icon: const Icon(Icons.contactless_outlined, color: Cores.laranja),
            onPressed: () => abrirModoCurral(context),
          ),
        ],
      ),
      floatingActionButton: fab,
      body: largo
          ? Row(children: [
              const SizedBox(width: 290, child: MenuLateral(fixo: true)),
              const VerticalDivider(width: 1),
              Expanded(child: conteudo),
            ])
          : conteudo,
    );
  }
}

/// Botão + que abre os atalhos de cadastro.
class AcoesFab extends StatelessWidget {
  const AcoesFab({super.key});

  static final _itens = <(String, IconData, Widget Function())>[
    ('Modo Curral', Icons.contactless_outlined, () => const ModoCurral()),
    ('Propriedade', Icons.home_work_outlined, () => const PropriedadeFormPage()),
    ('Lote', Icons.workspaces_outline, () => const LoteFormPage()),
    ('Animal', Icons.pets, () => const AnimalFormPage()),
    ('Nascimento', Icons.child_friendly_outlined, () => const NascimentoFormPage()),
    ('Reprodução', Icons.favorite_border, () => const ReproducaoFormPage()),
    ('Sanidade', Icons.vaccines_outlined, () => const SanidadeFormPage()),
    ('Pesagem', Icons.monitor_weight_outlined, () => const PesagemFormPage()),
  ];

  void _abrir(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar',
      barrierColor: Colors.black54,
      pageBuilder: (c, _, __) => SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              type: MaterialType.transparency,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (i, it) in _itens.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12, right: 4),
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(c);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => it.$3()));
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: i == 0 ? Cores.laranja : Cores.palha,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(it.$1.toUpperCase(),
                                    style: TextStyle(
                                        color: i == 0 ? Colors.white : Cores.tinta,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4)),
                              ),
                              const SizedBox(width: 12),
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: i == 0 ? Cores.laranja : Cores.palha,
                                child: Icon(it.$2, color: i == 0 ? Colors.white : Cores.oliva),
                              ),
                            ],
                          ),
                        ),
                      ),
                    FloatingActionButton(
                      heroTag: null,
                      onPressed: () => Navigator.pop(c),
                      child: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FloatingActionButton(
        heroTag: null,
        tooltip: 'Adicionar',
        onPressed: () => _abrir(context),
        child: const Icon(Icons.add, size: 32),
      );
}
