import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/estoque.dart';
import '../dados/proteinado.dart' show CalculoFormula, formulas, insumos;
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';

String _q(double v, [int casas = 1]) => numeroBr(v, casas: v % 1 == 0 ? 0 : casas);

/// Dieta do cocho: o que se põe no cocho de cada piquete/pasto por dia, custo e consumo previsto do mês.
class DietaPage extends StatelessWidget {
  const DietaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Dieta do cocho',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Nova dieta'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DietaFormPage())),
      ),
      corpo: AoMudar<List<Dieta>>(
        carregar: () async => dietas(),
        builder: (context, ds) {
          if (ds.isEmpty) {
            return const Vazio('Nenhuma dieta. Diga o que vai no cocho de cada piquete/pasto (proteinado, sal, ração) e quanto por cabeça.',
                icone: Icons.restaurant_outlined);
          }
          final porLocal = <String, List<Dieta>>{};
          for (final d in ds) {
            porLocal.putIfAbsent(d.local, () => []).add(d);
          }
          final kgMes = ds.fold<double>(0, (s, d) => s + d.kgMes);
          final custoMes = ds.fold<double>(0, (s, d) => s + d.custoMes);
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 100,
                child: Row(children: [
                  Expanded(child: Kpi('Consumo previsto no mês', kg(kgMes), icone: Icons.scale_outlined)),
                  Expanded(child: Kpi('Custo previsto no mês', moeda(custoMes), icone: Icons.attach_money)),
                ]),
              ),
            ),
            for (final e in porLocal.entries) ...[
              Secao('${e.key} · ${e.value.first.cabecas} cab.'),
              for (final d in e.value) _DietaCard(d),
            ],
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Mês = 30 dias com as cabeças de hoje. "Lançar trato" põe o custo em Custos (no lote, quando o gado do piquete é todo de um lote) e tira do estoque.'),
            ),
          ]);
        },
      ),
    );
  }
}

class _DietaCard extends StatelessWidget {
  const _DietaCard(this.d);
  final Dieta d;

  Future<void> _trato(BuildContext context) async {
    var data = hojeIso();
    final dias = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Trato · ${d.nome}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => set(() => data = v!)),
            gap,
            campoTexto(dias, 'Dias de trato', numero: true),
            gap,
            Text('${_q(d.kgDia)} kg por dia para ${d.cabecas} cabeças.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lançar')),
          ],
        ),
      ),
    );
    final n = lerNumero(dias.text)?.round();
    dias.dispose();
    if (ok != true || n == null || n <= 0) return;
    final id = await lancarTrato(d, data: data, dias: n);
    if (context.mounted) avisar(context, id == null ? 'Nada a lançar: confira a quantidade.' : 'Trato lançado em Custos e no estoque.');
  }

  Future<void> _bater(BuildContext context) async {
    final f = d.formula!;
    final c = CalculoFormula(f);
    var data = hojeIso();
    final qtd = TextEditingController(text: c.kgBatida > 0 ? _q(c.kgBatida) : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final kgs = lerNumero(qtd.text)?.toDouble() ?? 0;
          final batidas = c.kgBatida > 0 ? kgs / c.kgBatida : 0.0;
          return AlertDialog(
            title: Text('Bater ração · ${f['nome']}'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => set(() => data = v!)),
                gap,
                TextField(
                  controller: qtd,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quanto foi batido', suffixText: 'kg'),
                  onChanged: (_) => set(() {}),
                ),
                gap,
                Text('Custo por quilo: ${c.precoKg == null ? '-' : moeda(c.precoKg)}'),
                if (kgs > 0) ...[
                  const SizedBox(height: 8),
                  const Text('Sai do estoque:', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final l in c.linhas)
                    Text('${l.nome}: ${_q(l.kg * batidas)} kg'
                        '${l.insumo != null && saldo(l.insumo!['id'] as int) < l.kg * batidas ? ' (estoque insuficiente)' : ''}'),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bater')),
            ],
          );
        },
      ),
    );
    final kgs = lerNumero(qtd.text)?.toDouble() ?? 0;
    qtd.dispose();
    if (ok != true || kgs <= 0) return;
    final preco = await baterRacao(f, data: data, kgBatidos: kgs);
    if (!context.mounted) return;
    avisar(context, preco == null ? 'A fórmula não tem ingredientes.' : '${_q(kgs)} kg de ração no estoque, a ${moeda(preco)} o quilo.');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final estoque = d.diasDeEstoque;
    final pronta = racaoPronta(d.formula?['id']);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DietaFormPage(dieta: d.reg))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(d.nome, style: Theme.of(context).textTheme.titleMedium)),
              Text('${_q(d.kgCabDia * 1000, 0)} g/cab/dia', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            Text('Por dia: ${kg(d.kgDia)} · ${moeda(d.custoDia)} (${moeda(d.custoCabDia)} por cabeça)'),
            Text('No mês: ${kg(d.kgMes)} · ${moeda(d.custoMes)}'
                '${d.batidasMes == null ? '' : ' · ${_q(d.batidasMes!)} batida(s)'}'),
            if (d.lote != null)
              const Text('Dieta antiga, feita por lote: toque para passar para um piquete/pasto.',
                  style: TextStyle(color: Cores.alerta)),
            if (d.precoKg == null) const Text('Sem preço: informe o preço do insumo.', style: TextStyle(color: Cores.alerta)),
            if (estoque != null)
              Text('Estoque dá para ${estoque.floor().clamp(0, 99999)} dia(s)',
                  style: TextStyle(color: estoque < 15 ? Cores.alerta : cs.onSurfaceVariant)),
            if (pronta != null)
              Text('Ração pronta no estoque: ${kg(saldo(pronta['id'] as int))}'),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(children: [
                if (d.formula != null)
                  TextButton.icon(
                      icon: const Icon(Icons.blender_outlined), label: const Text('Bater ração'), onPressed: () => _bater(context)),
                TextButton.icon(icon: const Icon(Icons.restaurant), label: const Text('Lançar trato'), onPressed: () => _trato(context)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class DietaFormPage extends StatefulWidget {
  const DietaFormPage({super.key, this.dieta});
  final Reg? dieta;

  @override
  State<DietaFormPage> createState() => _DietaFormPageState();
}

class _DietaFormPageState extends State<DietaFormPage> {
  Reg? get d => widget.dieta;
  late int? piquete = d?['piquete_id'] as int?;
  late String origem = d?['insumo_id'] != null ? 'Insumo' : 'Proteinado';
  late int? formula = d?['formula_id'] as int?;
  late int? insumo = d?['insumo_id'] as int?;
  late final gramas = TextEditingController(
      text: d?['kg_cab_dia'] is num ? numeroBr((d!['kg_cab_dia'] as num) * 1000, casas: 0) : '');
  List<Reg> piquetes = [];

  @override
  void initState() {
    super.initState();
    Db.piquetes().then((l) => mounted ? setState(() => piquetes = l) : null);
  }

  @override
  void dispose() {
    gramas.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final g = lerNumero(gramas.text);
    final item = origem == 'Proteinado' ? formula : insumo;
    if (piquete == null || item == null || g == null || g <= 0) {
      return avisar(context, 'Escolha o piquete/pasto, o que vai no cocho e quanto por cabeça.');
    }
    final dados = {
      'piquete_id': piquete,
      'lote_id': null,
      'formula_id': origem == 'Proteinado' ? formula : null,
      'insumo_id': origem == 'Insumo' ? insumo : null,
      'kg_cab_dia': g / 1000,
    };
    if (d == null) {
      await Db.inserir('dietas', {...dados, 'propriedade_id': Db.pid});
    } else {
      await Db.atualizar('dietas', d!['id'] as int, dados);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    await Db.excluir('dietas', d!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fs = [for (final f in formulas()) {...f, 'rotulo': '${f['nome']} (${f['tipo']})'}];
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'Nova dieta' : 'Dieta'),
        actions: [if (d != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir)],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        escolhaId('Piquete/Pasto', piquete, piquetes, (v) => setState(() => piquete = v), vazio: '—'),
        gap,
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Proteinado', label: Text('Fórmula do proteinado')),
            ButtonSegment(value: 'Insumo', label: Text('Insumo do estoque')),
          ],
          selected: {origem},
          onSelectionChanged: (s) => setState(() => origem = s.first),
        ),
        gap,
        if (origem == 'Proteinado')
          escolhaId('Fórmula', formula, fs, (v) => setState(() {
                formula = v;
                final g = Db.registro('formulas', v)?['consumo_g'];
                if (gramas.text.trim().isEmpty && g is num && g > 0) gramas.text = numeroBr(g.toDouble(), casas: 0);
              }), vazio: '—', campo: 'rotulo')
        else
          escolhaId('Insumo (sal, ração...)', insumo, insumos(), (v) => setState(() => insumo = v), vazio: '—'),
        gap,
        campoTexto(gramas, 'Quanto por cabeça por dia', numero: true, sufixo: 'g'),
        if (piquete != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${animaisDoPiquete(piquete).length} cabeça(s) no piquete/pasto hoje.'),
          ),
        const SizedBox(height: 16),
        BotaoSalvar(onPressed: _salvar),
      ]),
    );
  }
}
