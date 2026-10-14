import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../util/util.dart';
import 'base.dart';

const atividadesPropriedade = ['Cria', 'Recria', 'Engorda', 'Ciclo completo', 'Leite', 'Agricultura'];

class PropriedadesPage extends StatelessWidget {
  const PropriedadesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Propriedades',
      fab: FloatingActionButton(
        heroTag: null,
        tooltip: 'Adicionar propriedade',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PropriedadeFormPage())),
        child: const Icon(Icons.add),
      ),
      corpo: AoMudar<List<Reg>>(
        carregar: Db.propriedades,
        builder: (context, lista) => ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: lista.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (c, i) {
            final p = lista[i];
            final atual = p['id'] == Db.pid;
            final area = [p['area_pastagem'], p['area_benfeitoria'], p['area_app'], p['area_agricultura']]
                .whereType<num>()
                .fold<num>(0, (a, b) => a + b);
            return ListTile(
              leading: Icon(Icons.home_work_outlined,
                  color: atual ? Theme.of(context).colorScheme.primary : null),
              title: Text(txt(p['nome']).toUpperCase()),
              subtitle: Text([
                '${p['qtd']} animal(is)',
                if (area > 0) '${num1(area)} ha',
                if (txt(p['uf']).isNotEmpty) txt(p['uf']),
                if (txt(p['atividades']).isNotEmpty) txt(p['atividades']),
              ].join(' · ')),
              trailing: atual
                  ? const Chip(label: Text('Atual'))
                  : TextButton(
                      onPressed: () => Db.selecionarPropriedade(p['id'] as int),
                      child: const Text('Usar'),
                    ),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => PropriedadeFormPage(propriedade: p))),
            );
          },
        ),
      ),
    );
  }
}

class PropriedadeFormPage extends StatefulWidget {
  const PropriedadeFormPage({super.key, this.propriedade});
  final Reg? propriedade;

  @override
  State<PropriedadeFormPage> createState() => _PropriedadeFormPageState();
}

class _PropriedadeFormPageState extends State<PropriedadeFormPage> {
  late final p = widget.propriedade;
  late final nome = TextEditingController(text: txt(p?['nome']));
  late final pastagem = TextEditingController(text: _n(p?['area_pastagem']));
  late final benfeitoria = TextEditingController(text: _n(p?['area_benfeitoria']));
  late final app = TextEditingController(text: _n(p?['area_app']));
  late final agricultura = TextEditingController(text: _n(p?['area_agricultura']));
  late final obs = TextEditingController(text: txt(p?['obs']));
  late String? uf = p?['uf'] as String?;
  late final atividades = txt(p?['atividades']).split(', ').where((x) => x.isNotEmpty).toSet();

  static String _n(Object? v) => v is num ? num1(v) : '';

  @override
  void dispose() {
    for (final c in [nome, pastagem, benfeitoria, app, agricultura, obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> salvar() async {
    if (nome.text.trim().isEmpty) {
      avisar(context, 'Informe o nome da propriedade.');
      return;
    }
    if (uf == null) {
      avisar(context, 'Escolha a UF.');
      return;
    }
    if (atividades.isEmpty) {
      avisar(context, 'Escolha ao menos uma atividade.');
      return;
    }
    await Db.salvarPropriedade({
      'nome': nome.text.trim(),
      'area_pastagem': lerNumero(pastagem.text),
      'area_benfeitoria': lerNumero(benfeitoria.text),
      'area_app': lerNumero(app.text),
      'area_agricultura': lerNumero(agricultura.text),
      'uf': uf,
      'atividades': [for (final a in atividadesPropriedade) if (atividades.contains(a)) a].join(', '),
      'obs': nulo(obs.text),
    }, id: p?['id'] as int?);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> excluir() async {
    final todas = await Db.propriedades();
    if (!mounted) return;
    if (todas.length <= 1) {
      avisar(context, 'É preciso ter ao menos uma propriedade.');
      return;
    }
    final ok = await confirmar(
      context,
      'Excluir ${p!['nome']}?',
      'Todos os animais, lotes, piquetes e registros desta propriedade serão apagados. Isso não pode ser desfeito.',
      ok: 'Excluir tudo',
    );
    if (!ok) return;
    await Db.excluirPropriedade(p!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  Widget _area(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: 'ha', prefixIcon: const Icon(Icons.open_in_full)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? 'ADICIONAR PROPRIEDADE' : 'EDITAR PROPRIEDADE'),
        actions: [
          if (p != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: excluir),
        ],
      ),
      bottomNavigationBar: BotaoSalvar(onPressed: salvar),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nome,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome da propriedade *', prefixIcon: Icon(Icons.home_work_outlined)),
          ),
          gap,
          _area(pastagem, 'Área de pastagem'),
          gap,
          _area(benfeitoria, 'Área de benfeitoria'),
          gap,
          _area(app, 'Área de reserva / APP'),
          gap,
          _area(agricultura, 'Área de agricultura'),
          gap,
          escolha('UF *', uf, ufs, (v) => setState(() => uf = v)),
          const SizedBox(height: 16),
          Text('Atividades *', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final a in atividadesPropriedade)
                FilterChip(
                  label: Text(a),
                  selected: atividades.contains(a),
                  onSelected: (v) => setState(() => v ? atividades.add(a) : atividades.remove(a)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          campoTexto(obs, 'Anotações', linhas: 3),
        ],
      ),
    );
  }
}
