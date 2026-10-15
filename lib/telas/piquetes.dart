// Piquetes (divisões de pasto) e manejos de pastagem.
import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/mapa.dart';
import '../util/util.dart';
import 'animais.dart';
import 'base.dart';
import 'mapa.dart';

const tiposPastagem = [
  'Entrada de animais',
  'Saída de animais',
  'Adubação',
  'Calagem',
  'Roçada',
  'Herbicida',
  'Reforma / plantio',
  'Vedação (descanso)',
  'Medição de altura',
  'Outro',
];

// ======================= Piquetes =======================

class PiquetesPage extends StatelessWidget {
  const PiquetesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Piquete/Pasto',
      fab: FloatingActionButton(
        heroTag: null,
        tooltip: 'Adicionar piquete',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PiqueteFormPage())),
        child: const Icon(Icons.add),
      ),
      acoes: [
        IconButton(
          tooltip: 'Rodízio de pastejo',
          icon: const Icon(Icons.autorenew),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RodizioPage())),
        ),
      ],
      corpo: AoMudar<(List<Reg>, Map<int, Lotacao>, Map<Object?, Rodizio>)>(
        carregar: () async =>
            (await Db.piquetes(), lotacaoPiquetes(), {for (final r in rodizio(hojeIso())) r.piquete['id']: r}),
        builder: (context, d) {
          final (lista, lot, rod) = d;
          if (lista.isEmpty) {
            return const Vazio('Nenhum piquete cadastrado.\nCadastre as divisões de pasto da propriedade.',
                icone: Icons.fence);
          }
          final area = lista.map((p) => p['area']).whereType<num>().fold<num>(0, (a, b) => a + b);
          final ocupados = lista.where((p) => (p['qtd'] as int) > 0).length;
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text('${lista.length} piquete(s) · $ocupados ocupado(s)'
                      '${area > 0 ? ' · ${num1(area)} ha' : ''}'),
                );
              }
              final p = lista[i - 1];
              final qtd = p['qtd'] as int;
              final a = p['area'] as num?;
              final cs = Theme.of(context).colorScheme;
              return ListTile(
                leading: Icon(Icons.fence, color: qtd > 0 ? cs.primary : cs.outline),
                title: Text(txt(p['nome']).toUpperCase()),
                subtitle: Text([
                  if (a != null) '${num1(a)} ha',
                  if (txt(p['forrageira']).isNotEmpty) txt(p['forrageira']),
                  if (lot[p['id']]?.uaHa != null) '${num1(lot[p['id']]!.uaHa!)} UA/ha',
                  if (rod[p['id']] != null && rod[p['id']]!.situacao != SituacaoPasto.semHistorico) rod[p['id']]!.texto
                  else if (p['ultimo_manejo'] != null) 'Último manejo ${br(p['ultimo_manejo'])}',
                ].join(' · ')),
                trailing: Text(qtd > 0 ? '$qtd cab.' : 'Vazio',
                    style: TextStyle(color: qtd > 0 ? cs.primary : cs.outline, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => PiqueteDetalhePage(p['id'] as int))),
              );
            },
          );
        },
      ),
    );
  }
}

class PiqueteFormPage extends StatefulWidget {
  const PiqueteFormPage({super.key, this.piquete});
  final Reg? piquete;

  @override
  State<PiqueteFormPage> createState() => _PiqueteFormPageState();
}

class _PiqueteFormPageState extends State<PiqueteFormPage> {
  late final p = widget.piquete;
  late final nome = TextEditingController(text: txt(p?['nome']));
  late final area = TextEditingController(text: p?['area'] is num ? num1(p!['area'] as num) : '');
  late final forrageira = TextEditingController(text: txt(p?['forrageira']));
  late final capacidade = TextEditingController(text: p?['capacidade'] is num ? num1(p!['capacidade'] as num) : '');
  late final obs = TextEditingController(text: txt(p?['obs']));
  late final ocupacao = TextEditingController(text: p?['dias_ocupacao'] is num ? '${p!['dias_ocupacao']}' : '');
  late final descanso = TextEditingController(text: p?['dias_descanso'] is num ? '${p!['dias_descanso']}' : '');

  @override
  void dispose() {
    for (final c in [nome, area, forrageira, capacidade, obs, ocupacao, descanso]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> salvar() async {
    if (nome.text.trim().isEmpty) {
      avisar(context, 'Informe o nome do piquete.');
      return;
    }
    final v = <String, Object?>{
      'nome': nome.text.trim(),
      'area': lerNumero(area.text),
      'forrageira': nulo(forrageira.text),
      'capacidade': lerNumero(capacidade.text),
      'dias_ocupacao': lerNumero(ocupacao.text)?.round(),
      'dias_descanso': lerNumero(descanso.text)?.round(),
      'obs': nulo(obs.text),
    };
    if (p == null) {
      await Db.inserir('piquetes', {...v, 'propriedade_id': Db.pid});
    } else {
      await Db.atualizar('piquetes', p!['id'] as int, v);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p == null ? 'ADICIONAR PIQUETE/PASTO' : 'EDITAR PIQUETE/PASTO')),
      bottomNavigationBar: BotaoSalvar(onPressed: salvar),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nome,
            autofocus: p == null,
            decoration: const InputDecoration(labelText: 'Nome do piquete *', prefixIcon: Icon(Icons.fence)),
          ),
          gap,
          campoTexto(area, 'Área', numero: true, sufixo: 'ha'),
          gap,
          campoTexto(forrageira, 'Forrageira (ex.: Mombaça, Braquiarão)'),
          gap,
          campoTexto(capacidade, 'Capacidade de suporte', numero: true, sufixo: 'UA/ha'),
          gap,
          Row(children: [
            Expanded(child: campoTexto(ocupacao, 'Ocupação (padrão $ocupacaoPadrao)', numero: true, sufixo: 'dias')),
            const SizedBox(width: 12),
            Expanded(child: campoTexto(descanso, 'Descanso (padrão $descansoPadrao)', numero: true, sufixo: 'dias')),
          ]),
          gap,
          campoTexto(obs, 'Anotações', linhas: 3),
        ],
      ),
    );
  }
}

class PiqueteDetalhePage extends StatelessWidget {
  const PiqueteDetalhePage(this.id, {super.key});
  final int id;

  @override
  Widget build(BuildContext context) {
    return AoMudar<(Reg?, List<Reg>, List<Reg>)>(
      carregar: () async => (
        await Db.piquete(id),
        await Db.animais(piqueteId: id, soAtivos: true),
        await Db.pastagens(piqueteId: id),
      ),
      builder: (context, d) {
        final p = d.$1;
        if (p == null) return Scaffold(appBar: AppBar(), body: const Vazio('Piquete não encontrado.'));
        final animais = d.$2, manejos = d.$3;
        final area = p['area'] as num?;
        final cap = p['capacidade'] as num?;
        final lot = lotacaoPiquetes()[id];
        final rod = rodizio(hojeIso()).where((r) => r.piquete['id'] == id).firstOrNull;
        final entrada = manejos.where((m) => m['tipo'] == 'Entrada de animais').firstOrNull;
        return Scaffold(
          appBar: AppBar(
            title: Text(txt(p['nome']).toUpperCase()),
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => PiqueteFormPage(piquete: p))),
              ),
              IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirmar(context, 'Excluir piquete?',
                      'O histórico de pastagem deste piquete será apagado. Os animais continuam cadastrados.',
                      ok: 'Excluir')) {
                    return;
                  }
                  await Db.excluir('piquetes', id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            icon: const Icon(Icons.grass),
            label: const Text('Manejo'),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => PastagemFormPage(piquete: p))),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Info('Área', area == null ? '' : '${num1(area)} ha'),
                    Info('Forrageira', txt(p['forrageira'])),
                    Info('Capacidade', cap == null ? '' : '${num1(cap)} UA/ha'),
                    Info('Animais', '${animais.length}'),
                    if (entrada != null && animais.isNotEmpty)
                      Info('Ocupado desde', '${br(entrada['data'])} (${diasEntre(txt(entrada['data']), hojeIso())} dias)'),
                    if (lot?.uaHa != null)
                      Info('Lotação atual',
                          '${num1(lot!.uaHa!)} UA/ha (${num1(lot.ua)} UA)${lot.acima ? ' – acima da capacidade' : ''}'
                          '${lot.estimados > 0 ? ' · ${lot.estimados} sem pesagem, pela categoria' : ''}'),
                    if (rod != null) Info('Rodízio', rod.texto),
                    Info('Anotações', txt(p['obs'])),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.format_list_numbered),
                    label: const Text('Contagem'),
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ContagemPage(piqueteId: id))),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.report_outlined),
                    label: const Text('Ocorrência'),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => OcorrenciaFormPage(local: centro(contorno(p))))),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.login),
                    label: const Text('Colocar animais'),
                    onPressed: () async {
                      final r = await pickAnimais(context, titulo: 'Animais que entram no piquete');
                      if (r == null || r.isEmpty) return;
                      await Db.moverParaPiquete(r, id, hojeIso());
                    },
                  ),
                  if (animais.isNotEmpty)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.logout),
                      label: const Text('Retirar todos'),
                      onPressed: () async {
                        if (!await confirmar(context, 'Retirar animais?',
                            'Os ${animais.length} animais saem deste piquete hoje.', ok: 'Retirar')) {
                          return;
                        }
                        await Db.retirarDoPiquete(animais, id, hojeIso());
                      },
                    ),
                ]),
              ),
              Secao('Animais no piquete (${animais.length})'),
              if (animais.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Piquete vazio.')),
              for (final a in animais) AnimalTile(a),
              Secao('Histórico de pastagem (${manejos.length})'),
              if (manejos.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Sem registros.')),
              for (final m in manejos) PastagemTile(m, mostrarPiquete: false),
            ],
          ),
        );
      },
    );
  }
}

// ======================= Pastagem =======================

class PastagemPage extends StatelessWidget {
  const PastagemPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Pastagem',
      fab: FloatingActionButton(
        heroTag: null,
        tooltip: 'Novo manejo de pastagem',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PastagemFormPage())),
        child: const Icon(Icons.add),
      ),
      corpo: AoMudar<List<Reg>>(
        carregar: Db.pastagens,
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio(
                'Nenhum manejo de pastagem.\nRegistre adubação, roçada, vedação, altura do capim e entrada ou saída de animais.',
                icone: Icons.grass);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) => PastagemTile(lista[i]),
          );
        },
      ),
    );
  }
}

class PastagemTile extends StatelessWidget {
  const PastagemTile(this.m, {super.key, this.mostrarPiquete = true});
  final Reg m;
  final bool mostrarPiquete;

  @override
  Widget build(BuildContext context) {
    final altura = m['altura'] as num?;
    final linha = [
      br(m['data']),
      if (txt(m['quantidade']).isNotEmpty) txt(m['quantidade']),
      if (altura != null) 'altura ${num1(altura)} cm',
      if (txt(m['descricao']).isNotEmpty) txt(m['descricao']),
    ].join(' · ');
    return ListTile(
      leading: Icon(Icons.grass, color: Theme.of(context).colorScheme.primary),
      title: Text(mostrarPiquete ? '${m['piquete_nome']} · ${m['tipo']}' : txt(m['tipo'])),
      subtitle: Text(linha, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PastagemFormPage(registro: m))),
    );
  }
}

class PastagemFormPage extends StatefulWidget {
  const PastagemFormPage({super.key, this.registro, this.piquete});
  final Reg? registro;
  final Reg? piquete;

  @override
  State<PastagemFormPage> createState() => _PastagemFormPageState();
}

class _PastagemFormPageState extends State<PastagemFormPage> {
  late final r = widget.registro;
  List<Reg> piquetes = [];
  late int? piqueteId = (r?['piquete_id'] as int?) ?? (widget.piquete?['id'] as int?);
  late String data = (r?['data'] as String?) ?? hojeIso();
  late String? tipo = (r?['tipo'] as String?) ?? 'Adubação';
  late final descricao = TextEditingController(text: txt(r?['descricao']));
  late final quantidade = TextEditingController(text: txt(r?['quantidade']));
  late final altura = TextEditingController(text: r?['altura'] is num ? num1(r!['altura'] as num) : '');
  late final obs = TextEditingController(text: txt(r?['obs']));

  @override
  void initState() {
    super.initState();
    Db.piquetes().then((v) {
      if (mounted) setState(() => piquetes = v);
    });
  }

  @override
  void dispose() {
    for (final c in [descricao, quantidade, altura, obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> salvar() async {
    if (piqueteId == null) {
      avisar(context, 'Escolha o piquete.');
      return;
    }
    final v = <String, Object?>{
      'piquete_id': piqueteId,
      'data': data,
      'tipo': tipo ?? 'Outro',
      'descricao': nulo(descricao.text),
      'quantidade': nulo(quantidade.text),
      'altura': lerNumero(altura.text),
      'obs': nulo(obs.text),
    };
    if (r == null) {
      await Db.inserir('pastagens', v);
    } else {
      await Db.atualizar('pastagens', r!['id'] as int, v);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final medicao = tipo == 'Medição de altura';
    return Scaffold(
      appBar: AppBar(
        title: Text(r == null ? 'MANEJO DE PASTAGEM' : 'EDITAR MANEJO'),
        actions: [
          if (r != null)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirmar(context, 'Excluir registro?', 'Este manejo será apagado.', ok: 'Excluir')) {
                  return;
                }
                await Db.excluir('pastagens', r!['id'] as int);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      bottomNavigationBar: BotaoSalvar(onPressed: salvar),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (piquetes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Cadastre um piquete primeiro (menu > Piquete/Pasto).'),
            ),
          escolhaId('Piquete/Pasto *', piqueteId, piquetes, (v) => setState(() => piqueteId = v), vazio: 'Escolha'),
          gap,
          escolha('Tipo de manejo', tipo, tiposPastagem, (v) => setState(() => tipo = v)),
          gap,
          DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v!)),
          gap,
          campoTexto(descricao, medicao ? 'Ponto de medição' : 'Produto / descrição'),
          gap,
          if (!medicao) ...[
            campoTexto(quantidade, 'Quantidade (ex.: 200 kg/ha)'),
            gap,
          ],
          campoTexto(altura, 'Altura do capim', numero: true, sufixo: 'cm'),
          gap,
          campoTexto(obs, 'Anotações', linhas: 3),
        ],
      ),
    );
  }
}
