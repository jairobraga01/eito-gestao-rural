import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/proteinado.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';
import 'estoque.dart';

const _outro = 'Outro tipo…';

String _n(Object? v, [int casas = 2]) =>
    v is num ? numeroBr(v.toDouble(), casas: v % 1 == 0 ? 0 : casas) : '';

/// Fórmulas de proteinado (baixo e alto consumo, creep): custo da batida, do quilo e da seca.
class ProteinadoPage extends StatelessWidget {
  const ProteinadoPage({super.key});

  Future<void> _planilha(BuildContext context) async {
    final n = await carregarPlanilhaProteinado();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 0 ? 'As fórmulas prontas já estão aqui.' : '$n fórmula(s) pronta(s) carregada(s).')));
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Proteinado',
      acoes: [
        IconButton(
          tooltip: 'Insumos, preços e estoque',
          icon: const Icon(Icons.inventory_2_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EstoquePage())),
        ),
        PopupMenuButton<String>(
          onSelected: (_) => _planilha(context),
          itemBuilder: (_) => const [PopupMenuItem(value: 'planilha', child: Text('Carregar fórmulas prontas'))],
        ),
      ],
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Nova fórmula'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FormulaPage())),
      ),
      corpo: AoMudar<List<Reg>>(
        carregar: () async => formulas(),
        builder: (context, fs) {
          if (fs.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Vazio('Nenhuma fórmula de proteinado ainda.', icone: Icons.agriculture_outlined),
                FilledButton.icon(
                  icon: const Icon(Icons.table_view),
                  label: const Text('Carregar fórmulas prontas'),
                  onPressed: () => _planilha(context),
                ),
              ]),
            );
          }
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            for (final tipo in tiposEmUso()) ...[
              Secao(tipo,
                  acao: IconButton(
                    tooltip: 'Nova fórmula de $tipo',
                    icon: const Icon(Icons.add),
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => FormulaPage(tipoInicial: tipo))),
                  )),
              if (!fs.any((f) => tipoFormula(f) == tipo))
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nenhuma fórmula.')),
              for (final f in fs.where((f) => tipoFormula(f) == tipo)) _FormulaCard(f),
            ],
          ]);
        },
      ),
    );
  }
}

class _FormulaCard extends StatelessWidget {
  const _FormulaCard(this.f);
  final Reg f;

  @override
  Widget build(BuildContext context) {
    final c = CalculoFormula(f);
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FormulaPage(formula: f))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(txt(f['nome']), style: Theme.of(context).textTheme.titleMedium)),
              Text('${moeda(c.precoKg)}/kg',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
            ]),
            const SizedBox(height: 4),
            Text('Batida de ${kg(c.kgBatida)} · ${moeda(c.custoBatida)}'),
            Text('${_n(c.gramasDia)} g/cabeça/dia · ${moeda(c.custoCabecaDia)} por cabeça/dia'),
            Text('${c.cabecas} cab. · mês ${kg(c.kgMes)} ${moeda(c.custoMes)} · seca (${_n(c.meses, 1)} meses) ${kg(c.kgSeca)} ${moeda(c.custoSeca)}',
                style: TextStyle(color: cs.onSurfaceVariant)),
            if (c.semPreco.isNotEmpty)
              Text('Sem preço: ${c.semPreco.join(', ')}', style: const TextStyle(color: Cores.alerta)),
          ]),
        ),
      ),
    );
  }
}

/// Monta ou edita a fórmula, com a conta ao vivo e o lançamento da batida em Custos.
class FormulaPage extends StatefulWidget {
  const FormulaPage({super.key, this.formula, this.modelo, this.tipoInicial});
  final Reg? formula;

  /// Fórmula nova copiada desta (sem id).
  final Reg? modelo;
  final String? tipoInicial;

  @override
  State<FormulaPage> createState() => _FormulaPageState();
}

class _FormulaPageState extends State<FormulaPage> {
  Reg? get f => widget.formula;
  Reg? get _base => widget.formula ?? widget.modelo;
  late final nome = TextEditingController(text: txt(_base?['nome']));
  late String tipo = _base != null ? tipoFormula(_base!) : (widget.tipoInicial ?? tiposProteinado.first);
  late final consumo = TextEditingController(text: _n(_base?['consumo_g']));
  late final cabecas = TextEditingController(text: _n(_base?['cabecas'] ?? 1));
  late final meses = TextEditingController(text: _n(_base?['meses'] ?? 4));
  late final sacos = TextEditingController(text: _n(_base?['saco_qtd']));
  late final precoSaco = TextEditingController(text: _n(_base?['saco_preco']));
  late final maoObra = TextEditingController(text: _n(_base?['mao_obra']));
  late final itens = <(int?, TextEditingController)>[
    for (final it in (_base?['itens'] as List?) ?? const [])
      (Map.of(it as Map)['insumo_id'] as int?, TextEditingController(text: _n(it['kg']))),
  ];

  List<TextEditingController> get _campos => [nome, consumo, cabecas, meses, sacos, precoSaco, maoObra, for (final i in itens) i.$2];

  @override
  void dispose() {
    for (final c in _campos) {
      c.dispose();
    }
    super.dispose();
  }

  Reg get _dados => {
        'nome': nulo(nome.text) ?? 'Sem nome',
        'tipo': tipo,
        'itens': [
          for (final (id, c) in itens)
            if (id != null && (lerNumero(c.text) ?? 0) > 0) {'insumo_id': id, 'kg': lerNumero(c.text)},
        ],
        'consumo_g': lerNumero(consumo.text) ?? 0,
        'cabecas': (lerNumero(cabecas.text) ?? 1).round(),
        'meses': lerNumero(meses.text) ?? 0,
        'saco_qtd': lerNumero(sacos.text) ?? 0,
        'saco_preco': lerNumero(precoSaco.text) ?? 0,
        'mao_obra': lerNumero(maoObra.text) ?? 0,
      };

  Future<void> _salvar() async {
    if (f == null) {
      await Db.inserir('formulas', {..._dados, 'propriedade_id': Db.pid});
    } else {
      await Db.atualizar('formulas', f!['id'] as int, _dados);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _outroTipo() async {
    final c = TextEditingController();
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo tipo de fórmula'),
        content: campoTexto(c, 'Tipo (ex.: Sal mineral, Engorda)', foco: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, nulo(c.text)), child: const Text('OK')),
        ],
      ),
    );
    c.dispose();
    if (novo != null) setState(() => tipo = novo);
  }

  void _duplicar() => Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => FormulaPage(modelo: {..._dados, 'nome': '${nulo(nome.text) ?? 'Fórmula'} (cópia)'})));

  Future<void> _excluir() async {
    if (!await confirmar(context, 'Excluir a fórmula?', txt(f!['nome']), ok: 'Excluir')) return;
    await Db.excluir('formulas', f!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _batida() async {
    var data = hojeIso();
    int? lote;
    final qtd = TextEditingController(text: '1');
    final lotes = await Db.lotes();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Registrar batida'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => set(() => data = v!)),
            gap,
            campoTexto(qtd, 'Batidas', numero: true),
            gap,
            escolhaId('Lote que vai comer', lote, lotes, (v) => set(() => lote = v), vazio: 'Geral'),
            gap,
            const Text('O custo entra em Custos e margem, como Ração e sal.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lançar')),
          ],
        ),
      ),
    );
    final n = lerNumero(qtd.text);
    qtd.dispose();
    if (ok != true || n == null || n <= 0) return;
    await registrarBatida({...?f, ..._dados}, data: data, batidas: n, loteId: lote);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Batida lançada em Custos.')));
  }

  Widget _num(TextEditingController c, String rotulo, {String? sufixo, String? prefixo}) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: rotulo, suffixText: sufixo, prefixText: prefixo),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ins = insumos();
    final c = CalculoFormula(_dados);
    return Scaffold(
      appBar: AppBar(
        title: Text(f == null ? 'Nova fórmula' : txt(f!['nome'])),
        actions: [
          IconButton(tooltip: 'Duplicar', icon: const Icon(Icons.copy_outlined), onPressed: _duplicar),
          if (f != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        Row(children: [
          Expanded(flex: 3, child: campoTexto(nome, 'Nome (ex.: Nutroeste)')),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: escolha('Tipo', tipo, [...{...tiposEmUso(), tipo}, _outro], (v) {
              if (v == _outro) {
                _outroTipo();
              } else if (v != null) {
                setState(() => tipo = v);
              }
            }),
          ),
        ]),
        const Secao('Batida (kg de cada insumo)'),
        if (ins.isEmpty)
          const Text('Cadastre os insumos e os preços pelo botão de caixa na tela do Proteinado.'),
        for (var i = 0; i < itens.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: escolhaId('Insumo', itens[i].$1, ins, (v) => setState(() => itens[i] = (v, itens[i].$2)), vazio: '—'),
              ),
              const SizedBox(width: 8),
              _num(itens[i].$2, 'Kg', sufixo: 'kg'),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => itens.removeAt(i).$2.dispose()),
              ),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Adicionar insumo'),
            onPressed: ins.isEmpty ? null : () => setState(() => itens.add((null, TextEditingController()))),
          ),
        ),
        Row(children: [
          _num(sacos, 'Sacos'),
          const SizedBox(width: 8),
          _num(precoSaco, 'Preço do saco', prefixo: r'R$ '),
          const SizedBox(width: 8),
          _num(maoObra, 'Mão de obra', prefixo: r'R$ '),
        ]),
        const Secao('Consumo'),
        Row(children: [
          _num(consumo, 'Por cabeça/dia', sufixo: 'g'),
          const SizedBox(width: 8),
          _num(cabecas, 'Cabeças'),
          const SizedBox(width: 8),
          _num(meses, 'Seca', sufixo: 'meses'),
        ]),
        const Secao('Conta'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Table(columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2)}, children: [
              _linha('', 'Kg', 'R\$', negrito: true),
              for (final l in c.linhas) _linha(l.nome, numeroBr(l.kg, casas: 2), l.custo == null ? 'sem preço' : moeda(l.custo)),
              if (c.sacaria > 0) _linha('Sacaria', '', moeda(c.sacaria)),
              if (c.maoDeObra > 0) _linha('Mão de obra', '', moeda(c.maoDeObra)),
              _linha('Batida', numeroBr(c.kgBatida, casas: 2), moeda(c.custoBatida), negrito: true),
              _linha('Preço por kg', '', moeda(c.precoKg), negrito: true),
              _linha('Por cabeça/dia', numeroBr(c.gramasDia / 1000, casas: 3), moeda(c.custoCabecaDia)),
              _linha('Dia (${c.cabecas} cab.)', numeroBr(c.kgDia, casas: 2), moeda(c.custoDia)),
              _linha('Mês (30 dias)', numeroBr(c.kgMes, casas: 1), moeda(c.custoMes)),
              _linha('Seca toda', numeroBr(c.kgSeca, casas: 1), moeda(c.custoSeca), negrito: true),
            ]),
          ),
        ),
        if (c.batidasSeca != null && c.kgSeca > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('A seca toda pede ${numeroBr(c.batidasSeca!, casas: 1)} batida(s) desta fórmula.'),
          ),
        const SizedBox(height: 16),
        Row(children: [
          if (f != null)
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Registrar batida'),
                onPressed: _batida,
              ),
            ),
          if (f != null) const SizedBox(width: 12),
          Expanded(child: BotaoSalvar(onPressed: _salvar)),
        ]),
      ]),
    );
  }

  TableRow _linha(String a, String b, String c, {bool negrito = false}) {
    final s = negrito ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return TableRow(children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(a, style: s)),
      Text(b, textAlign: TextAlign.right, style: s),
      Text(c, textAlign: TextAlign.right, style: s),
    ]);
  }
}
