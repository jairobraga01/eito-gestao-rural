import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/estoque.dart';
import '../dados/proteinado.dart' show historicoPrecos, insumos, lancarPrecoInsumo, precoKgInsumo, variacaoPct;
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';
import 'batidas.dart';

String _q(double v) => numeroBr(v, casas: v % 1 == 0 ? 0 : 1);

/// Estoque de insumos (milho, sorgo, sal, ração) ou, com [medicamentos], de vacinas e remédios.
/// Baixa automática (vacinação, batida e trato do cocho) e avisos de falta e validade.
class EstoquePage extends StatelessWidget {
  const EstoquePage({super.key, this.medicamentos = false});
  final bool medicamentos;

  List<String> get categorias => medicamentos ? categoriasMedicamento : categoriasGeral;

  @override
  Widget build(BuildContext context) {
    final hoje = hojeIso();
    return Pagina(
      titulo: medicamentos ? 'Estoque de Medicamentos' : 'Estoque de insumos',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Entrada'),
        onPressed: () => entradaDialog(context, categorias: categorias),
      ),
      acoes: [
        IconButton(
          tooltip: medicamentos ? 'Novo medicamento' : 'Novo insumo',
          icon: const Icon(Icons.playlist_add),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InsumoFormPage(categorias: categorias))),
        ),
      ],
      corpo: AoMudar<(List<Reg>, List<AlertaEstoque>)>(
        carregar: () async => (
          [for (final i in insumos()) if (categorias.contains(categoriaInsumo(i))) i],
          [for (final a in alertasEstoque(hoje)) if (categorias.contains(categoriaInsumo(a.insumo))) a],
        ),
        builder: (context, d) {
          final (ins, alertas) = d;
          if (ins.isEmpty) {
            return Vazio(
                medicamentos
                    ? 'Nenhum medicamento. Cadastre vacinas e remédios pelo botão no alto.'
                    : 'Nenhum insumo. Cadastre milho, sorgo, sal e ração pelo botão no alto.',
                icone: medicamentos ? Icons.medication_outlined : Icons.inventory_2_outlined);
          }
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            if (!medicamentos)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Gerar batida'),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GerarBatidaPage())),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('Histórico de batidas'),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BatidasPage())),
                  ),
                ]),
              ),
            if (alertas.isNotEmpty) ...[
              Secao('Avisos (${alertas.length})'),
              for (final a in alertas)
                ListTile(
                  dense: true,
                  leading: Icon(a.grave ? Icons.error_outline : Icons.warning_amber, color: a.grave ? Cores.alerta : Colors.orange),
                  title: Text(txt(a.insumo['nome'])),
                  subtitle: Text(a.texto),
                  onTap: () => _abrir(context, a.insumo),
                ),
            ],
            for (final cat in categorias)
              if (ins.any((i) => categoriaInsumo(i) == cat)) ...[
                Secao(cat),
                for (final i in ins.where((i) => categoriaInsumo(i) == cat)) _InsumoTile(i, hoje),
              ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(medicamentos
                  ? 'Baixa automática: vacina ou remédio lançado na sanidade com o mesmo nome do cadastro.'
                  : 'Baixa automática: batida e trato da dieta do cocho. Toque no insumo para lançar o preço: '
                      'o custo de cada batida usa o preço mais recente.'),
            ),
          ]);
        },
      ),
    );
  }

  static void _abrir(BuildContext context, Reg i) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => InsumoFormPage(insumo: i)));
}

class _InsumoTile extends StatelessWidget {
  const _InsumoTile(this.i, this.hoje);
  final Reg i;
  final String hoje;

  @override
  Widget build(BuildContext context) {
    final id = i['id'] as int;
    final un = unidadeInsumo(i);
    final usa = movimentos(id).isNotEmpty;
    final s = saldo(id);
    final c = consumoDiario(id, hoje);
    return ListTile(
      title: Text(txt(i['nome'])),
      subtitle: Text([
        if (precoKgInsumo(i) != null) '${moeda(precoKgInsumo(i))}/$un',
        if (c > 0) 'gasta ${_q(c)} $un/dia · dura ${(s / c).floor().clamp(0, 9999)} dias',
        if (txt(i['validade']).isNotEmpty) 'validade ${br(i['validade'])}',
      ].join(' · ')),
      trailing: Text(usa ? '${_q(s)} $un' : 'sem saldo',
          style: TextStyle(fontWeight: FontWeight.bold, color: usa && s <= 0 ? Cores.alerta : null)),
      onTap: () => EstoquePage._abrir(context, i),
    );
  }
}

/// Entrada no estoque (compra), em unidades ou em embalagens.
Future<void> entradaDialog(BuildContext context, {Reg? insumo, List<String>? categorias}) async {
  final ins = [for (final i in insumos()) if (categorias == null || categorias.contains(categoriaInsumo(i))) i];
  if (ins.isEmpty) {
    avisar(context, 'Cadastre o insumo primeiro.');
    return;
  }
  int? id = insumo?['id'] as int?;
  var data = hojeIso();
  String? validade;
  var emEmbalagem = true;
  final qtd = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final i = ins.where((x) => x['id'] == id).firstOrNull;
      final emb = i?['kg_saco'] is num && (i!['kg_saco'] as num) > 0 ? (i['kg_saco'] as num).toDouble() : null;
      final un = i == null ? '' : unidadeInsumo(i);
      return AlertDialog(
        title: const Text('Entrada no estoque'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          escolhaId('Insumo', id, ins, (v) => set(() => id = v), vazio: '—'),
          gap,
          DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => set(() => data = v!)),
          gap,
          campoTexto(qtd, emb != null && emEmbalagem ? 'Embalagens (${_q(emb)} $un cada)' : 'Quantidade ($un)',
              numero: true, foco: true),
          if (emb != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Contar em embalagens'),
              value: emEmbalagem,
              onChanged: (v) => set(() => emEmbalagem = v),
            ),
          gap,
          DateField(label: 'Validade (se tiver)', value: validade, onChanged: (v) => set(() => validade = v)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lançar')),
        ],
      );
    }),
  );
  final n = lerNumero(qtd.text);
  qtd.dispose();
  if (ok != true || id == null || n == null || n <= 0) return;
  final i = ins.firstWhere((x) => x['id'] == id);
  final emb = i['kg_saco'] is num && (i['kg_saco'] as num) > 0 ? (i['kg_saco'] as num).toDouble() : null;
  await entradaEstoque(id!, emb != null && emEmbalagem ? n * emb : n, data: data, validade: validade);
}

/// Cadastro do insumo, histórico do estoque e ajuste pela contagem.
class InsumoFormPage extends StatefulWidget {
  const InsumoFormPage({super.key, this.insumo, this.categorias});
  final Reg? insumo;

  /// Categorias que o cadastro oferece (medicamentos ou insumos em geral).
  final List<String>? categorias;

  @override
  State<InsumoFormPage> createState() => _InsumoFormPageState();
}

class _InsumoFormPageState extends State<InsumoFormPage> {
  Reg? get i => widget.insumo;
  static String _n(Object? v) => v is num ? numeroBr(v.toDouble(), casas: v % 1 == 0 ? 0 : 2) : '';

  late final nome = TextEditingController(text: txt(i?['nome']));
  late final List<String> opcoes = [
    ...(widget.categorias ?? (i != null && categoriasMedicamento.contains(categoriaInsumo(i!)) ? categoriasMedicamento : categoriasGeral)),
    if (i != null && !(widget.categorias ?? categoriasInsumo).contains(categoriaInsumo(i!))) categoriaInsumo(i!),
  ];
  late String categoria = i == null ? opcoes.first : categoriaInsumo(i!);
  late String unidade = i == null ? unidadePadrao(categoria) : unidadeInsumo(i!);
  late final preco = TextEditingController(text: _n(i?['preco_saco']));
  late final embalagem = TextEditingController(text: _n(i?['kg_saco']));
  late final minimo = TextEditingController(text: _n(i?['estoque_min']));
  late final dose = TextEditingController(text: _n(i?['dose_animal']));
  late String? validade = txt(i?['validade']).isEmpty ? null : txt(i!['validade']);

  @override
  void dispose() {
    for (final c in [nome, preco, embalagem, minimo, dose]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    final n = nulo(nome.text);
    if (n == null) return avisar(context, 'Informe o nome.');
    final dados = {
      'nome': n,
      'categoria': categoria,
      'unidade': unidade,
      'preco_saco': lerNumero(preco.text),
      'kg_saco': lerNumero(embalagem.text),
      'estoque_min': lerNumero(minimo.text),
      'dose_animal': lerNumero(dose.text),
      'validade': validade,
    };
    final p = lerNumero(preco.text), emb = lerNumero(embalagem.text);
    final mudouPreco = p != null && emb != null && emb > 0 && (p != (i?['preco_saco'] as num?) || emb != (i?['kg_saco'] as num?));
    final int id;
    if (i == null) {
      id = await Db.inserir('insumos', {...dados, 'propriedade_id': Db.pid});
    } else {
      id = i!['id'] as int;
      await Db.atualizar('insumos', id, dados);
    }
    // Preço novo ou mudado entra no histórico, para acompanhar a evolução.
    if (mudouPreco) await lancarPrecoInsumo(id, data: hojeIso(), precoEmbalagem: p, kgEmbalagem: emb);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    if (!await confirmar(context, 'Excluir o insumo?', 'O histórico do estoque e as dietas com ele somem junto.', ok: 'Excluir')) {
      return;
    }
    await Db.excluir('insumos', i!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _lancarPreco() async {
    var data = hojeIso();
    final p = TextEditingController();
    final e = TextEditingController(text: _n(i?['kg_saco']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Lançar preço'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => set(() => data = v!)),
            gap,
            campoTexto(p, 'Preço da embalagem (R\$)', numero: true, foco: true),
            gap,
            campoTexto(e, 'Embalagem tem', numero: true, sufixo: unidade),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lançar')),
          ],
        ),
      ),
    );
    final vp = lerNumero(p.text), ve = lerNumero(e.text);
    p.dispose();
    e.dispose();
    if (ok != true || vp == null || ve == null || ve <= 0) return;
    await lancarPrecoInsumo(i!['id'] as int, data: data, precoEmbalagem: vp, kgEmbalagem: ve);
    if (!mounted) return;
    setState(() {
      preco.text = _n(vp);
      embalagem.text = _n(ve);
    });
  }

  Future<void> _contagem() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contagem do depósito'),
        content: campoTexto(c, 'Quanto tem agora ($unidade)', numero: true, foco: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Acertar')),
        ],
      ),
    );
    final v = lerNumero(c.text);
    c.dispose();
    if (ok == true && v != null && v >= 0) await ajustarSaldo(i!['id'] as int, v, data: hojeIso());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sanitario = categoria == 'Vacina' || categoria == 'Medicamento e vermífugo';
    return Scaffold(
      appBar: AppBar(
        title: Text(i == null ? 'Novo insumo' : txt(i!['nome'])),
        actions: [if (i != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir)],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        campoTexto(nome, sanitario ? 'Nome (igual ao lançado na sanidade, ex.: Aftosa)' : 'Nome'),
        gap,
        Row(children: [
          Expanded(
            flex: 3,
            child: escolha('Categoria', categoria, opcoes, (v) => setState(() {
                  categoria = v ?? categoria;
                  if (i == null) unidade = unidadePadrao(categoria);
                })),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: escolha('Unidade', unidade, unidadesInsumo, (v) => setState(() => unidade = v ?? unidade))),
        ]),
        gap,
        Row(children: [
          Expanded(
            child: TextField(
              controller: preco,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço da embalagem', prefixText: r'R$ '),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: campoTexto(embalagem, 'Embalagem tem', numero: true, sufixo: unidade)),
        ]),
        gap,
        Row(children: [
          Expanded(child: campoTexto(minimo, 'Estoque mínimo', numero: true, sufixo: unidade)),
          const SizedBox(width: 12),
          Expanded(child: DateField(label: 'Validade', value: validade, onChanged: (v) => setState(() => validade = v))),
        ]),
        if (sanitario) ...[
          gap,
          campoTexto(dose, 'Dose por animal (baixa na vacinação)', numero: true, sufixo: unidade),
        ],
        const SizedBox(height: 16),
        BotaoSalvar(onPressed: _salvar),
        if (i != null) ...[
          Secao('Preços lançados',
              acao: IconButton(tooltip: 'Lançar preço', icon: const Icon(Icons.attach_money), onPressed: _lancarPreco)),
          if (historicoPrecos(i!['id'] as int).isEmpty) const ListTile(dense: true, title: Text('Nenhum preço lançado ainda.')),
          for (final (k, p) in historicoPrecos(i!['id'] as int).indexed)
            Builder(builder: (_) {
              final antes = historicoPrecos(i!['id'] as int).skip(k + 1).firstOrNull;
              final v = variacaoPct((antes?['preco_kg'] as num?)?.toDouble(), (p['preco_kg'] as num?)?.toDouble());
              return ListTile(
                dense: true,
                title: Text('${moeda(p['preco_saco'] as num?)} por ${_q((p['kg_saco'] as num? ?? 0).toDouble())} $unidade'),
                subtitle: Text([
                  br(p['data']),
                  if (p['preco_kg'] != null) '${moeda(p['preco_kg'] as num)}/$unidade',
                  if (v != null) '${v >= 0 ? '+' : ''}${numeroBr(v, casas: 1)}% vs. anterior',
                ].join(' · ')),
                trailing: IconButton(
                  tooltip: 'Apagar',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () async {
                    await Db.excluir('precos_insumo', p['id'] as int);
                    setState(() {});
                  },
                ),
              );
            }),
          Secao('Estoque: ${_q(saldo(i!['id'] as int))} $unidade',
              acao: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Contagem', icon: const Icon(Icons.fact_check_outlined), onPressed: _contagem),
                IconButton(
                  tooltip: 'Entrada',
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    await entradaDialog(context, insumo: i);
                    setState(() {});
                  },
                ),
              ])),
          for (final m in movimentos(i!['id'] as int).take(50))
            ListTile(
              dense: true,
              leading: Icon((m['qtd'] as num) >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
                  color: (m['qtd'] as num) >= 0 ? Cores.sucesso : Cores.alerta),
              title: Text('${(m['qtd'] as num) >= 0 ? '+' : ''}${_q((m['qtd'] as num).toDouble())} $unidade'),
              subtitle: Text('${br(m['data'])} · ${txt(m['motivo'])}'),
              trailing: m['grupo'] == null
                  ? IconButton(
                      tooltip: 'Apagar',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        await Db.excluir('estoque', m['id'] as int);
                        setState(() {});
                      },
                    )
                  : null,
            ),
        ],
      ]),
    );
  }
}
