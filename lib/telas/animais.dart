import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/gestao.dart' show Genealogia;
import '../dados/manejo.dart' show intervaloEntrePartos, partosDaVaca;
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/util.dart';
import '../widgets/foto_animal.dart';
import 'base.dart';
import 'ficha_animal.dart' show FichaCurral;
import 'mover.dart';
import 'reproducao.dart';
import 'sanidade.dart';
import 'vendas.dart';
import 'importar_animais.dart';

// ======================= Lista de animais =======================

class AnimaisPage extends StatefulWidget {
  const AnimaisPage({super.key});

  @override
  State<AnimaisPage> createState() => _AnimaisPageState();
}

class _AnimaisPageState extends State<AnimaisPage> {
  String busca = '';
  bool soAtivos = true;
  String? sexo;
  String ordem = 'Número';
  bool buscando = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pagina(
      titulo: 'Rebanho',
      acoes: [
        if (!Db.ehCampo)
          IconButton(
            tooltip: 'Importar animais de planilha',
            icon: const Icon(Icons.upload_file),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportarAnimaisPage())),
          ),
        IconButton(
          tooltip: 'Mover animais de lote, piquete ou propriedade',
          icon: const Icon(Icons.swap_horiz),
          onPressed: () async {
            final r = await pickAnimais(context, titulo: 'Animais para mover');
            if (r == null || r.isEmpty || !context.mounted) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => MoverAnimaisPage(animais: r)));
          },
        ),
        IconButton(
          tooltip: 'Buscar',
          icon: Icon(buscando ? Icons.close : Icons.search),
          onPressed: () => setState(() {
            buscando = !buscando;
            if (!buscando) busca = '';
          }),
        ),
      ],
      fab: const AcoesFab(),
      corpo: Column(
        children: [
          if (buscando)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar por brinco, nome, lote ou raça',
                ),
                onChanged: (v) => setState(() => busca = v),
              ),
            ),
          Material(
            color: cs.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.sort_by_alpha, color: cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: ordem,
                      decoration: const InputDecoration(
                          labelText: 'Ordem', border: InputBorder.none, isDense: true),
                      items: [
                        for (final o in Db.ordens.keys) DropdownMenuItem(value: o, child: Text(o)),
                      ],
                      onChanged: (v) => setState(() => ordem = v ?? 'Número'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Só ativos'),
                  selected: soAtivos,
                  onSelected: (v) => setState(() => soAtivos = v),
                ),
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: sexo == null,
                  onSelected: (_) => setState(() => sexo = null),
                ),
                ChoiceChip(
                  label: const Text('Fêmeas'),
                  selected: sexo == 'F',
                  onSelected: (_) => setState(() => sexo = 'F'),
                ),
                ChoiceChip(
                  label: const Text('Machos'),
                  selected: sexo == 'M',
                  onSelected: (_) => setState(() => sexo = 'M'),
                ),
              ],
            ),
          ),
          Expanded(
            child: AoMudar<List<Reg>>(
              carregar: () => Db.animais(
                  busca: busca, sexo: sexo, soAtivos: soAtivos, ordem: Db.ordens[ordem] ?? 'numero'),
              builder: (context, lista) {
                if (lista.isEmpty) {
                  return const Vazio('Nenhum animal nesta propriedade.\nToque em + para cadastrar.',
                      icone: Icons.pets);
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: lista.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Text('${lista.length} animal(is)',
                            style: Theme.of(context).textTheme.labelMedium),
                      );
                    }
                    return AnimalTile(lista[i - 1]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> menuNovoAnimal(BuildContext context) async {
  final op = await showModalBottomSheet<int>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Cadastrar animal'),
            subtitle: const Text('Compra, animal já existente na fazenda'),
            onTap: () => Navigator.pop(c, 1),
          ),
          ListTile(
            leading: const Icon(Icons.child_friendly_outlined),
            title: const Text('Registrar nascimento'),
            subtitle: const Text('Cria nascida de uma vaca do rebanho'),
            onTap: () => Navigator.pop(c, 2),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || op == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => op == 1 ? const AnimalFormPage() : const NascimentoFormPage()),
  );
}

class AnimalTile extends StatelessWidget {
  const AnimalTile(this.a, {super.key});
  final Reg a;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ativo = a['status'] == 'Ativo';
    final partes = [
      txt(a['categoria']).isEmpty ? 'Sem categoria' : txt(a['categoria']),
      txt(a['raca']),
      if (txt(a['lote_nome']).isNotEmpty) 'Lote ${a['lote_nome']}',
      if (txt(a['piquete_nome']).isNotEmpty) 'Piquete/Pasto ${a['piquete_nome']}',
      idade(a['nascimento']),
      if (a['ultimo_peso'] != null) kg(a['ultimo_peso'] as num),
    ].where((x) => x.isNotEmpty);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: a['sexo'] == 'F' ? Colors.pink.shade50 : Colors.blue.shade50,
        child: Icon(a['sexo'] == 'F' ? Icons.female : Icons.male,
            color: a['sexo'] == 'F' ? Colors.pink : Colors.blue),
      ),
      title: Text(rotulo(a), style: TextStyle(color: ativo ? null : cs.outline)),
      subtitle: Text(partes.join(' · ')),
      trailing: ativo ? const Icon(Icons.chevron_right) : Chip(label: Text(txt(a['status']))),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FichaAnimalPage(a['id'] as int)),
      ),
    );
  }
}

// ======================= Cadastro / edição =======================

class AnimalFormPage extends StatefulWidget {
  const AnimalFormPage({super.key, this.animal, this.codigoLido});
  final Reg? animal;

  /// Código lido pelo bastão (ou digitado) que não foi encontrado no rebanho.
  final String? codigoLido;

  @override
  State<AnimalFormPage> createState() => _AnimalFormPageState();
}

class _AnimalFormPageState extends State<AnimalFormPage> {
  late final brinco = TextEditingController(text: txt(widget.animal?['brinco']));
  late final nome = TextEditingController(text: txt(widget.animal?['nome']));
  late final raca = TextEditingController(text: txt(widget.animal?['raca']));
  late final pai = TextEditingController(text: txt(widget.animal?['pai']));
  late final obs = TextEditingController(text: txt(widget.animal?['obs']));
  late final rfid = TextEditingController(text: txt(widget.animal?['rfid']));
  late final sisbov = TextEditingController(text: txt(widget.animal?['sisbov']));
  final peso = TextEditingController();
  VoidCallback? _cancelarLeitor;

  late String sexo = txt(widget.animal?['sexo']).isEmpty ? 'F' : txt(widget.animal?['sexo']);
  late String? nascimento = widget.animal?['nascimento'] as String?;
  late String? categoria = widget.animal?['categoria'] as String?;
  late String? origem = (widget.animal?['origem'] as String?) ?? 'Compra';
  late String status = (widget.animal?['status'] as String?) ?? 'Ativo';
  Reg? mae;
  late int? loteId = widget.animal?['lote_id'] as int?;
  late int? piqueteId = widget.animal?['piquete_id'] as int?;
  List<Reg> lotes = [], piquetes = [];
  bool categoriaManual = false;
  bool salvando = false;

  bool get editando => widget.animal != null;

  @override
  void initState() {
    super.initState();
    final c = widget.codigoLido;
    if (c != null) {
      // Brinco eletrônico (RFID) tem 15 dígitos; o brinco visual é curto.
      (c.length >= 8 ? rfid : brinco).text = c;
    }
    // Encostou o bastão com esta tela aberta: preenche o brinco eletrônico.
    _cancelarLeitor = LeitorTeclado.instancia.assinar((leitura) {
      if (parecePeso(leitura)) return;
      setState(() => rfid.text = leitura.trim());
      // O bastão "digita" no campo que estiver com o cursor: tira de lá.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        for (final c in [brinco, nome, raca, pai, obs, sisbov, peso]) {
          if (c.text.endsWith(leitura.trim())) {
            c.text = c.text.substring(0, c.text.length - leitura.trim().length);
          }
        }
      });
    });
    categoriaManual = editando;
    final maeId = widget.animal?['mae_id'];
    if (maeId != null) {
      mae = {'id': maeId, 'brinco': widget.animal?['mae_brinco'] ?? '?', 'nome': widget.animal?['mae_nome']};
    }
    categoria ??= sugerirCategoria(sexo, nascimento);
    Db.lotes().then((v) {
      if (mounted) setState(() => lotes = v.where((l) => Db.loteAtivo(l) || l['id'] == loteId).toList());
    });
    Db.piquetes().then((v) {
      if (mounted) setState(() => piquetes = v);
    });
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    for (final c in [brinco, nome, raca, pai, obs, rfid, sisbov, peso]) {
      c.dispose();
    }
    super.dispose();
  }

  void _recalcularCategoria() {
    if (!categoriaManual) categoria = sugerirCategoria(sexo, nascimento);
    final validas = sexo == 'F' ? categoriasF : categoriasM;
    if (!validas.contains(categoria)) categoria = sugerirCategoria(sexo, nascimento);
  }

  Future<void> salvar() async {
    if (brinco.text.trim().isEmpty) {
      avisar(context, 'Informe o número do brinco.');
      return;
    }
    if (mae != null && mae!['id'] == widget.animal?['id']) {
      avisar(context, 'O animal não pode ser mãe dele mesmo.');
      return;
    }
    setState(() => salvando = true);
    final v = <String, Object?>{
      'brinco': brinco.text.trim(),
      'rfid': nulo(rfid.text),
      'sisbov': nulo(sisbov.text),
      'nome': nulo(nome.text),
      'sexo': sexo,
      'raca': nulo(raca.text),
      'categoria': categoria,
      'nascimento': nascimento,
      'mae_id': mae?['id'],
      'pai': nulo(pai.text),
      'lote_id': loteId,
      'piquete_id': piqueteId,
      'origem': origem,
      'obs': nulo(obs.text),
    };
    try {
      if (editando) {
        v['status'] = status;
        if (status == 'Ativo') v['saida_id'] = null;
        await Db.atualizar('animais', widget.animal!['id'] as int, v);
      } else {
        v['status'] = 'Ativo';
        v['propriedade_id'] = Db.pid;
        v['criado_em'] = DateTime.now().toIso8601String();
        final id = await Db.inserir('animais', v);
        final p = lerNumero(peso.text);
        if (p != null && p > 0) {
          await Db.inserir('pesagens', {
            'animal_id': id,
            'data': hojeIso(),
            'peso': p,
            'evento': origem == 'Compra' ? 'Entrada' : 'Rotina',
          });
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on RegistroDuplicado catch (e) {
      setState(() => salvando = false);
      if (!mounted) return;
      avisar(context, e.mensagem);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(editando ? 'Editar animal' : 'Cadastrar animal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          campoTexto(brinco, 'Brinco / identificação *', foco: !editando),
          gap,
          TextField(
            controller: rfid,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Brinco eletrônico (RFID)',
              helperText: 'Encoste o bastão no brinco para preencher',
              prefixIcon: Icon(Icons.contactless_outlined),
            ),
          ),
          gap,
          TextField(
            controller: sisbov,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Número oficial (SISBOV / PNIB)',
              helperText: 'Identificação individual do MAPA, se o animal já tiver',
              prefixIcon: Icon(Icons.verified_outlined),
            ),
          ),
          gap,
          campoTexto(nome, 'Nome (opcional)'),
          gap,
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'F', label: Text('Fêmea'), icon: Icon(Icons.female)),
              ButtonSegment(value: 'M', label: Text('Macho'), icon: Icon(Icons.male)),
            ],
            selected: {sexo},
            onSelectionChanged: (s) => setState(() {
              sexo = s.first;
              _recalcularCategoria();
            }),
          ),
          gap,
          DateField(
            label: 'Data de nascimento',
            value: nascimento,
            onChanged: (v) => setState(() {
              nascimento = v;
              _recalcularCategoria();
            }),
          ),
          if (nascimento != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 12),
              child: Text('Idade: ${idade(nascimento)}'),
            ),
          gap,
          escolha('Categoria', categoria, sexo == 'F' ? categoriasF : categoriasM, (v) {
            setState(() {
              categoria = v;
              categoriaManual = true;
            });
          }),
          gap,
          campoTexto(raca, 'Raça'),
          gap,
          escolhaId('Lote', loteId, lotes, (v) => setState(() => loteId = v), vazio: 'Sem lote'),
          gap,
          escolhaId('Piquete/Pasto', piqueteId, piquetes, (v) => setState(() => piqueteId = v), vazio: 'Nenhum'),
          gap,
          AnimalField(
            label: 'Mãe',
            animal: mae,
            sexo: 'F',
            onChanged: (a) => setState(() => mae = a),
          ),
          if (mae != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => setState(() => mae = null), child: const Text('Remover mãe')),
            ),
          gap,
          campoTexto(pai, 'Pai (touro ou sêmen)'),
          gap,
          escolha('Origem', origem, const ['Compra', 'Nascimento', 'Outro'], (v) => setState(() => origem = v)),
          if (!editando) ...[
            gap,
            campoTexto(peso, 'Peso atual (opcional)', numero: true, sufixo: 'kg'),
          ],
          if (editando) ...[
            gap,
            escolha('Situação', status, ['Ativo', ...statusPorSaida.values], (v) => setState(() => status = v!)),
          ],
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

// ======================= Nascimento =======================

class NascimentoFormPage extends StatefulWidget {
  const NascimentoFormPage({super.key, this.mae, this.reproducao});
  final Reg? mae;
  final Reg? reproducao;

  @override
  State<NascimentoFormPage> createState() => _NascimentoFormPageState();
}

class _NascimentoFormPageState extends State<NascimentoFormPage> {
  Reg? mae;
  Reg? servico;
  String data = hojeIso();
  String sexo = 'F';
  final brinco = TextEditingController();
  final nome = TextEditingController();
  final raca = TextEditingController();
  final pai = TextEditingController();
  final peso = TextEditingController();
  final obs = TextEditingController();
  int? loteId;
  List<Reg> lotes = [];
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    servico = widget.reproducao;
    mae = widget.mae;
    if (mae != null) _completarMae(mae!);
    Db.lotes(soAtivos: true).then((v) {
      if (mounted) setState(() => lotes = v);
    });
  }

  @override
  void dispose() {
    for (final c in [brinco, nome, raca, pai, peso, obs]) {
      c.dispose();
    }
    super.dispose();
  }

  void _definirMae(Reg m) {
    setState(() {
      mae = m;
      if (widget.reproducao == null) servico = null;
    });
    _completarMae(m);
  }

  Future<void> _completarMae(Reg m) async {
    final completo = await Db.animal(m['id'] as int);
    final rep = widget.reproducao ?? await Db.reproducaoAberta(m['id'] as int);
    if (!mounted) return;
    setState(() {
      servico = rep;
      if (completo != null) {
        if (raca.text.isEmpty) raca.text = txt(completo['raca']);
        loteId ??= completo['lote_id'] as int?;
      }
      if (rep != null && pai.text.isEmpty) pai.text = txt(rep['touro']);
    });
  }

  Future<void> salvar() async {
    if (mae == null) {
      avisar(context, 'Escolha a mãe.');
      return;
    }
    if (brinco.text.trim().isEmpty) {
      avisar(context, 'Informe o brinco da cria.');
      return;
    }
    setState(() => salvando = true);
    try {
      await Db.registrarNascimento(
        maeId: mae!['id'] as int,
        data: data,
        brinco: brinco.text.trim(),
        sexo: sexo,
        nome: nulo(nome.text),
        raca: nulo(raca.text),
        pai: nulo(pai.text),
        peso: lerNumero(peso.text),
        loteId: loteId,
        obs: nulo(obs.text),
        reproducaoId: servico?['id'] as int?,
      );
      if (!mounted) return;
      avisar(context, 'Nascimento registrado.');
      Navigator.pop(context, true);
    } on RegistroDuplicado catch (e) {
      setState(() => salvando = false);
      if (!mounted) return;
      avisar(context, e.mensagem);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar nascimento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AnimalField(label: 'Mãe *', animal: mae, sexo: 'F', onChanged: (a) => _definirMae(a!)),
          if (servico != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(
                'Serviço vinculado: ${txt(servico!['tipo'])} em ${br(servico!['data'])}'
                '${servico!['parto_previsto'] != null ? ' · parto previsto ${br(servico!['parto_previsto'])}' : ''}',
              ),
            ),
          gap,
          DateField(label: 'Data do parto', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v!)),
          gap,
          campoTexto(brinco, 'Brinco da cria *'),
          gap,
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'F', label: Text('Fêmea'), icon: Icon(Icons.female)),
              ButtonSegment(value: 'M', label: Text('Macho'), icon: Icon(Icons.male)),
            ],
            selected: {sexo},
            onSelectionChanged: (s) => setState(() => sexo = s.first),
          ),
          gap,
          campoTexto(nome, 'Nome (opcional)'),
          gap,
          campoTexto(peso, 'Peso ao nascer', numero: true, sufixo: 'kg'),
          gap,
          campoTexto(raca, 'Raça'),
          gap,
          campoTexto(pai, 'Pai (touro ou sêmen)'),
          gap,
          escolhaId('Lote', loteId, lotes, (v) => setState(() => loteId = v), vazio: 'Sem lote'),
          gap,
          campoTexto(obs, 'Observações', linhas: 3),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: salvando ? null : salvar,
            icon: const Icon(Icons.save),
            label: const Text('Salvar nascimento'),
          ),
        ],
      ),
    );
  }
}

// ======================= Ficha do animal =======================

class _Ficha {
  _Ficha(this.a, this.filhos, this.pesagens, this.reproducoes, this.sanidade, this.saida);
  final Reg a;
  final List<Reg> filhos, pesagens, reproducoes, sanidade;
  final Reg? saida;
}

class FichaAnimalPage extends StatelessWidget {
  const FichaAnimalPage(this.id, {super.key});
  final int id;

  Future<_Ficha?> _carregar() async {
    final a = await Db.animal(id);
    if (a == null) return null;
    return _Ficha(
      a,
      await Db.filhos(id),
      await Db.pesagens(animalId: id),
      a['sexo'] == 'F' ? await Db.reproducoes(femeaId: id) : <Reg>[],
      await Db.sanidadeDoAnimal(id),
      a['saida_id'] == null ? null : await Db.saida(a['saida_id'] as int),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AoMudar<_Ficha?>(
      carregar: _carregar,
      builder: (context, f) {
        if (f == null) {
          return Scaffold(appBar: AppBar(), body: const Vazio('Animal não encontrado.'));
        }
        final a = f.a;
        final femea = a['sexo'] == 'F';
        return Scaffold(
          appBar: AppBar(
            title: Text(rotulo(a)),
            actions: [
              if (a['status'] == 'Ativo')
                IconButton(
                  tooltip: 'Ficha rápida (Modo Curral)',
                  icon: const Icon(Icons.contactless_outlined, color: Cores.laranja),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => FichaCurral(animalId: id))),
                ),
              if (a['status'] == 'Ativo')
                IconButton(
                  tooltip: 'Registrar venda ou saída',
                  icon: const Icon(Icons.sell_outlined),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => SaidaFormPage(animais: [a]))),
                ),
              if (a['status'] == 'Ativo')
                IconButton(
                  tooltip: 'Mudar de lote, piquete ou propriedade',
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => MoverAnimaisPage(animais: [a]))),
                ),
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => AnimalFormPage(animal: a))),
              ),
              IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await confirmar(
                    context,
                    'Excluir animal ${a['brinco']}?',
                    'Também serão apagadas as pesagens, reproduções e manejos sanitários deste animal. '
                        'Para venda ou morte, use "Saídas" em vez de excluir.',
                    ok: 'Excluir',
                  );
                  if (!ok || !context.mounted) return;
                  Navigator.pop(context);
                  await Db.excluir('animais', id);
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              FotoAnimal(animalId: id),
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Info('Situação', txt(a['status'])),
                      Info('Brinco eletrônico', txt(a['rfid'])),
                      Info('Número oficial', txt(a['sisbov'])),
                      Info('Sexo', femea ? 'Fêmea' : 'Macho'),
                      Info('Categoria', txt(a['categoria'])),
                      Info('Raça', txt(a['raca'])),
                      Info('Nascimento',
                          a['nascimento'] == null ? '' : '${br(a['nascimento'])} (${idade(a['nascimento'])})'),
                      Info('Lote', txt(a['lote_nome'])),
                      Info('Piquete/Pasto', txt(a['piquete_nome'])),
                      Info(
                        'Mãe',
                        txt(a['mae_brinco']),
                        onTap: a['mae_id'] == null
                            ? null
                            : () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => FichaAnimalPage(a['mae_id'] as int))),
                      ),
                      Info('Pai', txt(a['pai'])),
                      Info('Origem', txt(a['origem'])),
                      if (femea && partosDaVaca(id).isNotEmpty)
                        Info(
                          'Partos',
                          '${partosDaVaca(id).length}'
                              '${intervaloEntrePartos(id) == null ? '' : ' · intervalo médio de ${intervaloEntrePartos(id)!.round()} dias'}',
                        ),
                      if (f.saida != null)
                        Info('Saída',
                            '${f.saida!['tipo']} em ${br(f.saida!['data'])}${txt(f.saida!['destino']).isEmpty ? '' : ' – ${f.saida!['destino']}'}'),
                      Info('Observações', txt(a['obs'])),
                    ],
                  ),
                ),
              ),
              _secaoPesagens(context, f),
              if (femea) _secaoReproducao(context, f),
              _secaoGenealogia(context, a),
              if (f.filhos.isNotEmpty) ...[
                Secao('Crias (${f.filhos.length})'),
                for (final c in f.filhos) AnimalTile({...c, 'mae_brinco': a['brinco']}),
              ],
              _secaoSanidade(context, f),
            ],
          ),
        );
      },
    );
  }

  Widget _secaoGenealogia(BuildContext context, Reg a) {
    final g = Genealogia(a);
    Widget linha(String titulo, Reg? animal, {String? pai}) => Info(
          titulo,
          animal != null ? rotulo(animal) : txt(pai),
          onTap: animal == null
              ? null
              : () => Navigator.push(context, MaterialPageRoute(builder: (_) => FichaAnimalPage(animal['id'] as int))),
        );
    final parentes = g.tourosParentes;
    if (g.mae == null && parentes.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Secao('Genealogia'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          linha('Pai', null, pai: a['pai'] as String?),
          linha('Mãe', g.mae),
          linha('Avô materno', null, pai: g.mae?['pai'] as String?),
          linha('Avó materna', g.avo),
          linha('Bisavó materna', g.bisavo),
          if (a['sexo'] == 'F' && parentes.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text('Para evitar consanguinidade, não use sêmen de: '
                  '${parentes.entries.map((e) => '${e.key} (${e.value})').join(', ')}.'),
            ),
        ]),
      ),
    ]);
  }

  Widget _secaoPesagens(BuildContext context, _Ficha f) {
    final ps = [...f.pesagens]..sort((x, y) => txt(x['data']).compareTo(txt(y['data'])));
    String? resumo;
    if (ps.length >= 2) {
      final dias = diasEntre(txt(ps.first['data']), txt(ps.last['data']));
      if (dias > 0) {
        final ganho = (ps.last['peso'] as num) - (ps.first['peso'] as num);
        resumo = 'Ganho total ${kg(ganho)} em $dias dias · GMD ${gmd(ganho / dias)}';
      }
    }
    final desc = ps.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Secao(
          'Pesagens',
          acao: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Pesar'),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => PesagemFormPage(animal: f.a))),
          ),
        ),
        if (resumo != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(resumo)),
        if (desc.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Sem pesagens.')),
        for (var i = 0; i < desc.length; i++)
          ListTile(
            dense: true,
            leading: const Icon(Icons.monitor_weight_outlined),
            title: Text(kg(desc[i]['peso'] as num)),
            subtitle: Text('${br(desc[i]['data'])} · ${txt(desc[i]['evento'])}'),
            trailing: i + 1 < desc.length ? Text(_gmdEntre(desc[i + 1], desc[i])) : null,
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => PesagemFormPage(registro: desc[i]))),
          ),
      ],
    );
  }

  String _gmdEntre(Reg anterior, Reg atual) {
    final dias = diasEntre(txt(anterior['data']), txt(atual['data']));
    if (dias <= 0) return '';
    return gmd(((atual['peso'] as num) - (anterior['peso'] as num)) / dias);
  }

  Widget _secaoReproducao(BuildContext context, _Ficha f) {
    final aberta = f.reproducoes.where((r) => r['parto_data'] == null && r['diagnostico'] != 'Vazia');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Secao(
          'Reprodução',
          acao: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Serviço'),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ReproducaoFormPage(femea: f.a))),
          ),
        ),
        if (aberta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.child_friendly_outlined),
              label: const Text('Registrar parto'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NascimentoFormPage(mae: f.a, reproducao: aberta.first)),
              ),
            ),
          ),
        if (f.reproducoes.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Sem registros.')),
        for (final r in f.reproducoes) ReproducaoTile(r, mostrarFemea: false),
      ],
    );
  }

  Widget _secaoSanidade(BuildContext context, _Ficha f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Secao(
          'Sanidade',
          acao: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Manejo'),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => SanidadeFormPage(animal: f.a))),
          ),
        ),
        if (f.sanidade.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Sem registros.')),
        for (final s in f.sanidade)
          ListTile(
            dense: true,
            leading: const Icon(Icons.vaccines_outlined),
            title: Text('${s['produto']} (${txt(s['tipo'])})'),
            subtitle: Text([
              br(s['data']),
              if (txt(s['dose']).isNotEmpty) 'Dose ${s['dose']}',
              if (s['proxima'] != null) 'Próxima ${br(s['proxima'])}',
            ].join(' · ')),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmar(context, 'Excluir registro?', 'Remove só deste animal.', ok: 'Excluir')) {
                  await Db.excluir('sanidade', s['id'] as int);
                }
              },
            ),
          ),
      ],
    );
  }
}
