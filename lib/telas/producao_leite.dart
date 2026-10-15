import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/leite.dart';
import '../dados/resumo_periodo.dart' show nomesMeses;
import '../util/util.dart';
import 'base.dart';

String _l(double v) => '${numeroBr(v, casas: 1)} L';

/// Produção leiteira por vaca, com relatório do mês e do ano (individual e total).
class ProducaoLeitePage extends StatefulWidget {
  const ProducaoLeitePage({super.key});

  @override
  State<ProducaoLeitePage> createState() => _ProducaoLeitePageState();
}

class _ProducaoLeitePageState extends State<ProducaoLeitePage> {
  final hoje = DateTime.now();
  late int ano = hoje.year, mes = hoje.month;
  bool anual = false;

  void _mover(int d) => setState(() {
        if (anual) {
          ano += d;
        } else {
          final m = DateTime(ano, mes + d);
          ano = m.year;
          mes = m.month;
        }
      });

  Future<void> _vacas() async {
    final atuais = [for (final v in vacasLeiteiras()) v['id'] as int];
    final r = await pickAnimais(context, titulo: 'Vacas leiteiras', iniciais: atuais);
    if (r == null) return;
    await definirLeiteiras([for (final a in r) a['id'] as int]);
    if (mounted && r.any((a) => a['sexo'] != 'F')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Só as fêmeas entram como leiteiras.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Produção leiteira',
      acoes: [IconButton(tooltip: 'Vacas leiteiras', icon: const Icon(Icons.checklist), onPressed: _vacas)],
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.water_drop_outlined),
        label: const Text('Lançar ordenha'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdenhaPage())),
      ),
      corpo: AoMudar<(ProducaoLeite, int)>(
        carregar: () async => (anual ? ProducaoLeite.ano(ano) : ProducaoLeite.mes(ano, mes), vacasLeiteiras().length),
        builder: (context, d) {
          final (p, leiteiras) = d;
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('Mensal')), ButtonSegment(value: true, label: Text('Anual'))],
                selected: {anual},
                onSelectionChanged: (s) => setState(() => anual = s.first),
              ),
            ),
            Row(children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _mover(-1)),
              Expanded(
                child: Text(anual ? '$ano' : '${nomesMeses[mes - 1]} de $ano',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _mover(1)),
            ]),
            if (leiteiras == 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextButton.icon(
                  icon: const Icon(Icons.checklist),
                  label: const Text('Escolha as vacas leiteiras para lançar as ordenhas'),
                  onPressed: _vacas,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.2,
                children: [
                  Kpi('Produção total', _l(p.total), icone: Icons.water_drop_outlined),
                  Kpi('Média por vaca/dia', _l(p.mediaVacaDia), icone: Icons.trending_up),
                  Kpi('Média do rebanho/dia', _l(p.mediaDia), icone: Icons.calendar_today_outlined),
                  Kpi('Vacas ordenhadas', '${p.vacas.length} de $leiteiras', icone: Icons.pets_outlined),
                ],
              ),
            ),
            if (anual) ...[
              const Secao('Total por mês'),
              Barras({for (var i = 0; i < 12; i++) nomesMeses[i].substring(0, 3): p.porMes[i]}, sufixo: ' L'),
            ],
            Secao('Produção por vaca (${p.vacas.length})'),
            if (p.vacas.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nenhuma ordenha lançada no período.')),
            for (final v in p.vacas)
              ListTile(
                dense: true,
                title: Text(rotulo(v.vaca)),
                subtitle: Text('${v.dias.length} dia(s) · média ${_l(v.media)}/dia'),
                trailing: Text(_l(v.litros), style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeiteVacaPage(vaca: v.vaca, ano: ano))),
              ),
          ]);
        },
      ),
    );
  }
}

/// Lança os litros do dia de cada vaca leiteira, em série.
class OrdenhaPage extends StatefulWidget {
  const OrdenhaPage({super.key});

  @override
  State<OrdenhaPage> createState() => _OrdenhaPageState();
}

class _OrdenhaPageState extends State<OrdenhaPage> {
  String data = hojeIso();
  final vacas = vacasLeiteiras();
  late final campos = {for (final v in vacas) v['id'] as int: TextEditingController()};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    final dia = ordenhasDoDia(data);
    for (final e in campos.entries) {
      e.value.text = dia[e.key] == null ? '' : numeroBr(dia[e.key]!, casas: dia[e.key]! % 1 == 0 ? 0 : 1);
    }
  }

  @override
  void dispose() {
    for (final c in campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total => campos.values.fold(0, (s, c) => s + (lerNumero(c.text) ?? 0));

  Future<void> _salvar() async {
    for (final e in campos.entries) {
      await lancarOrdenha(e.key, data, lerNumero(e.value.text));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ordenha do dia')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => setState(() {
              data = v!;
              _carregar();
            })),
        gap,
        if (vacas.isEmpty)
          const Text('Nenhuma vaca leiteira. Escolha as vacas pelo botão de lista na tela de Produção leiteira.'),
        for (final v in vacas)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Text(rotulo(v), style: Theme.of(context).textTheme.titleMedium)),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: campos[v['id']],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Litros', suffixText: 'L'),
                ),
              ),
            ]),
          ),
        if (vacas.isNotEmpty) ...[
          gap,
          Text('Total do dia: ${_l(_total)}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          BotaoSalvar(onPressed: _salvar),
        ],
      ]),
    );
  }
}

/// Produção de uma vaca mês a mês no ano.
class LeiteVacaPage extends StatefulWidget {
  const LeiteVacaPage({super.key, required this.vaca, required this.ano});
  final Reg vaca;
  final int ano;

  @override
  State<LeiteVacaPage> createState() => _LeiteVacaPageState();
}

class _LeiteVacaPageState extends State<LeiteVacaPage> {
  late int ano = widget.ano;

  @override
  Widget build(BuildContext context) {
    final id = widget.vaca['id'];
    final meses = [
      for (var m = 1; m <= 12; m++) ProducaoLeite.mes(ano, m).vacas.where((v) => v.vaca['id'] == id).firstOrNull,
    ];
    final total = meses.fold<double>(0, (s, v) => s + (v?.litros ?? 0));
    final dias = meses.fold<int>(0, (s, v) => s + (v?.dias.length ?? 0));
    return Scaffold(
      appBar: AppBar(title: Text('Leite · ${rotulo(widget.vaca)}')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => ano--)),
          Expanded(
            child: Text('$ano · ${_l(total)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => ano++)),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('$dias dia(s) ordenhada · média ${_l(dias == 0 ? 0 : total / dias)}/dia'),
        ),
        const Secao('Por mês'),
        for (var m = 0; m < 12; m++)
          ListTile(
            dense: true,
            title: Text(nomesMeses[m]),
            subtitle: meses[m] == null ? null : Text('${meses[m]!.dias.length} dia(s) · média ${_l(meses[m]!.media)}/dia'),
            trailing: Text(_l(meses[m]?.litros ?? 0)),
          ),
      ]),
    );
  }
}
