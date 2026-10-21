// Cotação de Medicamentos e Cotação de Insumos: escolhe os itens e os
// fornecedores, manda o link pelo WhatsApp e compara os preços que voltam.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/contatos.dart' show fornecedoresDe;
import '../dados/cotacao_compra.dart';
import '../dados/db.dart';
import '../dados/estoque.dart'
    show categoriaInsumo, categoriasGeral, categoriasMedicamento, movimentos, saldo, unidadeInsumo;
import '../dados/proteinado.dart' show insumos;
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';
import 'contatos.dart' show ContatoFormPage;
import 'estoque.dart' show InsumoFormPage;

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

/// Cores de cada cotação: medicamentos em verde-água, insumos em laranja.
(Color, Color) coresCotacao(String tipo) =>
    tipo == tipoMedicamentos ? (const Color(0xFF00897B), const Color(0xFF26C6DA)) : (const Color(0xFFEF6C00), const Color(0xFFFFB300));

const _corAguardando = Color(0xFFF9A825);
const _corParcial = Color(0xFF1E88E5);
const _corCompleta = Color(0xFF2E7D32);
const _corNova = Color(0xFFD81B60);

/// Situação da cotação (texto e cor).
(String, Color) _situacao(GrupoCotacao g) {
  if (g.respondidas.any((p) => !p.visto)) return ('Resposta nova', _corNova);
  if (g.respondidas.isEmpty) return ('Aguardando', _corAguardando);
  if (g.respondidas.length < g.pedidos.length) return ('Parcial', _corParcial);
  return ('Todos responderam', _corCompleta);
}

/// Lista das cotações enviadas e o botão de nova cotação.
class CotacoesCompraPage extends StatelessWidget {
  const CotacoesCompraPage({super.key, required this.tipo});
  final String tipo;

  @override
  Widget build(BuildContext context) {
    final (cor, cor2) = coresCotacao(tipo);
    return Pagina(
      titulo: 'Cotação de $tipo',
      acoes: [
        IconButton(
          tooltip: 'Cadastro de $tipo',
          icon: const Icon(Icons.playlist_add_check),
          onPressed: () => Nav.ir(tipo == tipoMedicamentos ? secCadastroMedicamentos : secCadastroInsumos),
        ),
        IconButton(
          tooltip: 'Fornecedores de $tipo',
          icon: const Icon(Icons.local_shipping_outlined),
          onPressed: () => Nav.ir(tipo == tipoMedicamentos ? secFornecedoresMedicamentos : secFornecedoresInsumos),
        ),
      ],
      fab: FloatingActionButton.extended(
        heroTag: null,
        backgroundColor: cor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nova cotação'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NovaCotacaoPage(tipo: tipo))),
      ),
      corpo: ValueListenableBuilder<List<PedidoCotacao>>(
        valueListenable: CotacoesCompra.pedidos,
        builder: (context, lista, _) {
          final grupos = CotacoesCompra.grupos(tipo, lista);
          final respondidas = grupos.fold<int>(0, (s, g) => s + g.respondidas.length);
          final enviadas = grupos.fold<int>(0, (s, g) => s + g.pedidos.length);
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cor, cor2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(tipo == tipoMedicamentos ? Icons.medication_outlined : Icons.inventory_2_outlined, color: cor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Cotação de $tipo',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  _Numero('${grupos.length}', 'Cotações', Colors.white),
                  _Numero('$respondidas', 'Respostas', const Color(0xFFC8F7C5)),
                  _Numero('${enviadas - respondidas}', 'Aguardando', const Color(0xFFFFF59D)),
                ]),
              ]),
            ),
            if (grupos.isEmpty) ...[
              for (final (i, (texto, icone, c)) in <(String, IconData, Color)>[
                ('Escolha os ${tipo.toLowerCase()} e as quantidades', Icons.checklist, cor),
                ('Marque os fornecedores', Icons.local_shipping_outlined, _corParcial),
                ('Envie o link pelo WhatsApp', Icons.chat, const Color(0xFF25D366)),
                ('Compare os preços que chegarem', Icons.emoji_events_outlined, _corAguardando),
              ].indexed)
                ListTile(
                  leading: CircleAvatar(backgroundColor: c, child: Icon(icone, color: Colors.white)),
                  title: Text('${i + 1}. $texto'),
                ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Cada fornecedor preenche os preços no celular, sem entrar no app.'),
              ),
            ],
            for (final g in grupos)
              Builder(builder: (context) {
                final (sit, corSit) = _situacao(g);
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: InkWell(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => GrupoCotacaoPage(tipo: tipo, grupo: g.primeiro.grupo))),
                    child: IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Container(width: 8, color: corSit),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Text(g.titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: corSit, borderRadius: BorderRadius.circular(20)),
                                  child: Text(sit,
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                ),
                              ]),
                              const SizedBox(height: 4),
                              Text([
                                _quando(g.primeiro.criadoEm),
                                '${g.itens.length} ${g.itens.length == 1 ? 'item' : 'itens'}',
                                '${g.respondidas.length} de ${g.pedidos.length} responderam',
                              ].where((t) => t.isNotEmpty).join(' · ')),
                              if (g.melhor != null) ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  const Icon(Icons.emoji_events, color: _corAguardando, size: 20),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text('${g.melhor!.fornecedor} · ${moeda(g.melhor!.total)}',
                                        style: const TextStyle(color: _corCompleta, fontWeight: FontWeight.w800)),
                                  ),
                                ]),
                              ],
                            ]),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: cor),
                        const SizedBox(width: 4),
                      ]),
                    ),
                  ),
                );
              }),
          ]);
        },
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero(this.valor, this.rotulo, this.cor);
  final String valor, rotulo;
  final Color cor;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valor, style: TextStyle(color: cor, fontSize: 26, fontWeight: FontWeight.w900)),
          Text(rotulo, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ]),
      );
}

/// Monta a cotação: itens, quantidades e fornecedores.
class NovaCotacaoPage extends StatefulWidget {
  const NovaCotacaoPage({super.key, required this.tipo, this.itensIniciais = const {}, this.fornecedoresIniciais = const {}, this.qtdIniciais = const {}});
  final String tipo;

  /// Quantidade já digitada para cada produto (id do insumo).
  final Map<int, String> qtdIniciais;

  /// Produtos (ids de insumos) e fornecedores (ids de contatos) que já vêm marcados.
  final Set<int> itensIniciais, fornecedoresIniciais;

  @override
  State<NovaCotacaoPage> createState() => _NovaCotacaoPageState();
}

class _Linha {
  _Linha(this.nome, this.unidade, {this.insumoId, this.fornecedorId})
      : estoque = insumoId != null && movimentos(insumoId).isNotEmpty ? saldo(insumoId) : null;
  final String nome, unidade;
  final int? insumoId, fornecedorId;

  /// Saldo do estoque (null = sem movimento de estoque).
  final double? estoque;
  final qtd = TextEditingController();
  bool marcado = false;
}

class _NovaCotacaoPageState extends State<NovaCotacaoPage> {
  late final titulo = TextEditingController(text: 'Cotação de ${widget.tipo} ${br(hojeIso())}');
  final obs = TextEditingController();
  late final linhas = [
    for (final i in itensDoTipo(widget.tipo))
      _Linha(txt(i['nome']), unidadeInsumo(i), insumoId: i['id'] as int, fornecedorId: i['fornecedor_id'] as int?)
        ..marcado = widget.itensIniciais.contains(i['id'])
        ..qtd.text = widget.qtdIniciais[i['id']] ?? '',
  ];
  late final escolhidos = {...widget.fornecedoresIniciais};

  /// Abre o cadastro de produto e põe na lista o que foi cadastrado.
  Future<void> _novoProduto() async {
    final cats = widget.tipo == tipoMedicamentos ? categoriasMedicamento : categoriasGeral;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => InsumoFormPage(categorias: cats)));
    if (!mounted) return;
    final ja = {for (final l in linhas) l.insumoId};
    setState(() {
      for (final i in itensDoTipo(widget.tipo)) {
        if (!ja.contains(i['id'])) {
          linhas.add(_Linha(txt(i['nome']), unidadeInsumo(i), insumoId: i['id'] as int, fornecedorId: i['fornecedor_id'] as int?)
            ..marcado = true);
        }
      }
    });
  }
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

  /// Cotações já criadas: a tela passa a mostrar os botões de envio.
  List<PedidoCotacao>? _criados;

  Future<void> _criar() async {
    final forn = [for (final f in fornecedoresDe(widget.tipo)) if (escolhidos.contains(f['id'])) f];
    if (forn.isEmpty) return avisar(context, 'Escolha pelo menos um fornecedor.');
    final itens = [
      for (final l in linhas)
        if (l.marcado)
          ItemCotacao(nome: l.nome, unidade: l.unidade, qtd: lerNumero(l.qtd.text) ?? 1, insumoId: l.insumoId, estoque: l.estoque),
    ];
    if (itens.isEmpty) return avisar(context, 'Marque pelo menos um item.');
    setState(() => _enviando = true);
    final pedidos = await CotacoesCompra.criar(
      tipo: widget.tipo,
      titulo: nulo(titulo.text) ?? 'Cotação de ${widget.tipo}',
      itens: itens,
      fornecedores: forn,
      obs: nulo(obs.text),
    );
    if (!mounted) return;
    // Um fornecedor só: abre o WhatsApp direto.
    if (pedidos.length == 1) {
      _abrirWhats(pedidos.first);
      Navigator.pop(context);
      return;
    }
    setState(() => _criados = pedidos);
  }

  /// Marca o fornecedor e os itens cadastrados com ele.
  void _escolherFornecedor(int id, bool sim) => setState(() {
        sim ? escolhidos.add(id) : escolhidos.remove(id);
        if (sim) {
          for (final l in linhas) {
            if (l.fornecedorId == id) l.marcado = true;
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    final fornecedores = fornecedoresDe(widget.tipo);
    final criados = _criados;
    return Scaffold(
      appBar: AppBar(
        title: Text('Nova cotação de ${widget.tipo.toLowerCase()}'),
        backgroundColor: coresCotacao(widget.tipo).$1,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: criados != null
          ? BotaoSalvar(onPressed: () => Navigator.pop(context), texto: 'Concluir')
          : BotaoSalvar(onPressed: _enviando ? null : _criar, texto: 'Enviar pelo WhatsApp'),
      body: criados != null
          ? ListView(padding: const EdgeInsets.all(16), children: [
              Text('3. Enviar a cotação', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('Toque em cada fornecedor para abrir o WhatsApp com a mensagem e o link. '
                  'Quando ele responder, aparece o aviso "Cotação Recebida".'),
              gap,
              for (final p in criados) _CartaoEnvio(p),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
              campoTexto(titulo, 'Nome da cotação'),
              Secao('1. Fornecedores',
                  acao: TextButton.icon(
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Novo'),
                    onPressed: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => ContatoFormPage(tipo: 'Fornecedor', fornece: widget.tipo)));
                      if (mounted) setState(() {});
                    },
                  )),
              if (fornecedores.isEmpty)
                const Text('Nenhum fornecedor. Toque em "Novo" e cadastre com o WhatsApp.'),
              for (final f in fornecedores)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: escolhidos.contains(f['id']),
                  onChanged: (v) => _escolherFornecedor(f['id'] as int, v == true),
                  title: Text(txt(f['nome'])),
                  subtitle: Text(txt(f['telefone']).isEmpty ? 'Sem WhatsApp no cadastro' : txt(f['telefone']),
                      style: TextStyle(color: txt(f['telefone']).isEmpty ? Cores.alerta : null)),
                ),
              Secao('2. ${widget.tipo} e quantidades',
                  acao: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton.icon(
                        icon: const Icon(Icons.playlist_add), label: const Text('Cadastrar'), onPressed: _novoProduto),
                    TextButton.icon(icon: const Icon(Icons.add), label: const Text('Avulso'), onPressed: _avulso),
                  ])),
              if (linhas.isEmpty)
                Text('Nenhum item no cadastro de ${widget.tipo.toLowerCase()}. Use "Cadastrar" ou "Avulso".'),
              for (final l in linhas)
                Row(children: [
                  Checkbox(value: l.marcado, onChanged: (v) => setState(() => l.marcado = v ?? false)),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => l.marcado = !l.marcado),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.nome),
                        if (l.estoque != null)
                          Text(
                            l.estoque! <= 0 ? 'Estoque: zerado' : 'Estoque: ${_q(l.estoque!)} ${l.unidade}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: l.estoque! <= 0 ? Cores.alerta : Cores.sucesso),
                          ),
                      ]),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: l.qtd,
                      onChanged: (t) {
                        if (t.trim().isNotEmpty && !l.marcado) setState(() => l.marcado = true);
                      },
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(isDense: true, labelText: 'Qtd.', suffixText: l.unidade),
                    ),
                  ),
                ]),
              gap,
              campoTexto(obs, 'Recado para os fornecedores (prazo, entrega...)', linhas: 2),
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

  /// Manda o mesmo pedido a fornecedores que ficaram de fora da primeira rodada.
  Future<void> _reenviar(GrupoCotacao g) async {
    final ja = {for (final p in g.pedidos) p.contatoId};
    final escolhidos = await showModalBottomSheet<List<Reg>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EscolherOutrosFornecedores(tipo: widget.tipo, jaEnviados: ja),
    );
    if (escolhidos == null || escolhidos.isEmpty || !mounted) return;
    final pedidos = await CotacoesCompra.criar(
      tipo: widget.tipo,
      titulo: g.titulo,
      itens: g.itens,
      fornecedores: escolhidos,
      obs: nulo(g.primeiro.pedidoObs),
      grupoExistente: g.primeiro.grupo,
    );
    if (!mounted) return;
    if (pedidos.length == 1) {
      _abrirWhats(pedidos.first);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar a cotação'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [for (final p in pedidos) _CartaoEnvio(p)]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Concluir'))],
      ),
    );
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
          floatingActionButton: g == null
              ? null
              : FloatingActionButton.extended(
                  heroTag: null,
                  backgroundColor: coresCotacao(widget.tipo).$1,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Enviar a outro fornecedor'),
                  onPressed: () => _reenviar(g),
                ),
        );
      },
    );
  }

  Widget _corpo(GrupoCotacao g) {
    final melhor = g.melhor, resp = g.respondidas;
    return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
      if (melhor != null)
        Card(
          color: coresCotacao(widget.tipo).$1,
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
        const Secao('Preço por item'),
        for (final (i, it) in g.itens.indexed) _CartaoItem(g: g, i: i, it: it, resp: resp, cor: coresCotacao(widget.tipo).$1),
        const Secao('Preço final por fornecedor'),
        for (final p in resp) _CartaoTotais(p: p, melhor: identical(p, melhor), cor: coresCotacao(widget.tipo).$1),
      ],
      const Secao('Fornecedores'),
      for (final p in g.pedidos)
        ListTile(
          leading: CircleAvatar(
            backgroundColor: p.respondida ? _corCompleta : _corAguardando,
            child: Icon(p.respondida ? Icons.mark_email_read_outlined : Icons.hourglass_empty, color: Colors.white),
          ),
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


/// Rótulos dos três preços que o fornecedor informa (À vista, 30/60/90, 90 direto).
const _modos = ['À vista', '30/60/90 dias', '90 dias direto'];

/// Caixinha com um preço; verde quando é o menor entre os fornecedores.
class _PrecoCaixa extends StatelessWidget {
  const _PrecoCaixa(this.rotulo, this.valor, {this.menor = false});
  final String rotulo;
  final double? valor;
  final bool menor;

  @override
  Widget build(BuildContext context) {
    final cor = valor == null ? Colors.grey : (menor ? Cores.sucesso : null);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: menor ? Cores.sucesso.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.10),
        border: Border.all(color: menor ? Cores.sucesso : Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(rotulo, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(valor == null ? '—' : moeda(valor),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cor)),
      ]),
    );
  }
}

/// Um item da cotação com o preço de cada fornecedor nos três prazos.
class _CartaoItem extends StatelessWidget {
  const _CartaoItem({required this.g, required this.i, required this.it, required this.resp, required this.cor});
  final GrupoCotacao g;
  final int i;
  final ItemCotacao it;
  final List<PedidoCotacao> resp;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    List<double?> precos(PedidoCotacao p, int m) => switch (m) { 0 => p.precos, 1 => p.precos30, _ => p.precos90 };
    double? menor(int m) => resp
        .map((p) => precos(p, m)[i])
        .whereType<double>()
        .fold<double?>(null, (a, v) => a == null || v < a ? v : a);
    final menores = [for (var m = 0; m < 3; m++) menor(m)];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(it.nome, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: cor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Text('${_q(it.qtd)} ${it.unidade}', style: TextStyle(fontWeight: FontWeight.w700, color: cor)),
            ),
          ]),
          if (it.estoque != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(it.estoque! <= 0 ? 'Estoque: zerado' : 'Estoque: ${_q(it.estoque!)} ${it.unidade}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: it.estoque! <= 0 ? Cores.alerta : Cores.sucesso)),
            ),
          for (final p in resp) ...[
            const Divider(height: 18),
            Text(p.fornecedor, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (p.precos[i] == null && p.precos30[i] == null && p.precos90[i] == null)
              const Text('não tem', style: TextStyle(color: Colors.grey))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var m = 0; m < 3; m++)
                  _PrecoCaixa(_modos[m], precos(p, m)[i],
                      menor: precos(p, m)[i] != null && precos(p, m)[i] == menores[m] && resp.length > 1),
              ]),
          ],
        ]),
      ),
    );
  }
}

/// Total de um fornecedor nos três prazos, com o frete.
class _CartaoTotais extends StatelessWidget {
  const _CartaoTotais({required this.p, required this.melhor, required this.cor});
  final PedidoCotacao p;
  final bool melhor;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: melhor ? Cores.sucesso : Colors.transparent, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (melhor) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.emoji_events_outlined, color: Cores.laranja)),
            Expanded(child: Text(p.fornecedor, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Text('${p.cotados} de ${p.itens.length} itens', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var m = 0; m < 3; m++)
              _PrecoCaixa('Final ${_modos[m].toLowerCase()}', p.cotadosModo(m) > 0 ? p.totalModo(m) : null,
                  menor: m == 0 && melhor),
          ]),
          if (p.frete > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Frete incluso: ${moeda(p.frete)}', style: const TextStyle(fontSize: 12))),
        ]),
      ),
    );
  }
}


/// Lista os fornecedores do cadastro que ainda não receberam esta cotação.
class _EscolherOutrosFornecedores extends StatefulWidget {
  const _EscolherOutrosFornecedores({required this.tipo, required this.jaEnviados});
  final String tipo;
  final Set<int?> jaEnviados;

  @override
  State<_EscolherOutrosFornecedores> createState() => _EscolherOutrosFornecedoresState();
}

class _EscolherOutrosFornecedoresState extends State<_EscolherOutrosFornecedores> {
  final _marcados = <int>{};

  List<Reg> get _faltam => [
        for (final f in fornecedoresDe(widget.tipo))
          if (!widget.jaEnviados.contains(f['id'])) f,
      ];

  @override
  Widget build(BuildContext context) {
    final faltam = _faltam;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Enviar a outro fornecedor', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 4),
          const Text('Fornecedores que não receberam esta cotação. Os mesmos itens e quantidades serão enviados.'),
          const SizedBox(height: 8),
          if (faltam.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Todos os fornecedores cadastrados já receberam. Cadastre outro para enviar.')),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final f in faltam)
                CheckboxListTile(
                  value: _marcados.contains(f['id']),
                  title: Text(txt(f['nome'])),
                  subtitle: txt(f['telefone']).isEmpty ? const Text('sem telefone') : Text(txt(f['telefone'])),
                  onChanged: (v) => setState(() => v == true ? _marcados.add(f['id'] as int) : _marcados.remove(f['id'])),
                ),
            ]),
          ),
          Row(children: [
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Novo fornecedor'),
              onPressed: () async {
                await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => ContatoFormPage(tipo: 'Fornecedor', fornece: widget.tipo)));
                if (mounted) setState(() {});
              },
            ),
            const Spacer(),
            FilledButton.icon(
              icon: const Icon(Icons.chat),
              label: Text('Enviar${_marcados.isEmpty ? '' : ' (${_marcados.length})'}'),
              onPressed: _marcados.isEmpty
                  ? null
                  : () => Navigator.pop(context, [for (final f in faltam) if (_marcados.contains(f['id'])) f]),
            ),
          ]),
        ]),
      ),
    );
  }
}


/// Ícone de cotações ao lado do sininho: com o número de respostas novas quando há,
/// e sempre à mão para abrir as cotações.
class AlertaCotacaoRespondida extends StatelessWidget {
  const AlertaCotacaoRespondida({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<PedidoCotacao>>(
        valueListenable: CotacoesCompra.recebidas,
        builder: (context, lista, _) {
          final daqui = [for (final p in lista) if (txt(p.dados['propriedade_id']) == '${Db.pid}') p];
          final p = daqui.firstOrNull;
          return IconButton(
            tooltip: p == null
                ? 'Cotações'
                : daqui.length == 1
                    ? 'Cotação respondida: ${p.fornecedor}'
                    : '${daqui.length} cotações respondidas',
            icon: Badge(
              isLabelVisible: daqui.isNotEmpty,
              label: Text('${daqui.length}'),
              backgroundColor: Cores.sucesso,
              child: Icon(daqui.isEmpty ? Icons.request_quote_outlined : Icons.request_quote,
                  color: daqui.isEmpty ? null : Cores.laranja),
            ),
            onPressed: () => daqui.length == 1
                ? Navigator.push(
                    context, MaterialPageRoute(builder: (_) => GrupoCotacaoPage(tipo: p!.tipo, grupo: p.grupo)))
                : Nav.ir(p?.tipo == tipoInsumos ? secCotacaoInsumos : secCotacaoMedicamentos),
          );
        },
      );
}

/// Cartão do Painel, numa linha: quantas cotações foram respondidas nos últimos 14 dias.
class CartaoCotacoesRespondidas extends StatelessWidget {
  const CartaoCotacoesRespondidas({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<PedidoCotacao>>(
        valueListenable: CotacoesCompra.pedidos,
        builder: (context, lista, _) {
          final corte = DateTime.now().subtract(const Duration(days: 14));
          final grupos = [
            for (final t in [tipoMedicamentos, tipoInsumos])
              for (final g in CotacoesCompra.grupos(t, lista))
                if (g.respondidas.any((p) => (p.respondidoEm ?? corte).isAfter(corte) || !p.visto)) g,
          ]..sort((a, b) => _ultima(b).compareTo(_ultima(a)));
          if (grupos.isEmpty) return const SizedBox.shrink();
          final n = grupos.length;
          final novas = grupos.any((g) => g.respondidas.any((p) => !p.visto));
          return Card(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Cores.sucesso, width: 1.5)),
            child: ListTile(
              leading: const Icon(Icons.request_quote, color: Cores.laranja),
              title: const Text('Existem cotações respondidas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              subtitle: Text('${n.toString().padLeft(2, '0')} ${n == 1 ? 'cotação respondida' : 'cotações respondidas'}'),
              trailing: novas
                  ? const Chip(
                      label: Text('NOVA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      backgroundColor: Cores.sucesso,
                      visualDensity: VisualDensity.compact)
                  : const Icon(Icons.chevron_right),
              onTap: () => n == 1 ? _abrir(context, grupos.first) : _lista(context, grupos),
            ),
          );
        },
      );

  static void _abrir(BuildContext context, GrupoCotacao g) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => GrupoCotacaoPage(tipo: g.tipo, grupo: g.primeiro.grupo)));

  /// Lista das cotações respondidas (abre ao tocar no cartão quando há mais de uma).
  static Future<void> _lista(BuildContext context, List<GrupoCotacao> grupos) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            const ListTile(title: Text('Cotações respondidas', style: TextStyle(fontWeight: FontWeight.w800))),
            for (final g in grupos)
              ListTile(
                title: Text(g.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${g.respondidas.length} de ${g.pedidos.length} fornecedores responderam'
                    '${g.melhor == null ? '' : ' · melhor: ${g.melhor!.fornecedor} ${moeda(g.melhor!.total)}'}'),
                trailing: g.respondidas.any((p) => !p.visto)
                    ? const Chip(
                        label: Text('NOVA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        backgroundColor: Cores.sucesso,
                        visualDensity: VisualDensity.compact)
                    : const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _abrir(context, g);
                },
              ),
          ]),
        ),
      );

  static DateTime _ultima(GrupoCotacao g) =>
      g.respondidas.map((p) => p.respondidoEm ?? DateTime(2000)).reduce((a, b) => a.isAfter(b) ? a : b);
}
