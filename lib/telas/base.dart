// Estrutura comum: menu lateral, faixa da propriedade e botão + com atalhos.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/equipe.dart';
import '../marca.dart';
import '../tema.dart';
import '../util/util.dart';
import '../widgets/barra_sincronia.dart';
import '../widgets/logo_eito.dart';
import 'animais.dart';
import 'conta.dart';
import 'dispositivos.dart';
import 'equipe.dart';
import 'lotes.dart';
import 'modo_curral.dart';
import 'modo_inseminacao.dart';
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
  ('Produção leiteira', Icons.local_drink_outlined),
  ('Piquete/Pasto', Icons.fence),
  ('Pastagem', Icons.grass),
  ('Mapa e ocorrências', Icons.map_outlined),
  ('Compras e entradas', Icons.arrow_circle_down_outlined),
  ('Vendas e saídas', Icons.arrow_circle_up_outlined),
  ('Custos e margem', Icons.attach_money),
  ('Dívidas e ônus reais', Icons.account_balance_outlined),
  ('Contas a pagar e receber', Icons.receipt_long_outlined),
  ('Proteinado', Icons.agriculture_outlined),
  ('Estoque de insumos', Icons.inventory_2_outlined),
  ('Dieta do cocho', Icons.restaurant_outlined),
  ('Cotação da arroba', Icons.trending_up),
  ('Vender ou esperar', Icons.balance),
  ('Chuva', Icons.water_drop_outlined),
  ('Relatórios', Icons.bar_chart),
  ('Exportações (contador, LCDPR, GTA)', Icons.ios_share),
  ('Backup', Icons.backup_outlined),
  ('Tarefas', Icons.task_alt),
  ('Quem lançou o quê', Icons.history),
  ('Relatório financeiro', Icons.summarize_outlined),
];

// Índices usados pelos atalhos.
const secPainel = 0, secPropriedades = 1, secLotes = 2, secRebanho = 3, secReproducao = 4,
    secSanidade = 5, secLeite = 6, secPiquetes = 7, secPastagem = 8, secMapa = 9, secEntradas = 10, secVendas = 11,
    secCustos = 12, secDividas = 13, secContas = 14, secProteinado = 15, secEstoque = 16, secDieta = 17,
    secCotacao = 18, secVender = 19, secChuva = 20, secRelatorios = 21, secExportacoes = 22, secBackup = 23,
    secTarefas = 24, secHistorico = 25, secRelatorioFinanceiro = 26;

/// Menu lateral agrupado por tópico (índices de [itensMenu]).
const gruposMenu = <(String, IconData, List<int>)>[
  ('Rebanho', Icons.pets_outlined, [secRebanho, secLotes, secReproducao, secSanidade, secLeite, secEntradas, secVendas]),
  ('Pasto e fazenda', Icons.grass, [secPropriedades, secPiquetes, secPastagem, secMapa, secChuva]),
  ('Nutrição', Icons.agriculture_outlined, [secProteinado, secEstoque, secDieta]),
  ('Financeiro', Icons.attach_money,
      [secRelatorioFinanceiro, secCustos, secContas, secDividas, secCotacao, secVender]),
  ('Relatórios e dados', Icons.bar_chart, [secRelatorios, secExportacoes, secHistorico, secBackup]),
];

/// Seções que o peão vê: o serviço de campo, sem financeiro nem cadastros da fazenda.
const secoesPeao = {
  secPainel, secRebanho, secReproducao, secSanidade, secLeite, secPiquetes, secPastagem, secMapa, secChuva, secTarefas,
};

/// Seções que o veterinário vê: rebanho, reprodução e sanidade.
const secoesVeterinario = {secPainel, secRebanho, secReproducao, secSanidade, secTarefas};

/// Seções só do dono (nem o gerente vê).
const secoesDono = {secRelatorioFinanceiro};

/// Se quem está usando pode abrir a seção (o dono vê tudo; o gerente, tudo menos o que é só do dono).
bool podeVer(int secao) {
  if (Db.ehPeao) return secoesPeao.contains(secao);
  if (Db.ehVeterinario) return secoesVeterinario.contains(secao);
  return Db.ehDono || !secoesDono.contains(secao);
}

/// Abre o Modo Curral (atalho para lançar o serviço do curral).
void abrirModoCurral(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ModoCurral()));

/// Abre o Modo Inseminação (IA/IATF e diagnóstico em série).
void abrirModoInseminacao(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ModoInseminacao()));

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
                  if (Equipe.atual != null)
                    Text(
                        '${papeis[Equipe.atual!.papel] ?? ''} · fazenda de '
                        '${Equipe.atual!.donoNome.isEmpty ? 'outra conta' : Equipe.atual!.donoNome}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
            // Modo Inseminação: logo abaixo do Modo Curral.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Material(
                color: Cores.azul,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.favorite_border, color: Cores.laranja),
                  title: const Text('Modo Inseminação',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  subtitle: const Text('IA, IATF e diagnóstico', style: TextStyle(color: Colors.white70)),
                  onTap: () {
                    fechar();
                    abrirModoInseminacao(context);
                  },
                ),
              ),
            ),
            item(itensMenu[secTarefas].$2, itensMenu[secTarefas].$1, () {
              fechar();
              Nav.ir(secTarefas);
            }, atual: atual == secTarefas),
            for (final (titulo, icone, todos) in gruposMenu)
              if (todos.where(podeVer).toList() case final itens when itens.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: PageStorageKey('menu_$titulo'),
                  leading: Icon(icone, color: itens.contains(atual) ? Cores.laranja : Cores.oliva),
                  title: Text(titulo,
                      style: const TextStyle(fontSize: 16, color: Cores.tinta, fontWeight: FontWeight.w800)),
                  initiallyExpanded: itens.contains(atual),
                  childrenPadding: const EdgeInsets.only(left: 12),
                  children: [
                    for (final i in itens)
                      item(itensMenu[i].$2, itensMenu[i].$1, () {
                        fechar();
                        Nav.ir(i);
                      }, atual: i == atual),
                  ],
                ),
              ),
            const Divider(),
            item(Icons.bluetooth, 'Bastão e balança', () {
              fechar();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaDispositivos()));
            }),
            if (Db.ehDono)
              item(Icons.group_outlined, 'Equipe e permissões', () {
                fechar();
                Navigator.push(context, MaterialPageRoute(builder: (_) => const EquipePage()));
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
          if (!Db.ehCampo) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Adicionar propriedade'),
            onTap: () => Navigator.pop(c, 'nova'),
          ),
          ],
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
                    for (final (i, it) in _itens
                        .where((it) => !Db.ehCampo || (it.$1 != 'Propriedade' && it.$1 != 'Lote'))
                        .indexed)
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
