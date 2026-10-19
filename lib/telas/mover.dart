// Mudar animais de lote, piquete ou propriedade, e migrar a categoria de um lote inteiro.
import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../util/util.dart';
import 'sanidade.dart' show Segmentos;

const _manter = -1;
const _nenhum = 0;

/// Lista suspensa com "Manter como está", "Nenhum" e os registros.
Widget _destino(String label, int valor, List<Reg> itens, ValueChanged<int> onChanged,
    {required bool podeManter, required String nenhum}) {
  final opcoes = <int>[if (podeManter) _manter, _nenhum, for (final e in itens) e['id'] as int];
  return DropdownButtonFormField<int>(
    key: ValueKey('$label|$valor|${opcoes.join(',')}'),
    initialValue: opcoes.contains(valor) ? valor : _nenhum,
    decoration: InputDecoration(labelText: label),
    items: [
      if (podeManter) const DropdownMenuItem(value: _manter, child: Text('Manter como está')),
      DropdownMenuItem(value: _nenhum, child: Text(nenhum)),
      for (final e in itens) DropdownMenuItem(value: e['id'] as int, child: Text(txt(e['nome']))),
    ],
    onChanged: (v) => onChanged(v ?? _nenhum),
  );
}

class MoverAnimaisPage extends StatefulWidget {
  const MoverAnimaisPage({super.key, required this.animais});
  final List<Reg> animais;

  @override
  State<MoverAnimaisPage> createState() => _MoverAnimaisPageState();
}

class _MoverAnimaisPageState extends State<MoverAnimaisPage> {
  late List<Reg> animais = widget.animais;
  List<Reg> propriedades = [], lotes = [], piquetes = [];
  late int propId = Db.pid;
  int lote = _manter, piquete = _manter;
  String data = hojeIso();
  bool salvando = false;

  bool get mesmaPropriedade => propId == Db.pid;

  @override
  void initState() {
    super.initState();
    Db.propriedades().then((v) {
      if (mounted) setState(() => propriedades = v);
    });
    _carregarDestinos();
  }

  Future<void> _carregarDestinos() async {
    final l = await Db.lotes(soAtivos: true, propriedadeId: propId);
    final p = await Db.piquetes(propriedadeId: propId);
    if (!mounted) return;
    setState(() {
      lotes = l;
      piquetes = p;
      if (!mesmaPropriedade) {
        if (lote == _manter) lote = _nenhum;
        if (piquete == _manter) piquete = _nenhum;
      }
    });
  }

  String _resumoAtual(String chave) {
    final nomes = animais.map((a) => txt(a[chave]).isEmpty ? 'nenhum' : txt(a[chave])).toSet();
    return nomes.length == 1 ? nomes.first : '${nomes.length} diferentes';
  }

  Future<void> salvar() async {
    if (animais.isEmpty) {
      avisar(context, 'Nenhum animal selecionado.');
      return;
    }
    final m = <String, Object?>{};
    if (!mesmaPropriedade) m['propriedade_id'] = propId;
    if (lote != _manter) m['lote_id'] = lote == _nenhum ? null : lote;
    if (piquete != _manter) m['piquete_id'] = piquete == _nenhum ? null : piquete;
    if (m.isEmpty) {
      avisar(context, 'Escolha para onde os animais vão.');
      return;
    }
    if (!mesmaPropriedade) {
      final nome = txt(propriedades.where((p) => p['id'] == propId).firstOrNull?['nome']);
      if (!await confirmar(context, 'Transferir para $nome?',
          '${animais.length} animal(is) passam para outra propriedade, com todo o histórico. '
              'Eles deixam de aparecer nesta propriedade.',
          ok: 'Transferir')) {
        return;
      }
    }
    setState(() => salvando = true);
    await Db.moverAnimais(animais, m, data);
    if (!mounted) return;
    avisar(context, '${animais.length} animal(is) movido(s).');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MOVER ANIMAIS')),
      bottomNavigationBar: BotaoSalvar(onPressed: salvando ? null : salvar, texto: 'Mover'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${animais.length} animal(is)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final a in animais)
              InputChip(
                label: Text(txt(a['brinco'])),
                onDeleted: animais.length == 1 ? null : () => setState(() => animais = [...animais]..remove(a)),
              ),
          ]),
          const SizedBox(height: 8),
          Text('Hoje: lote ${_resumoAtual('lote_nome')} · piquete ${_resumoAtual('piquete_nome')}'),
          const SizedBox(height: 20),
          escolhaId('Propriedade', propId, propriedades, (v) {
            if (v == null) return;
            setState(() => propId = v);
            _carregarDestinos();
          }, vazio: '—'),
          gap,
          _destino('Lote', lote, lotes, (v) => setState(() => lote = v),
              podeManter: mesmaPropriedade, nenhum: 'Sem lote'),
          gap,
          _destino('Piquete/Pasto', piquete, piquetes, (v) => setState(() => piquete = v),
              podeManter: mesmaPropriedade, nenhum: 'Fora de piquete'),
          gap,
          DateField(label: 'Data da mudança', value: data, obrigatorio: true,
              onChanged: (v) => setState(() => data = v!)),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('A entrada e a saída de piquete ficam registradas no histórico de pastagem.'),
          ),
        ],
      ),
    );
  }
}

// ======================= Migrar lote =======================

/// Passagens comuns de categoria.
const passagens = <(String, String)>[
  ('Bezerra', 'Novilha'),
  ('Novilha', 'Vaca'),
  ('Bezerro', 'Garrote'),
  ('Garrote', 'Boi'),
  ('Garrote', 'Touro'),
];

class MigrarLotePage extends StatefulWidget {
  const MigrarLotePage({super.key, required this.lote});
  final Reg lote;

  @override
  State<MigrarLotePage> createState() => _MigrarLotePageState();
}

class _MigrarLotePageState extends State<MigrarLotePage> {
  Map<String, int> porCategoria = {};
  List<Reg> outrosLotes = [];
  String? de;
  String? para;
  String destino = 'mesmo';
  int? outroLote;
  final novoLote = TextEditingController();
  String data = hojeIso();
  bool salvando = false;

  int get loteId => widget.lote['id'] as int;

  @override
  void initState() {
    super.initState();
    Db.animais(loteId: loteId, soAtivos: true).then((v) {
      final c = <String, int>{};
      for (final a in v) {
        final k = txt(a['categoria']).isEmpty ? 'Sem categoria' : txt(a['categoria']);
        c[k] = (c[k] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        porCategoria = c;
        final sugestao = passagens.where((p) => c.containsKey(p.$1)).firstOrNull;
        if (sugestao != null) _usar(sugestao);
      });
    });
    Db.lotes(soAtivos: true).then((v) {
      if (mounted) setState(() => outrosLotes = v.where((l) => l['id'] != loteId).toList());
    });
  }

  @override
  void dispose() {
    novoLote.dispose();
    super.dispose();
  }

  void _usar((String, String) p) {
    de = p.$1;
    para = p.$2;
    if (novoLote.text.isEmpty || passagens.any((x) => novoLote.text == x.$2.toUpperCase())) {
      novoLote.text = p.$2.toUpperCase();
    }
  }

  int get afetados => de == null
      ? porCategoria.values.fold(0, (a, b) => a + b)
      : (porCategoria[de] ?? 0);

  Future<void> salvar() async {
    if (para == null) {
      avisar(context, 'Escolha a nova categoria.');
      return;
    }
    if (afetados == 0) {
      avisar(context, 'Nenhum animal ativo com essa categoria no lote.');
      return;
    }
    if (destino == 'outro' && outroLote == null) {
      avisar(context, 'Escolha o lote de destino.');
      return;
    }
    if (destino == 'novo' && novoLote.text.trim().isEmpty) {
      avisar(context, 'Informe o nome do novo lote.');
      return;
    }
    if (!await confirmar(context, 'Migrar $afetados animal(is)?',
        '${de ?? 'Todos os animais'} → $para'
            '${destino == 'novo' ? ', no novo lote ${novoLote.text.trim()}' : ''}'
            '${destino == 'outro' ? ', no lote ${txt(outrosLotes.firstWhere((l) => l['id'] == outroLote)['nome'])}' : ''}.')) {
      return;
    }
    setState(() => salvando = true);
    final n = await Db.migrarLote(
      loteId: loteId,
      deCategoria: de == 'Sem categoria' ? '' : de,
      paraCategoria: para!,
      destinoLoteId: destino == 'outro' ? outroLote : null,
      novoLote: destino == 'novo' ? novoLote.text.trim() : null,
      data: data,
    );
    if (!mounted) return;
    avisar(context, '$n animal(is) passaram para $para.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final categorias = [...categoriasF, ...categoriasM];
    return Scaffold(
      appBar: AppBar(title: const Text('MIGRAR LOTE')),
      bottomNavigationBar: BotaoSalvar(onPressed: salvando ? null : salvar, texto: 'Migrar'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(txt(widget.lote['nome']).toUpperCase(), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(porCategoria.isEmpty
              ? 'Nenhum animal ativo neste lote.'
              : porCategoria.entries.map((e) => '${e.value} ${e.key.toLowerCase()}').join(' · ')),
          const Secao('Atalhos'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in passagens)
              ChoiceChip(
                label: Text('${p.$1}s → ${p.$2}s'),
                selected: de == p.$1 && para == p.$2,
                onSelected: (_) => setState(() => _usar(p)),
              ),
          ]),
          const SizedBox(height: 16),
          escolha('Quais animais', de ?? 'Todos do lote', ['Todos do lote', ...porCategoria.keys],
              (v) => setState(() => de = v == 'Todos do lote' ? null : v)),
          gap,
          escolha('Nova categoria *', para, categorias, (v) => setState(() => para = v)),
          if (afetados > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 12),
              child: Text('$afetados animal(is) serão migrados.'),
            ),
          const SizedBox(height: 20),
          Text('Depois da migração, os animais ficam:', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Segmentos(
            opcoes: const ['NESTE LOTE', 'LOTE NOVO', 'OUTRO LOTE'],
            selecionado: const ['mesmo', 'novo', 'outro'].indexOf(destino),
            altura: 40,
            onChanged: (i) => setState(() => destino = const ['mesmo', 'novo', 'outro'][i]),
          ),
          const SizedBox(height: 12),
          if (destino == 'novo') campoTexto(novoLote, 'Nome do novo lote *'),
          if (destino == 'outro')
            escolhaId('Lote de destino *', outroLote, outrosLotes, (v) => setState(() => outroLote = v),
                vazio: 'Escolha'),
          gap,
          DateField(label: 'Data da migração', value: data, obrigatorio: true,
              onChanged: (v) => setState(() => data = v!)),
        ],
      ),
    );
  }
}

/// Muda todos os animais de um piquete/pasto para outro de uma vez.
class MudarPastoPage extends StatefulWidget {
  const MudarPastoPage({super.key, this.origem, this.destino});

  /// Piquete de onde os animais saem (já escolhido ao abrir pelo piquete).
  final int? origem;

  /// Piquete sugerido para receber (ex.: o que descansou mais).
  final int? destino;

  @override
  State<MudarPastoPage> createState() => _MudarPastoPageState();
}

class _MudarPastoPageState extends State<MudarPastoPage> {
  List<Reg> piquetes = [];
  late int? origem = widget.origem;
  late int? destino = widget.destino;
  String data = hojeIso();
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    Db.piquetes().then((v) {
      if (!mounted) return;
      setState(() => piquetes = [for (final p in v) {...p, 'rotulo': '${txt(p['nome'])} (${p['qtd']} cab.)'}]);
    });
  }

  String _nome(int? id) => txt(piquetes.where((p) => p['id'] == id).firstOrNull?['nome']);

  int get _qtd => (piquetes.where((p) => p['id'] == origem).firstOrNull?['qtd'] as int?) ?? 0;

  Future<void> salvar() async {
    if (origem == null || destino == null) {
      avisar(context, 'Escolha o piquete de origem e o de destino.');
      return;
    }
    if (origem == destino) {
      avisar(context, 'O destino precisa ser outro piquete.');
      return;
    }
    final animais = await Db.animais(piqueteId: origem, soAtivos: true);
    if (!mounted) return;
    if (animais.isEmpty) {
      avisar(context, 'Não há animais em ${_nome(origem)}.');
      return;
    }
    if (!await confirmar(context, 'Mudar ${animais.length} animal(is)?',
        'Todos saem de ${_nome(origem)} e entram em ${_nome(destino)} em ${br(data)}.',
        ok: 'Mudar')) {
      return;
    }
    setState(() => salvando = true);
    await Db.moverAnimais(animais, {'piquete_id': destino}, data);
    if (!mounted) return;
    avisar(context, '${animais.length} animal(is) foram para ${_nome(destino)}.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MUDAR DE PASTO')),
      bottomNavigationBar: BotaoSalvar(onPressed: salvando ? null : salvar, texto: 'Mudar todos'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Leva todos os animais ativos de um piquete/pasto para outro. '
              'A saída e a entrada ficam no histórico de pastagem dos dois.'),
          gap,
          escolhaId('Sai de (piquete/pasto) *', origem, piquetes, (v) => setState(() => origem = v),
              vazio: 'Escolha', campo: 'rotulo'),
          if (origem != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 12),
              child: Text('$_qtd animal(is) serão mudados.'),
            ),
          gap,
          escolhaId('Vai para (piquete/pasto) *', destino, piquetes.where((p) => p['id'] != origem).toList(),
              (v) => setState(() => destino = v),
              vazio: 'Escolha', campo: 'rotulo'),
          gap,
          DateField(label: 'Data da mudança', value: data, obrigatorio: true,
              onChanged: (v) => setState(() => data = v!)),
        ],
      ),
    );
  }
}
