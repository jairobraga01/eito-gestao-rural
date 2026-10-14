import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../util/util.dart';
import 'animais.dart';
import 'base.dart';

const tiposServico = ['IATF', 'IA', 'Monta natural', 'TE (embrião)'];

class ReproducaoPage extends StatefulWidget {
  const ReproducaoPage({super.key});

  @override
  State<ReproducaoPage> createState() => _ReproducaoPageState();
}

class _ReproducaoPageState extends State<ReproducaoPage> {
  String? filtro;

  static const filtros = <String?, String>{
    null: 'Todos',
    'Pendente': 'Aguardando diagnóstico',
    'Prenhe': 'Prenhes',
    'Vazia': 'Vazias',
    'Parida': 'Paridas',
  };

  Widget _lista(bool monta) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final e in filtros.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: filtro == e.key,
                  onSelected: (_) => setState(() => filtro = e.key),
                ),
            ],
          ),
        ),
        Expanded(
          child: AoMudar<List<Reg>>(
            carregar: () => Db.reproducoes(filtro: filtro, monta: monta),
            builder: (context, lista) {
              if (lista.isEmpty) {
                return Vazio(monta ? 'Nenhuma monta natural encontrada' : 'Nenhuma inseminação encontrada',
                    icone: Icons.favorite_border);
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: lista.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (c, i) => ReproducaoTile(lista[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Pagina(
        titulo: 'Reprodução',
        fab: const AcoesFab(),
        corpo: Column(
          children: [
            const TabBar(tabs: [Tab(text: 'INSEMINAÇÃO'), Tab(text: 'MONTA NATURAL')]),
            Expanded(child: TabBarView(children: [_lista(false), _lista(true)])),
          ],
        ),
      ),
    );
  }
}

String situacaoServico(Reg r) {
  if (r['parto_data'] != null) return 'Parida';
  return txt(r['diagnostico']);
}

Color corSituacao(String s) => switch (s) {
      'Prenhe' => Colors.green,
      'Vazia' => Colors.red,
      'Parida' => Colors.blue,
      _ => Colors.orange,
    };

class ReproducaoTile extends StatelessWidget {
  const ReproducaoTile(this.r, {super.key, this.mostrarFemea = true});
  final Reg r;
  final bool mostrarFemea;

  @override
  Widget build(BuildContext context) {
    final sit = situacaoServico(r);
    final linhas = <String>[
      '${br(r['data'])}${txt(r['touro']).isEmpty ? '' : ' · ${r['touro']}'}',
      if (sit == 'Prenhe' && r['parto_previsto'] != null) 'Parto previsto: ${br(r['parto_previsto'])}',
      if (sit == 'Parida') 'Pariu em ${br(r['parto_data'])}${r['cria_brinco'] == null ? '' : ' · cria ${r['cria_brinco']}'}',
    ];
    return ListTile(
      leading: Icon(Icons.favorite, color: corSituacao(sit)),
      title: Text(mostrarFemea ? '${rotulo(r)} · ${txt(r['tipo'])}' : txt(r['tipo'])),
      subtitle: Text(linhas.join('\n')),
      isThreeLine: linhas.length > 1,
      trailing: Text(sit, style: TextStyle(color: corSituacao(sit), fontWeight: FontWeight.w600)),
      onTap: () => _acoes(context),
    );
  }

  Future<void> _acoes(BuildContext context) async {
    final prenhe = situacaoServico(r) == 'Prenhe';
    final femea = <String, Object?>{'id': r['femea_id'], 'brinco': r['brinco'], 'nome': r['nome']};
    final op = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Editar / lançar diagnóstico'),
                onTap: () => Navigator.pop(c, 'editar')),
            if (prenhe)
              ListTile(
                  leading: const Icon(Icons.child_friendly_outlined),
                  title: const Text('Registrar parto'),
                  onTap: () => Navigator.pop(c, 'parto')),
            if (mostrarFemea)
              ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Ver ficha da fêmea'),
                  onTap: () => Navigator.pop(c, 'ficha')),
            ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Excluir'),
                onTap: () => Navigator.pop(c, 'excluir')),
          ],
        ),
      ),
    );
    if (!context.mounted || op == null) return;
    switch (op) {
      case 'editar':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ReproducaoFormPage(registro: r)));
      case 'parto':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => NascimentoFormPage(mae: femea, reproducao: r)));
      case 'ficha':
        Navigator.push(context, MaterialPageRoute(builder: (_) => FichaAnimalPage(r['femea_id'] as int)));
      case 'excluir':
        if (await confirmar(context, 'Excluir registro?', 'O registro de reprodução será apagado.',
            ok: 'Excluir')) {
          await Db.excluir('reproducoes', r['id'] as int);
        }
    }
  }
}

class ReproducaoFormPage extends StatefulWidget {
  const ReproducaoFormPage({super.key, this.registro, this.femea});
  final Reg? registro;
  final Reg? femea;

  @override
  State<ReproducaoFormPage> createState() => _ReproducaoFormPageState();
}

class _ReproducaoFormPageState extends State<ReproducaoFormPage> {
  late final r = widget.registro;
  Reg? femea;
  late String? tipo = (r?['tipo'] as String?) ?? 'IATF';
  late String data = (r?['data'] as String?) ?? hojeIso();
  late String diagnostico = (r?['diagnostico'] as String?) ?? 'Pendente';
  late String? dataDiag = r?['data_diagnostico'] as String?;
  late final touro = TextEditingController(text: txt(r?['touro']));
  late final inseminador = TextEditingController(text: txt(r?['inseminador']));
  late final obs = TextEditingController(text: txt(r?['obs']));
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    femea = widget.femea ??
        (r == null ? null : {'id': r!['femea_id'], 'brinco': r!['brinco'], 'nome': r!['nome']});
  }

  @override
  void dispose() {
    touro.dispose();
    inseminador.dispose();
    obs.dispose();
    super.dispose();
  }

  Future<void> salvar() async {
    if (femea == null) {
      avisar(context, 'Escolha a fêmea.');
      return;
    }
    setState(() => salvando = true);
    final v = <String, Object?>{
      'femea_id': femea!['id'],
      'tipo': tipo,
      'data': data,
      'touro': nulo(touro.text),
      'inseminador': nulo(inseminador.text),
      'diagnostico': diagnostico,
      'data_diagnostico': diagnostico == 'Pendente' ? null : (dataDiag ?? hojeIso()),
      'parto_previsto': diagnostico == 'Prenhe' ? somaDias(data, diasGestacao) : null,
      'obs': nulo(obs.text),
    };
    if (r == null) {
      await Db.inserir('reproducoes', v);
    } else {
      await Db.atualizar('reproducoes', r!['id'] as int, v);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(r == null ? 'Novo serviço' : 'Editar serviço')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AnimalField(label: 'Fêmea *', animal: femea, sexo: 'F', onChanged: (a) => setState(() => femea = a)),
          gap,
          escolha('Tipo de serviço', tipo, tiposServico, (v) => setState(() => tipo = v)),
          gap,
          DateField(label: 'Data do serviço', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v!)),
          gap,
          campoTexto(touro, tipo == 'Monta natural' ? 'Touro' : 'Touro / sêmen'),
          gap,
          campoTexto(inseminador, 'Inseminador / responsável'),
          const SizedBox(height: 20),
          Text('Diagnóstico de gestação', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Pendente', label: Text('Pendente')),
              ButtonSegment(value: 'Prenhe', label: Text('Prenhe')),
              ButtonSegment(value: 'Vazia', label: Text('Vazia')),
            ],
            selected: {diagnostico},
            onSelectionChanged: (s) => setState(() {
              diagnostico = s.first;
              if (diagnostico != 'Pendente') dataDiag ??= hojeIso();
            }),
          ),
          if (diagnostico != 'Pendente') ...[
            gap,
            DateField(label: 'Data do diagnóstico', value: dataDiag, onChanged: (v) => setState(() => dataDiag = v)),
          ],
          if (diagnostico == 'Prenhe')
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: ListTile(
                leading: const Icon(Icons.event),
                title: Text('Parto previsto: ${br(somaDias(data, diasGestacao))}'),
                subtitle: const Text('Calculado com gestação de $diasGestacao dias'),
              ),
            ),
          if (diagnostico == 'Pendente')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Diagnóstico sugerido a partir de ${br(somaDias(data, 30))} (30 dias após o serviço).'),
            ),
          gap,
          campoTexto(obs, 'Observações', linhas: 3),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: salvando ? null : salvar,
            icon: const Icon(Icons.save),
            label: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
