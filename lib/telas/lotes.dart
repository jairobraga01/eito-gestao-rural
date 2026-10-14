import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../util/util.dart';
import 'animais.dart';
import 'base.dart';
import 'mover.dart';

class _ResumoLotes {
  _ResumoLotes(this.ativos, this.inativos, this.semLote);
  final List<Reg> ativos, inativos;
  final int semLote;
}

Future<_ResumoLotes> _carregar() async {
  final todos = await Db.lotes();
  return _ResumoLotes(
    todos.where(Db.loteAtivo).toList(),
    todos.where((l) => !Db.loteAtivo(l)).toList(),
    await Db.contarSemLote(),
  );
}

class LotesPage extends StatelessWidget {
  const LotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Lotes',
      fab: const AcoesFab(),
      corpo: AoMudar<_ResumoLotes>(
        carregar: _carregar,
        builder: (context, r) => ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            const Secao('Resumo'),
            SizedBox(
              height: 118,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _Cartao('${r.ativos.length}', 'Lotes ativos', Icons.workspaces_outline),
                  _Cartao('${r.inativos.length}', 'Lotes inativos', Icons.workspaces_outline),
                  _Cartao('${r.semLote}', 'Animais sem lote', Icons.pets),
                ],
              ),
            ),
            const Secao('Lotes ativos'),
            if (r.ativos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Não existem lotes ativos')),
              ),
            for (final l in r.ativos) _LoteTile(l),
            const Secao('Lotes inativos'),
            if (r.inativos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Não existem lotes inativos')),
              ),
            for (final l in r.inativos) _LoteTile(l),
          ],
        ),
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao(this.valor, this.rotulo, this.icone);
  final String valor, rotulo;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 132,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cs.primary),
          const Spacer(),
          Text(valor, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          Text(rotulo.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

String periodo(Reg l) {
  final ini = l['data_inicial'] == null ? '' : br(l['data_inicial']);
  final fim = l['data_final'] == null ? 'em aberto' : br(l['data_final']);
  return ini.isEmpty ? 'Até $fim' : '$ini à $fim';
}

class _LoteTile extends StatelessWidget {
  const _LoteTile(this.l);
  final Reg l;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.workspaces_outline, color: Theme.of(context).colorScheme.primary),
      title: Text(txt(l['nome']).toUpperCase()),
      subtitle: Text('${periodo(l)} · ${l['qtd']} animal(is)'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => LoteDetalhePage(l['id'] as int))),
    );
  }
}

class LoteFormPage extends StatefulWidget {
  const LoteFormPage({super.key, this.lote});
  final Reg? lote;

  @override
  State<LoteFormPage> createState() => _LoteFormPageState();
}

class _LoteFormPageState extends State<LoteFormPage> {
  late final l = widget.lote;
  late final nome = TextEditingController(text: txt(l?['nome']));
  late final obs = TextEditingController(text: txt(l?['obs']));
  late String? inicio = (l?['data_inicial'] as String?) ?? hojeIso();
  late String? fim = l?['data_final'] as String?;
  List<Reg> animais = [];
  bool animaisAlterados = false;

  @override
  void initState() {
    super.initState();
    if (l != null) {
      Db.animais(loteId: l!['id'] as int, soAtivos: true).then((v) {
        if (mounted) setState(() => animais = v);
      });
    }
  }

  @override
  void dispose() {
    nome.dispose();
    obs.dispose();
    super.dispose();
  }

  Future<void> _escolher() async {
    final r = await pickAnimais(context,
        titulo: 'Animais do lote', iniciais: [for (final a in animais) a['id'] as int]);
    if (r != null) {
      setState(() {
        animais = r;
        animaisAlterados = true;
      });
    }
  }

  Future<void> salvar() async {
    if (nome.text.trim().isEmpty) {
      avisar(context, 'Informe o nome do lote.');
      return;
    }
    if (inicio == null) {
      avisar(context, 'Informe a data inicial.');
      return;
    }
    if (fim != null && fim!.compareTo(inicio!) < 0) {
      avisar(context, 'A data final é anterior à inicial.');
      return;
    }
    await Db.salvarLote(
      {'nome': nome.text.trim(), 'data_inicial': inicio, 'data_final': fim, 'obs': nulo(obs.text)},
      id: l?['id'] as int?,
      animais: (l == null || animaisAlterados) ? [for (final a in animais) a['id'] as int] : null,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(l == null ? 'ADICIONAR LOTE' : 'EDITAR LOTE')),
      bottomNavigationBar: BotaoSalvar(onPressed: salvar),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nome,
            autofocus: l == null,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Nome do lote *', prefixIcon: Icon(Icons.workspaces_outline)),
          ),
          gap,
          DateField(label: 'Período (data inicial)', value: inicio, obrigatorio: true,
              onChanged: (v) => setState(() => inicio = v)),
          gap,
          DateField(label: 'Período (data final)', value: fim, onChanged: (v) => setState(() => fim = v)),
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 12),
            child: Text('Deixe a data final em branco para um lote sem prazo. Lotes vencidos ficam inativos.'),
          ),
          gap,
          OutlinedButton.icon(
            icon: const Icon(Icons.format_list_numbered),
            label: Text(animais.isEmpty ? 'Escolher animais do lote' : '${animais.length} animal(is) – alterar'),
            onPressed: _escolher,
          ),
          if (animais.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in animais) Chip(label: Text(txt(a['brinco']))),
              ]),
            ),
          gap,
          campoTexto(obs, 'Anotações', linhas: 3),
        ],
      ),
    );
  }
}

class LoteDetalhePage extends StatelessWidget {
  const LoteDetalhePage(this.id, {super.key});
  final int id;

  @override
  Widget build(BuildContext context) {
    return AoMudar<(Reg?, List<Reg>)>(
      carregar: () async => (
        await Db.lote(id),
        await Db.animais(loteId: id),
      ),
      builder: (context, d) {
        final l = d.$1;
        if (l == null) return Scaffold(appBar: AppBar(), body: const Vazio('Lote não encontrado.'));
        final animais = d.$2;
        final ativos = animais.where((a) => a['status'] == 'Ativo').toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(txt(l['nome']).toUpperCase()),
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoteFormPage(lote: l))),
              ),
              IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirmar(context, 'Excluir lote?',
                      'Os animais continuam cadastrados, apenas ficam sem lote.', ok: 'Excluir')) {
                    return;
                  }
                  await Db.excluir('lotes', id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Animais'),
            onPressed: () async {
              final r = await pickAnimais(context,
                  titulo: 'Animais do lote', iniciais: [for (final a in ativos) a['id'] as int]);
              if (r == null) return;
              await Db.salvarLote({}, id: id, animais: [for (final a in r) a['id'] as int]);
            },
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Info('Situação', Db.loteAtivo(l) ? 'Ativo' : 'Inativo'),
                    Info('Período', periodo(l)),
                    Info('Animais ativos', '${ativos.length}'),
                    Info('Anotações', txt(l['obs'])),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.upgrade),
                    label: const Text('Migrar categoria'),
                    onPressed: ativos.isEmpty
                        ? null
                        : () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => MigrarLotePage(lote: l))),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Mover animais'),
                    onPressed: ativos.isEmpty
                        ? null
                        : () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => MoverAnimaisPage(animais: ativos))),
                  ),
                ]),
              ),
              Secao('Animais (${animais.length})'),
              if (animais.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nenhum animal neste lote.'))),
              for (final a in animais) AnimalTile(a),
            ],
          ),
        );
      },
    );
  }
}
