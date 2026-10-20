import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/plataforma.dart';
import '../marca.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';

const _faq = <(String, String)>[
  ('O app funciona sem internet?',
      'Sim. Tudo é gravado primeiro no aparelho. Quando o celular pega sinal, o Eito envia sozinho. A faixa no topo mostra quantos lançamentos ainda estão esperando sinal.'),
  ('Como uso o bastão de brinco ou a balança?',
      'Abra o menu › Bastão e balança. A maioria dos bastões funciona como teclado: encoste no brinco em qualquer tela e a ficha do animal abre. No Modo Curral o peso da balança entra direto no lançamento.'),
  ('Como coloco meu rebanho de uma vez?',
      'Em Rebanho, toque no ícone de planilha (importar). Baixe o modelo, preencha no Excel, salve como CSV e escolha o arquivo. O Eito confere cada linha antes de gravar.'),
  ('Como coloco o peão ou o veterinário?',
      'Menu › Equipe e permissões. O peão entra só com usuário e senha que você cria e não vê o financeiro. O veterinário vê rebanho, reprodução e sanidade.'),
  ('A carência do remédio bloqueia a venda?',
      'Sim. Ao lançar uma aplicação com carência, o animal aparece com aviso e o Eito alerta se você tentar vender para abate antes do prazo.'),
  ('Como vejo quanto vale a fazenda?',
      'Financeiro › Patrimônio. Informe o valor por cabeça de cada categoria, o valor do hectare e os bens. As dívidas em aberto já entram no cálculo.'),
  ('Esqueci a senha.',
      'Na tela de entrada, digite o e-mail e toque em "Esqueci a senha". O link chega no e-mail (confira o spam). Login de peão: o dono cria uma senha nova em Equipe.'),
  ('Como faço backup?',
      'Relatórios e dados › Backup. O arquivo guarda todo o rebanho e os lançamentos. Os dados também ficam na nuvem, ligados ao seu e-mail.'),
];

/// Ajuda e suporte: dúvidas frequentes e chamados com a equipe do Eito.
class AjudaPage extends StatelessWidget {
  const AjudaPage({super.key, this.abaInicial = 0});
  final int abaInicial;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: abaInicial,
      child: Pagina(
        titulo: 'Ajuda e suporte',
        corpo: Column(children: [
          const Material(
            color: Cores.palha,
            child: TabBar(tabs: [Tab(text: 'Dúvidas frequentes'), Tab(text: 'Meus chamados')]),
          ),
          const Expanded(child: TabBarView(children: [_Duvidas(), _MeusChamados()])),
        ]),
      ),
    );
  }
}

class _Duvidas extends StatelessWidget {
  const _Duvidas();

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        ListTile(
          leading: const Icon(Icons.menu_book_outlined, color: Cores.oliva),
          title: const Text('Folder do Eito: todas as funções explicadas', style: TextStyle(fontWeight: FontWeight.w700)),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.base.resolve('/folder.html'), webOnlyWindowName: '_blank'),
        ),
        for (final (p, r) in _faq)
          ExpansionTile(
            leading: const Icon(Icons.help_outline, color: Cores.oliva),
            title: Text(p, style: const TextStyle(fontWeight: FontWeight.w600)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedAlignment: Alignment.centerLeft,
            children: [Text(r)],
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.support_agent),
            label: const Text('Não achei: falar com o suporte'),
            onPressed: () => novoChamado(context),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.mail_outline, color: Cores.oliva),
          title: const Text('E-mail do Eito'),
          subtitle: const Text(Marca.email),
          onTap: () => launchUrl(Uri.parse('mailto:${Marca.email}')),
        ),
      ]);
}

Future<void> novoChamado(BuildContext context) async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return;
  final assunto = TextEditingController();
  final texto = TextEditingController();
  var categoria = categoriasChamado.first;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Novo chamado'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            escolha('Assunto do chamado', categoria, categoriasChamado, (v) => set(() => categoria = v ?? categoria)),
            gap,
            campoTexto(assunto, 'Resumo (ex.: não consigo lançar pesagem)', foco: true),
            gap,
            campoTexto(texto, 'Conte o que aconteceu', linhas: 5),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    ),
  );
  final a = assunto.text.trim(), t = texto.text.trim();
  assunto.dispose();
  texto.dispose();
  if (ok != true) return;
  if (a.isEmpty || t.isEmpty) {
    if (context.mounted) avisar(context, 'Preencha o resumo e a mensagem.');
    return;
  }
  try {
    final id = await Plataforma.abrirChamado(u, assunto: a, categoria: categoria, texto: t);
    if (!context.mounted) return;
    avisar(context, 'Chamado enviado. A resposta aparece no sininho.');
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChamadoPage(id: id, equipe: false)));
  } catch (e) {
    if (context.mounted) avisar(context, 'Não foi possível enviar: $e');
  }
}

class _MeusChamados extends StatelessWidget {
  const _MeusChamados();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Novo chamado'),
        onPressed: () => novoChamado(context),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Plataforma.chamados.where('uid', isEqualTo: uid).snapshots(),
        builder: (context, s) {
          if (s.hasError) return Vazio('Não deu para carregar os chamados: ${s.error}', icone: Icons.error_outline);
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = [...s.data!.docs]..sort((a, b) =>
              (dataDe(b.data()['atualizado_em']) ?? DateTime(2100)).compareTo(dataDe(a.data()['atualizado_em']) ?? DateTime(2100)));
          if (docs.isEmpty) return const Vazio('Nenhum chamado ainda.', icone: Icons.support_agent);
          return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            for (final d in docs) ItemChamado(d: d, equipe: false),
          ]);
        },
      ),
    );
  }
}

String rotuloStatus(Object? s) => switch ('$s') {
      'respondido' => 'Respondido',
      'fechado' => 'Fechado',
      _ => 'Aberto',
    };

class ItemChamado extends StatelessWidget {
  const ItemChamado({super.key, required this.d, required this.equipe});
  final QueryDocumentSnapshot<Map<String, dynamic>> d;
  final bool equipe;

  @override
  Widget build(BuildContext context) {
    final c = d.data();
    final naoLido = equipe ? c['lido_equipe'] == false : c['lido_cliente'] == false;
    final em = dataDe(c['atualizado_em']);
    return ListTile(
      leading: Icon(
        c['status'] == 'fechado' ? Icons.check_circle_outline : Icons.chat_bubble_outline,
        color: naoLido ? Cores.alerta : Cores.oliva,
      ),
      title: Text('${c['assunto'] ?? ''}', style: TextStyle(fontWeight: naoLido ? FontWeight.w800 : FontWeight.w500)),
      subtitle: Text([
        if (equipe) '${c['email'] ?? ''}',
        '${c['categoria'] ?? ''} · ${rotuloStatus(c['status'])}${c['prioridade'] == 'alta' ? ' · prioridade alta' : ''}',
        if (em != null) br(em.toIso8601String()),
      ].join('\n')),
      isThreeLine: equipe,
      trailing: naoLido ? const Icon(Icons.circle, size: 12, color: Cores.alerta) : null,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChamadoPage(id: d.id, equipe: equipe))),
    );
  }
}

/// Conversa de um chamado (cliente ou criador).
class ChamadoPage extends StatefulWidget {
  const ChamadoPage({super.key, required this.id, required this.equipe});
  final String id;
  final bool equipe;

  @override
  State<ChamadoPage> createState() => _ChamadoPageState();
}

class _ChamadoPageState extends State<ChamadoPage> {
  final _texto = TextEditingController();
  bool _enviando = false;
  bool _marcado = false;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final t = _texto.text.trim();
    if (t.isEmpty) return;
    setState(() => _enviando = true);
    final u = FirebaseAuth.instance.currentUser;
    try {
      await Plataforma.responder(widget.id, t,
          equipe: widget.equipe, nome: widget.equipe ? 'Suporte Eito' : (u?.displayName ?? u?.email ?? 'Cliente'));
      _texto.clear();
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível enviar: $e');
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Plataforma.chamados.doc(widget.id).snapshots(),
      builder: (context, s) {
        final c = s.data?.data();
        if (c != null && !_marcado) {
          final campo = widget.equipe ? 'lido_equipe' : 'lido_cliente';
          if (c[campo] == false) {
            _marcado = true;
            Plataforma.marcarLido(widget.id, equipe: widget.equipe).catchError((_) {});
          }
        }
        final msgs = [
          for (final m in (c?['mensagens'] as List?) ?? const [])
            if (m is Map) Map<String, dynamic>.from(m),
        ];
        final fechado = c?['status'] == 'fechado';
        return Scaffold(
          appBar: AppBar(
            title: Text('${c?['assunto'] ?? 'Chamado'}'),
            actions: [
              if (c != null)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'fechar') await Plataforma.mudarStatus(widget.id, 'fechado');
                    if (v == 'reabrir') await Plataforma.mudarStatus(widget.id, 'aberto');
                    if (v == 'alta' || v == 'normal') {
                      await Plataforma.chamados.doc(widget.id).update({'prioridade': v});
                    }
                  },
                  itemBuilder: (_) => [
                    if (!fechado) const PopupMenuItem(value: 'fechar', child: Text('Marcar como resolvido')),
                    if (fechado) const PopupMenuItem(value: 'reabrir', child: Text('Reabrir')),
                    if (widget.equipe && c['prioridade'] != 'alta')
                      const PopupMenuItem(value: 'alta', child: Text('Prioridade alta')),
                    if (widget.equipe && c['prioridade'] == 'alta')
                      const PopupMenuItem(value: 'normal', child: Text('Prioridade normal')),
                  ],
                ),
            ],
          ),
          body: Column(children: [
            if (widget.equipe && c != null)
              Container(
                width: double.infinity,
                color: Cores.palha,
                padding: const EdgeInsets.all(12),
                child: Text('${c['nome'] ?? ''} · ${c['email'] ?? ''}\n${c['categoria'] ?? ''} · ${rotuloStatus(c['status'])}'),
              ),
            Expanded(
              child: c == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      for (final m in msgs) _Balao(m: m, minha: (m['de'] == 'equipe') == widget.equipe),
                    ]),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _texto,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                          hintText: fechado ? 'Escreva para reabrir o chamado' : 'Escreva sua mensagem'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _enviando ? null : _enviar,
                    icon: const Icon(Icons.send),
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Balao extends StatelessWidget {
  const _Balao({required this.m, required this.minha});
  final Map<String, dynamic> m;
  final bool minha;

  @override
  Widget build(BuildContext context) {
    final em = DateTime.tryParse('${m['em'] ?? ''}');
    return Align(
      alignment: minha ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: minha ? Cores.oliva.withValues(alpha: 0.12) : Cores.azul.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${m['nome'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 4),
          Text('${m['texto'] ?? ''}'),
          if (em != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  '${br(em.toIso8601String())} ${em.hour.toString().padLeft(2, '0')}:${em.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
        ]),
      ),
    );
  }
}
