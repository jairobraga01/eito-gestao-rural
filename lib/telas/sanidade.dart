import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../util/util.dart';
import 'base.dart';
import 'calendario_sanitario.dart';

const eventosPesagem = ['Rotina', 'Nascimento', 'Desmama', 'Sobreano', 'Entrada', 'Venda'];

class SanidadePage extends StatelessWidget {
  const SanidadePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Sanidade',
      acoes: [
        IconButton(
          tooltip: 'Calendário sanitário',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarioSanitarioPage())),
        ),
      ],
      corpo: const _ManejosTab(),
    );
  }
}

class PesagensPage extends StatelessWidget {
  const PesagensPage({super.key});

  @override
  Widget build(BuildContext context) => const Pagina(titulo: 'Pesagem', corpo: _PesagensTab());
}

// ======================= Sanidade =======================

class _ManejosTab extends StatelessWidget {
  const _ManejosTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Manejo'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SanidadeFormPage())),
      ),
      body: AoMudar<List<Reg>>(
        carregar: Db.sanidadeGrupos,
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio('Nenhum manejo sanitário.\nLance vacinas, vermífugos e tratamentos.',
                icone: Icons.vaccines_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final g = lista[i];
              final qtd = g['qtd'] as int;
              final linhas = [
                '${br(g['data'])} · ${qtd == 1 ? 'animal ${g['brincos']}' : '$qtd animais'}'
                    '${txt(g['dose']).isEmpty ? '' : ' · dose ${g['dose']}'}',
                if (g['proxima'] != null) 'Próxima aplicação: ${br(g['proxima'])}',
              ];
              return ListTile(
                leading: const Icon(Icons.vaccines),
                title: Text('${g['produto']} (${txt(g['tipo'])})'),
                subtitle: Text(linhas.join('\n')),
                isThreeLine: linhas.length > 1,
                onTap: () => _detalhe(context, g),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _detalhe(BuildContext context, Reg g) async {
    final excluir = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${g['produto']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Info('Tipo', txt(g['tipo'])),
              Info('Data', br(g['data'])),
              Info('Dose', txt(g['dose'])),
              Info('Carência', g['carencia'] == null ? '' : '${g['carencia']} dias'),
              Info('Próxima', br(g['proxima'])),
              Info('Observações', txt(g['obs'])),
              Info('Animais (${g['qtd']})', txt(g['brincos'])),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir manejo')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fechar')),
        ],
      ),
    );
    if (excluir != true || !context.mounted) return;
    if (await confirmar(context, 'Excluir manejo?', 'Apaga o registro de ${g['qtd']} animal(is).', ok: 'Excluir')) {
      await Db.excluirGrupoSanidade(g['grupo'] as String);
    }
  }
}

/// Itens de cada categoria, como no cartão de vacinação do produtor.
const itensSanidade = <String, List<String>>{
  'Vacinação': [
    'Aftosa',
    'Antitetânica',
    'Botulismo',
    'Brucelose',
    'Clostridiose',
    'Diarreia (BVD)',
    'Doença respiratória (DBR)',
    'Leptospirose',
    'Parainfluenza e herpes',
    'Raiva',
    'Rinotraqueíte (IBR)',
    'Outros',
  ],
  'Antiparasitário': [
    'Abamectina',
    'Albendazol',
    'Babesiose (tristeza bovina) e tripanossoma',
    'Brinco mosquicida',
    'Carrapaticida e mosquicida (pour on)',
    'Carrapaticida e mosquicida (pulverização)',
    'Deltametrina, imidocarb, nitroxinil e triclorfon',
    'Doramectina',
    'Eprinomectina',
    'Ivermectina',
    'Outros',
  ],
  'Tratamento': [
    'Anestésico, sedativo e similares',
    'Analgésico',
    'Antibiótico',
    'Anti-inflamatório',
    'Antisséptico',
    'Castração química',
    'Complexo vitamínico e mineral',
    'Homeopático',
    'Hormônio',
    'Outros',
  ],
};

class SanidadeFormPage extends StatefulWidget {
  const SanidadeFormPage({super.key, this.animal});
  final Reg? animal;

  @override
  State<SanidadeFormPage> createState() => _SanidadeFormPageState();
}

class _SanidadeFormPageState extends State<SanidadeFormPage> {
  // 0 = animal, 1 = lote, 2 = pasto/piquete.
  late int modo = widget.animal == null ? 1 : 0;
  bool get porLote => modo != 0;
  late Reg? animal = widget.animal;
  int? loteId;
  int? piqueteId;
  List<Reg> lotes = [];
  List<Reg> piquetes = [];
  List<Reg> doLote = [];
  final marcadosLote = <int>{};
  String data = hojeIso();
  String categoria = 'Vacinação';
  final marcados = <String, Set<String>>{for (final k in itensSanidade.keys) k: <String>{}};
  final outros = <String, TextEditingController>{
    for (final k in itensSanidade.keys) k: TextEditingController()
  };
  final dose = TextEditingController();
  final carencia = TextEditingController();
  final obs = TextEditingController();
  String? proxima;
  bool detalhes = false;
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    Db.lotes(soAtivos: true).then((v) {
      if (mounted) setState(() => lotes = v);
    });
    Db.piquetes().then((v) {
      if (mounted) setState(() => piquetes = v);
    });
  }

  @override
  void dispose() {
    for (final c in [...outros.values, dose, carencia, obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherLote(int? id) async {
    final v = id == null ? <Reg>[] : await Db.animais(loteId: id, soAtivos: true);
    if (!mounted) return;
    setState(() {
      loteId = id;
      piqueteId = null;
      doLote = v;
      marcadosLote
        ..clear()
        ..addAll(v.map((a) => a['id'] as int));
    });
  }

  Future<void> _escolherPiquete(int? id) async {
    final v = id == null ? <Reg>[] : await Db.animais(piqueteId: id, soAtivos: true);
    if (!mounted) return;
    setState(() {
      piqueteId = id;
      loteId = null;
      doLote = v;
      marcadosLote
        ..clear()
        ..addAll(v.map((a) => a['id'] as int));
    });
  }

  void _trocarModo(int i) {
    setState(() {
      modo = i;
      loteId = null;
      piqueteId = null;
      doLote = [];
      marcadosLote.clear();
    });
  }

  int get porcentagem => doLote.isEmpty ? 0 : (marcadosLote.length * 100 / doLote.length).round();

  /// Lista final: (categoria, nome do item).
  List<(String, String)> get _itens => [
        for (final e in marcados.entries)
          for (final i in e.value)
            (e.key, i == 'Outros' ? (nulo(outros[e.key]!.text) ?? 'Outros') : i),
      ];

  Future<void> salvar() async {
    final itens = _itens;
    if (itens.isEmpty) {
      avisar(context, 'Marque ao menos um item de vacinação, antiparasitário ou tratamento.');
      return;
    }
    final List<int> ids;
    if (porLote) {
      if (modo == 1 ? loteId == null : piqueteId == null) {
        avisar(context, modo == 1 ? 'Escolha o lote.' : 'Escolha o pasto/piquete.');
        return;
      }
      ids = marcadosLote.toList();
    } else {
      if (animal == null) {
        avisar(context, 'Escolha o animal.');
        return;
      }
      ids = [animal!['id'] as int];
    }
    if (ids.isEmpty) {
      avisar(context, 'Nenhum animal selecionado.');
      return;
    }
    setState(() => salvando = true);
    final nota = [
      if (porLote) 'Aplicado em $porcentagem% ${modo == 1 ? 'do lote' : 'do pasto/piquete'}',
      if (nulo(obs.text) != null) obs.text.trim(),
    ].join(' · ');
    for (final (cat, item) in itens) {
      await Db.lancarSanidade(ids, {
        'data': data,
        'tipo': cat,
        'produto': item,
        'dose': nulo(dose.text),
        'carencia': lerNumero(carencia.text)?.round(),
        'proxima': proxima,
        'obs': nota.isEmpty ? null : nota,
      });
    }
    if (!mounted) return;
    avisar(context, '${itens.length} item(ns) lançado(s) para ${ids.length} animal(is).');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lista = itensSanidade[categoria]!;
    return Scaffold(
      appBar: AppBar(title: const Text('ADICIONAR SANIDADE')),
      bottomNavigationBar: BotaoSalvar(onPressed: salvando ? null : salvar),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Segmentos(
            opcoes: const ['ANIMAL', 'LOTE', 'PASTO/PIQUETE'],
            selecionado: modo,
            altura: 40,
            onChanged: _trocarModo,
          ),
          gap,
          if (!porLote)
            AnimalField(label: 'Animal *', animal: animal, onChanged: (a) => setState(() => animal = a)),
          if (porLote) ...[
            if (modo == 1)
              lotes.isEmpty
                  ? const Text('Nenhum lote ativo. Cadastre em menu > Lotes.')
                  : escolhaId('Lote *', loteId, lotes, _escolherLote, vazio: 'Escolha')
            else
              piquetes.isEmpty
                  ? const Text('Nenhum pasto/piquete cadastrado. Cadastre em menu > Piquete/Pasto.')
                  : escolhaId('Pasto/Piquete *', piqueteId, piquetes, _escolherPiquete, vazio: 'Escolha'),
            if (doLote.isNotEmpty) ...[
              gap,
              InputDecorator(
                decoration: InputDecoration(
                    labelText: modo == 1 ? 'Porcentagem do lote' : 'Porcentagem do pasto/piquete',
                    prefixIcon: const Icon(Icons.percent)),
                child: Text('$porcentagem%  (${marcadosLote.length} de ${doLote.length} animais)'),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(modo == 1 ? 'Escolher quais animais do lote' : 'Escolher quais animais do pasto/piquete'),
                children: [
                  for (final a in doLote)
                    CheckboxListTile(
                      dense: true,
                      value: marcadosLote.contains(a['id']),
                      title: Text(rotulo(a)),
                      onChanged: (v) => setState(() {
                        final id = a['id'] as int;
                        v == true ? marcadosLote.add(id) : marcadosLote.remove(id);
                      }),
                    ),
                ],
              ),
            ],
          ],
          gap,
          DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v!)),
          const SizedBox(height: 16),
          Segmentos(
            opcoes: [
              for (final k in itensSanidade.keys)
                '${k.toUpperCase()}${marcados[k]!.isEmpty ? '' : ' (${marcados[k]!.length})'}',
            ],
            selecionado: itensSanidade.keys.toList().indexOf(categoria),
            onChanged: (i) => setState(() => categoria = itensSanidade.keys.elementAt(i)),
          ),
          const SizedBox(height: 8),
          for (final item in lista)
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              value: marcados[categoria]!.contains(item),
              title: Text(item.toUpperCase(), style: const TextStyle(fontSize: 15)),
              onChanged: (v) => setState(() {
                v == true ? marcados[categoria]!.add(item) : marcados[categoria]!.remove(item);
              }),
            ),
          if (marcados[categoria]!.contains('Outros'))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: campoTexto(outros[categoria]!, 'Qual? (nome do produto)'),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: detalhes,
            onExpansionChanged: (v) => detalhes = v,
            title: Text('Dose, carência e próxima aplicação', style: TextStyle(color: cs.primary)),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              campoTexto(dose, 'Dose (ex.: 5 ml)'),
              gap,
              campoTexto(carencia, 'Carência', numero: true, sufixo: 'dias'),
              gap,
              DateField(label: 'Próxima aplicação', value: proxima, onChanged: (v) => setState(() => proxima = v)),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in const {'30 dias': 30, '3 meses': 90, '6 meses': 182, '1 ano': 365}.entries)
                    ActionChip(
                      label: Text('+${e.key}'),
                      onPressed: () => setState(() => proxima = somaDias(data, e.value)),
                    ),
                ],
              ),
            ],
          ),
          gap,
          campoTexto(obs, 'Observações', linhas: 3),
        ],
      ),
    );
  }
}

// ======================= Pesagens =======================

class _PesagensTab extends StatelessWidget {
  const _PesagensTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Pesagem'),
        onPressed: () => menuPesagem(context),
      ),
      body: AoMudar<List<Reg>>(
        carregar: Db.pesagens,
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio('Nenhuma pesagem registrada.', icone: Icons.monitor_weight_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final p = lista[i];
              return ListTile(
                leading: const Icon(Icons.monitor_weight_outlined),
                title: Text('${rotulo(p)} · ${kg(p['peso'] as num)}'),
                subtitle: Text('${br(p['data'])} · ${txt(p['evento'])}'),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => PesagemFormPage(registro: p))),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> menuPesagem(BuildContext context) async {
  final op = await showModalBottomSheet<int>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Pesagem individual'),
            onTap: () => Navigator.pop(c, 1),
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Pesagem de lote'),
            subtitle: const Text('Digite o peso de cada animal do lote em sequência'),
            onTap: () => Navigator.pop(c, 2),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || op == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => op == 1 ? const PesagemFormPage() : const PesagemLotePage()),
  );
}

class PesagemFormPage extends StatefulWidget {
  const PesagemFormPage({super.key, this.registro, this.animal});
  final Reg? registro;
  final Reg? animal;

  @override
  State<PesagemFormPage> createState() => _PesagemFormPageState();
}

class _PesagemFormPageState extends State<PesagemFormPage> {
  late final r = widget.registro;
  Reg? animal;
  late String data = (r?['data'] as String?) ?? hojeIso();
  late String? evento = (r?['evento'] as String?) ?? 'Rotina';
  late final peso = TextEditingController(text: r == null ? '' : num1(r!['peso'] as num));
  late final obs = TextEditingController(text: txt(r?['obs']));

  @override
  void initState() {
    super.initState();
    animal = widget.animal ??
        (r == null ? null : {'id': r!['animal_id'], 'brinco': r!['brinco'], 'nome': r!['nome']});
  }

  @override
  void dispose() {
    peso.dispose();
    obs.dispose();
    super.dispose();
  }

  Future<void> salvar() async {
    final p = lerNumero(peso.text);
    if (animal == null) {
      avisar(context, 'Escolha o animal.');
      return;
    }
    if (p == null || p <= 0) {
      avisar(context, 'Informe um peso válido.');
      return;
    }
    final v = {'animal_id': animal!['id'], 'data': data, 'peso': p, 'evento': evento, 'obs': nulo(obs.text)};
    if (r == null) {
      await Db.inserir('pesagens', v);
    } else {
      await Db.atualizar('pesagens', r!['id'] as int, v);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(r == null ? 'Nova pesagem' : 'Editar pesagem'),
        actions: [
          if (r != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirmar(context, 'Excluir pesagem?', 'Esta pesagem será apagada.', ok: 'Excluir')) {
                  return;
                }
                await Db.excluir('pesagens', r!['id'] as int);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AnimalField(
            label: 'Animal *',
            animal: animal,
            enabled: widget.animal == null,
            onChanged: (a) => setState(() => animal = a),
          ),
          gap,
          DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v!)),
          gap,
          campoTexto(peso, 'Peso *', numero: true, sufixo: 'kg', foco: r == null && widget.animal != null),
          gap,
          escolha('Evento', evento, eventosPesagem, (v) => setState(() => evento = v)),
          gap,
          campoTexto(obs, 'Observações', linhas: 2),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: salvar, icon: const Icon(Icons.save), label: const Text('Salvar')),
        ],
      ),
    );
  }
}

class PesagemLotePage extends StatefulWidget {
  const PesagemLotePage({super.key});

  @override
  State<PesagemLotePage> createState() => _PesagemLotePageState();
}

class _PesagemLotePageState extends State<PesagemLotePage> {
  List<Reg> lotes = [];
  List<Reg> piquetes = [];
  int? lote;
  int? piquete;
  bool porPiquete = false;
  bool escolhido = false;
  String data = hojeIso();
  String? evento = 'Rotina';
  List<Reg> animais = [];
  final ctrls = <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    Db.lotes(soAtivos: true).then((v) {
      if (mounted) setState(() => lotes = v);
    });
    Db.piquetes().then((v) {
      if (mounted) setState(() => piquetes = v);
    });
  }

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar(int? l) async {
    final v = await Db.animais(soAtivos: true, loteId: porPiquete ? null : l, piqueteId: porPiquete ? l : null);
    if (!mounted) return;
    setState(() {
      lote = porPiquete ? null : l;
      piquete = porPiquete ? l : null;
      escolhido = true;
      animais = v;
      for (final a in v) {
        ctrls.putIfAbsent(a['id'] as int, TextEditingController.new);
      }
    });
  }

  Future<void> salvar() async {
    final linhas = <Reg>[];
    for (final a in animais) {
      final p = lerNumero(ctrls[a['id']]?.text ?? '');
      if (p != null && p > 0) {
        linhas.add({'animal_id': a['id'], 'data': data, 'peso': p, 'evento': evento});
      }
    }
    if (linhas.isEmpty) {
      avisar(context, 'Nenhum peso preenchido.');
      return;
    }
    await Db.lancarPesagens(linhas);
    if (!mounted) return;
    avisar(context, '${linhas.length} pesagem(ns) salva(s).');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final preenchidos = animais.where((a) => lerNumero(ctrls[a['id']]?.text ?? '') != null).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Pesagem de lote')),
      bottomNavigationBar: animais.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: salvar,
                  icon: const Icon(Icons.save),
                  label: Text('Salvar $preenchidos de ${animais.length}'),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Segmentos(
            opcoes: const ['LOTE', 'PASTO/PIQUETE'],
            selecionado: porPiquete ? 1 : 0,
            altura: 40,
            onChanged: (i) => setState(() {
              porPiquete = i == 1;
              lote = null;
              piquete = null;
              escolhido = false;
              animais = [];
            }),
          ),
          gap,
          if (porPiquete)
            escolhaId('Pasto/Piquete', piquete, piquetes, _carregar, vazio: 'Todos os animais ativos')
          else
            escolhaId('Lote', lote, lotes, _carregar, vazio: 'Todos os animais ativos'),
          if (!escolhido)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(onPressed: () => _carregar(null), child: const Text('Carregar animais')),
            ),
          gap,
          DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v!)),
          gap,
          escolha('Evento', evento, eventosPesagem, (v) => setState(() => evento = v)),
          const SizedBox(height: 16),
          if (escolhido && animais.isEmpty) Text(porPiquete ? 'Nenhum animal ativo neste pasto/piquete.' : 'Nenhum animal ativo neste lote.'),
          for (var i = 0; i < animais.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rotulo(animais[i]), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          animais[i]['ultimo_peso'] == null
                              ? txt(animais[i]['categoria'])
                              : 'Último: ${kg(animais[i]['ultimo_peso'] as num)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: ctrls[animais[i]['id']],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: i + 1 < animais.length ? TextInputAction.next : TextInputAction.done,
                      decoration: const InputDecoration(suffixText: 'kg', isDense: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Botões lado a lado, um selecionado (verde cheio), como abas.
class Segmentos extends StatelessWidget {
  const Segmentos({
    super.key,
    required this.opcoes,
    required this.selecionado,
    required this.onChanged,
    this.altura = 34,
  });
  final List<String> opcoes;
  final int selecionado;
  final ValueChanged<int> onChanged;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: altura,
      decoration: BoxDecoration(
        border: Border.all(color: cs.primary),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < opcoes.length; i++)
            Expanded(
              child: Material(
                color: i == selecionado ? cs.primary : cs.surface,
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          opcoes[i],
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.3,
                            color: i == selecionado ? cs.onPrimary : cs.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
