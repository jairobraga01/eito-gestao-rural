// Cotação de Medicamentos e Cotação de Insumos: escolhe os itens e os
// fornecedores, manda o link pelo WhatsApp e compara os preços que voltam.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/contatos.dart' show fornecedoresDe;
import '../dados/cotacao_compra.dart';
import '../dados/db.dart';
import '../dados/estoque.dart' show categoriaInsumo, categoriasGeral, categoriasMedicamento, unidadeInsumo;
import '../dados/proteinado.dart' show insumos;
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';
import 'contatos.dart' show ContatoFormPage;

String _q(double v) => numeroBr(v, casas: v % 1 == 0 ? 0 : 2);

String _quando(DateTime? d) => d == null ? '' : dataHoraBr(d);

/// Medicamentos ou insumos que entram na cotação ([tipo] de [tipoMedicamentos]/[tipoInsumos]).
List<Reg> itensDoTipo(String tipo) {
  final cats = tipo == tipoMedicamentos ? categoriasMedicamento : categoriasGeral;
  return [
    for (final i in insumos())
      if (cats.contains(categoriaInsumo(i)) && i['pronta_formula_id'] == null) i,
  ];
}

void _abrirWhats(PedidoCotacao p) => launchUrl(linkWhatsCotacao(p), mode: LaunchMode.externalApplication);

/// Lista das cotações enviadas e o botão de nova cotação.
class CotacoesCompraPage extends StatelessWidget {
  const CotacoesCompraPage({super.key, required this.tipo});
  final String tipo;

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Cotação de $tipo',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Nova cotação'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NovaCotacaoPage(tipo: tipo))),
      ),
      corpo: ValueListenableBuilder<List<PedidoCotacao>>(
        valueListenable: CotacoesCompra.pedidos,
        builder: (context, lista, _) {
          final grupos = CotacoesCompra.grupos(tipo, lista);
          if (grupos.isEmpty) {
            return Vazio(
                'Nenhuma cotação ainda.\nEscolha os ${tipo.toLowerCase()} e os fornecedores e mande o link pelo WhatsApp. '
                'Cada fornecedor preenche os preços no celular, sem entrar no app, e você compara tudo aqui.',
                icone: Icons.request_quote_outlined);
          }
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            for (final g in grupos)
              Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ListTile(
                  leading: Icon(Icons.request_quote_outlined,
                      color: g.respondidas.any((p) => !p.visto) ? Cores.alerta : Cores.oliva),
                  title: Text(g.titulo),
                  subtitle: Text([
                    _quando(g.primeiro.criadoEm),
                    '${g.itens.length} ${g.itens.length == 1 ? 'item' : 'itens'}',
                    '${g.respondidas.length} de ${g.pedidos.length} responderam',
                    if (g.melhor != null) 'melhor: ${g.melhor!.fornecedor} ${moeda(g.melhor!.total)}',
                  ].where((t) => t.isNotEmpty).join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => GrupoCotacaoPage(tipo: tipo, grupo: g.primeiro.grupo))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// Monta a cotação: itens, quantidades e fornecedores.
class NovaCotacaoPage extends StatefulWidget {
  const NovaCotacaoPage({super.key, required this.tipo});
  final String tipo;

  @override
  State<NovaCotacaoPage> createState() => _NovaCotacaoPageState();
}

class _Linha {
  _Linha(this.nome, this.unidade, {this.insumoId, this.fornecedorId});
  final String nome, unidade;
  final int? insumoId, fornecedorId;
  final qtd = TextEditingController();
  bool marcado = false;
}

class _NovaCotacaoPageState extends State<NovaCotacaoPage> {
  late final titulo = TextEditingController(text: 'Cotação de ${widget.tipo} ${br(hojeIso())}');
  final obs = TextEditingController();
  late final linhas = [
    for (final i in itensDoTipo(widget.tipo))
      _Linha(txt(i['nome']), unidadeInsumo(i), insumoId: i['id'] as int, fornecedorId: i['fornecedor_id'] as int?),
  ];
  final escolhidos = <int>{};
  bool _enviando = false;

  @override
  void dispose() {
    titulo.dispose();
    obs.dispose();
    for (final l in linhas) {
      l.qtd.dispose();
    }
    super.dispose();
  }

  Future<void> _avulso() async {
    final nome = TextEditingController(), un = TextEditingController(text: 'un');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Item fora do cadastro'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          campoTexto(nome, 'Nome do produto', foco: true),
          gap,
          campoTexto(un, 'Unidade (frasco, dose, kg, saco...)'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Incluir')),
        ],
      ),
    );
    final n = nulo(nome.text), u = nulo(un.text) ?? 'un';
    nome.dispose();
    un.dispose();
    if (ok == true && n != null) setState(() => linhas.add(_Linha(n, u)..marcado = true));
  }

  Future<void> _criar() async {
    final itens = [
      for (final l in linhas)
        if (l.marcado)
          ItemCotacao(nome: l.nome, unidade: l.unidade, qtd: lerNumero(l.qtd.text) ?? 1, insumoId: l.insumoId),
    ];
    if (itens.isEmpty) return avisar(context, 'Marque pelo menos um item.');
    final forn = [for (final f in fornecedoresDe(widget.tipo)) if (escolhidos.contains(f['id'])) f];
    if (forn.isEmpty) return avisar(context, 'Escolha pelo menos um fornecedor.');
    setState(() => _enviando = true);
    final pedidos = await CotacoesCompra.criar(
      tipo: widget.tipo,
      titulo: nulo(titulo.text) ?? 'Cotação de ${widget.tipo}',
      itens: itens,
      fornecedores: forn,
      obs: nulo(obs.text),
    );
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => EnviarCotacaoPage(pedidos: pedidos)));
  }

  @override
  Widget build(BuildContext context) {
    final fornecedores = fornecedoresDe(widget.tipo);
    // Quem é o fornecedor de algum item marcado já vem escolhido.
    final sugeridos = {for (final l in linhas) if (l.marcado && l.fornecedorId != null) l.fornecedorId!};
    return Scaffold(
      appBar: AppBar(title: Text('Nova cotação de ${widget.tipo.toLowerCase()}')),
      bottomNavigationBar: BotaoSalvar(onPressed: _enviando ? null : _criar, texto: 'Criar e enviar pelo WhatsApp'),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        campoTexto(titulo, 'Nome da cotação'),
        Secao('1. ${widget.tipo} e quantidades',
            acao: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Item avulso'), onPressed: _avulso)),
        if (linhas.isEmpty)
          Text('Nenhum item no cadastro de ${widget.tipo.toLowerCase()}. Use "Item avulso" ou cadastre no estoque.'),
        for (final l in linhas)
          Row(children: [
            Checkbox(value: l.marcado, onChanged: (v) => setState(() => l.marcado = v ?? false)),
            Expanded(child: InkWell(onTap: () => setState(() => l.marcado = !l.marcado), child: Text(l.nome))),
            SizedBox(
              width: 120,
              child: TextField(
                controller: l.qtd,
                enabled: l.marcado,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(isDense: true, labelText: 'Qtd.', suffixText: l.unidade),
              ),
            ),
          ]),
        Secao('2. Fornecedores',
            acao: TextButton.icon(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Novo'),
              onPressed: () async {
                await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const ContatoFormPage(tipo: 'Fornecedor')));
                if (mounted) setState(() {});
              },
            )),
        if (fornecedores.isEmpty)
          const Text('Nenhum fornecedor. Cadastre em Nutrição > Cadastro de Fornecedores, com o WhatsApp.'),
        for (final f in fornecedores)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: escolhidos.contains(f['id']) || (escolhidos.isEmpty && sugeridos.contains(f['id'])),
            onChanged: (v) => setState(() {
              if (escolhidos.isEmpty) escolhidos.addAll(sugeridos);
              v == true ? escolhidos.add(f['id'] as int) : escolhidos.remove(f['id']);
            }),
            title: Text(txt(f['nome'])),
            subtitle: Text(txt(f['telefone']).isEmpty ? 'Sem WhatsApp no cadastro' : txt(f['telefone']),
                style: TextStyle(color: txt(f['telefone']).isEmpty ? Cores.alerta : null)),
          ),
        gap,
        campoTexto(obs, 'Recado para os fornecedores (prazo, entrega...)', linhas: 2),
      ]),
    );
  }
}

/// Depois de criar: um botão de WhatsApp para cada fornecedor.
class EnviarCotacaoPage extends StatelessWidget {
  const EnviarCotacaoPage({super.key, required this.pedidos});
  final List<PedidoCotacao> pedidos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enviar a cotação')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Toque em cada fornecedor para abrir o WhatsApp com a mensagem e o link. '
            'Quando ele responder, aparece o aviso "Cotação Recebida".'),
        gap,
        for (final p in pedidos) _CartaoEnvio(p),
      ]),
    );
  }
}

class _CartaoEnvio extends StatelessWidget {
  const _CartaoEnvio(this.p);
  final PedidoCotacao p;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.fornecedor, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (p.telefone.isNotEmpty) Text(p.telefone),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                icon: const Icon(Icons.chat),
                label: const Text('Enviar pelo WhatsApp'),
                onPressed: () => _abrirWhats(p),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copiar link'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: p.link));
                  if (context.mounted) avisar(context, 'Link copiado.');
                },
              ),
            ]),
          ]),
        ),
      );
}

/// Comparativo: preço de cada item e preço final de cada fornecedor.
class GrupoCotacaoPage extends StatefulWidget {
  const GrupoCotacaoPage({super.key, required this.tipo, required this.grupo});
  final String tipo, grupo;

  @override
  State<GrupoCotacaoPage> createState() => _GrupoCotacaoPageState();
}

class _GrupoCotacaoPageState extends State<GrupoCotacaoPage> {
  GrupoCotacao? _grupo(List<PedidoCotacao> lista) {
    for (final g in CotacoesCompra.grupos(widget.tipo, lista)) {
      if (g.primeiro.grupo == widget.grupo) return g;
    }
    return null;
  }

  void _marcarVistas(GrupoCotacao g) {
    for (final p in g.respondidas) {
      if (!p.visto) CotacoesCompra.marcarVisto(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PedidoCotacao>>(
      valueListenable: CotacoesCompra.pedidos,
      builder: (context, lista, _) {
        final g = _grupo(lista);
        if (g != null) WidgetsBinding.instance.addPostFrameCallback((_) => _marcarVistas(g));
        return Scaffold(
          appBar: AppBar(
            title: Text(g?.titulo ?? 'Cotação'),
            actions: [
              if (g != null)
                IconButton(
                  tooltip: 'Excluir a cotação',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (!await confirmar(context, 'Excluir a cotação?',
                        'Os links enviados param de funcionar e as respostas somem.',
                        ok: 'Excluir')) {
                      return;
                    }
                    await CotacoesCompra.excluirGrupo(g);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          ),
          body: g == null ? const Center(child: Text('Cotação não encontrada.')) : _corpo(g),
        );
      },
    );
  }

  Widget _corpo(GrupoCotacao g) {
    final menores = g.menores, melhor = g.melhor, resp = g.respondidas;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      if (melhor != null)
        Card(
          color: Cores.olivaEscuro,
          margin: const EdgeInsets.all(12),
          child: ListTile(
            leading: const Icon(Icons.emoji_events_outlined, color: Cores.laranja, size: 36),
            title: Text('Melhor preço final: ${melhor.fornecedor}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            subtitle: Text(
                '${moeda(melhor.total)} · ${melhor.cotados} de ${g.itens.length} itens'
                '${melhor.frete > 0 ? ' · frete incluso' : ''}',
                style: const TextStyle(color: Colors.white70)),
          ),
        ),
      if (resp.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nenhum fornecedor respondeu ainda. Quando responder, aparece o aviso "Cotação Recebida".'),
        ),
      if (resp.isNotEmpty) ...[
        const Secao('Preço por item (menor em verde)'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DataTable(
            columnSpacing: 18,
            headingRowColor: WidgetStatePropertyAll(Cores.oliva.withValues(alpha: 0.10)),
            columns: [
              const DataColumn(label: Text('Item')),
              for (final p in resp) DataColumn(label: Text(p.fornecedor), numeric: true),
            ],
            rows: [
              for (final (i, it) in g.itens.indexed)
                DataRow(cells: [
                  DataCell(Text('${it.nome}\n${_q(it.qtd)} ${it.unidade}')),
                  for (final p in resp)
                    DataCell(Text(
                      p.precos[i] == null ? 'não tem' : moeda(p.precos[i]),
                      style: TextStyle(
                        color: p.precos[i] != null && p.precos[i] == menores[i] ? Cores.sucesso : null,
                        fontWeight: p.precos[i] != null && p.precos[i] == menores[i] ? FontWeight.w800 : null,
                      ),
                    )),
                ]),
              DataRow(cells: [
                const DataCell(Text('Frete')),
                for (final p in resp) DataCell(Text(p.frete > 0 ? moeda(p.frete) : '—')),
              ]),
              DataRow(color: WidgetStatePropertyAll(Cores.laranja.withValues(alpha: 0.25)), cells: [
                const DataCell(Text('PREÇO FINAL', style: TextStyle(fontWeight: FontWeight.w800))),
                for (final p in resp)
                  DataCell(Text(moeda(p.total),
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: identical(p, melhor) ? Cores.sucesso : null))),
              ]),
            ],
          ),
        ),
      ],
      const Secao('Fornecedores'),
      for (final p in g.pedidos)
        ListTile(
          leading: Icon(p.respondida ? Icons.mark_email_read_outlined : Icons.hourglass_empty,
              color: p.respondida ? Cores.sucesso : Colors.orange),
          title: Text(p.fornecedor),
          subtitle: Text(p.respondida
              ? [
                  'Respondeu ${_quando(p.respondidoEm)}',
                  if (p.respondidoPor.isNotEmpty) 'por ${p.respondidoPor}',
                  'total ${moeda(p.total)}',
                  if (p.prazo.isNotEmpty) 'entrega: ${p.prazo}',
                  if (p.pagamento.isNotEmpty) 'pagamento: ${p.pagamento}',
                  if (p.obs.isNotEmpty) p.obs,
                ].join(' · ')
              : 'Aguardando resposta'),
          trailing: p.respondida
              ? null
              : IconButton(
                  tooltip: 'Reenviar pelo WhatsApp',
                  icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                  onPressed: () => _abrirWhats(p),
                ),
        ),
    ]);
  }
}

/// Aviso "Cotação Recebida" no topo de todas as telas.
class FaixaCotacaoRecebida extends StatelessWidget {
  const FaixaCotacaoRecebida({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<PedidoCotacao>>(
        valueListenable: CotacoesCompra.recebidas,
        builder: (context, lista, _) {
          final daqui = [for (final p in lista) if (txt(p.dados['propriedade_id']) == '${Db.pid}') p];
          if (daqui.isEmpty) return const SizedBox.shrink();
          final p = daqui.first;
          return Material(
            color: Cores.sucesso,
            child: InkWell(
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => GrupoCotacaoPage(tipo: p.tipo, grupo: p.grupo))),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: Row(children: [
                  const Icon(Icons.mark_email_unread_outlined, color: Cores.laranja),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Cotação Recebida  ', style: TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(
                            text: daqui.length == 1
                                ? '${p.fornecedor} respondeu a cotação de ${p.tipo.toLowerCase()}. Toque para comparar.'
                                : '${daqui.length} respostas novas de fornecedores. Toque para ver.'),
                      ]),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () {
                      for (final x in daqui) {
                        CotacoesCompra.marcarVisto(x);
                      }
                    },
                  ),
                ]),
              ),
            ),
          );
        },
      );
}
