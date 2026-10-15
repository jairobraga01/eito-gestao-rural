import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/manejo.dart';
import '../dispositivos/leitor_teclado.dart';
import '../util/util.dart';
import '../widgets/teclado_grande.dart';

/// Lotes de vacas em protocolo de IATF, com a data de cada etapa.
class ProtocolosPage extends StatelessWidget {
  const ProtocolosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Protocolos de IATF')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Novo protocolo'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProtocoloFormPage())),
      ),
      body: AoMudar<List<Reg>>(
        carregar: Db.protocolos,
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio('Nenhum protocolo.\nToque em "Novo protocolo", escolha o D0 e leia os brincos das vacas.',
                icone: Icons.event_note);
          }
          final hoje = hojeIso();
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final p = lista[i];
              final etapas = [for (final e in (p['etapas'] as List?) ?? const []) Map<String, Object?>.from(e as Map)];
              final n = ((p['femeas'] as List?) ?? const []).length;
              return ListTile(
                leading: const Icon(Icons.event_note),
                title: Text('${p['nome']} · D0 ${br(p['inicio'])} · $n ${n == 1 ? 'vaca' : 'vacas'}'),
                subtitle: Text([
                  for (final e in etapas)
                    '${Db.dataEtapa(p['inicio'], e['dia']).compareTo(hoje) < 0 ? '✔' : '•'} '
                        'D${e['dia']} ${br(Db.dataEtapa(p['inicio'], e['dia']))}: ${e['nome']}',
                ].join('\n')),
                isThreeLine: true,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProtocoloFormPage(protocolo: p))),
              );
            },
          );
        },
      ),
    );
  }
}

class ProtocoloFormPage extends StatefulWidget {
  const ProtocoloFormPage({super.key, this.protocolo});
  final Reg? protocolo;

  @override
  State<ProtocoloFormPage> createState() => _ProtocoloFormPageState();
}

class _ProtocoloFormPageState extends State<ProtocoloFormPage> {
  late final p = widget.protocolo;
  late String nome = protocolosIatf.containsKey(p?['nome']) ? p!['nome'] as String : protocolosIatf.keys.first;
  late String inicio = (p?['inicio'] as String?) ?? hojeIso();
  late final List<Reg> vacas = [
    for (final id in (p?['femeas'] as List?) ?? const [])
      if (Db.registro('animais', id) case final a?) a,
  ];
  VoidCallback? _cancelarLeitor;

  @override
  void initState() {
    super.initState();
    _cancelarLeitor = LeitorTeclado.instancia.assinar((c) {
      if (!(ModalRoute.of(context)?.isCurrent ?? false) || parecePeso(c)) return;
      _adicionar(c);
    });
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    super.dispose();
  }

  Future<void> _adicionar(String codigo) async {
    final a = await Db.buscarPorCodigo(codigo);
    if (!mounted) return;
    if (a == null || a['status'] != 'Ativo' || a['sexo'] != 'F') {
      avisar(context, a == null ? 'Brinco $codigo não cadastrado.' : 'Brinco ${a['brinco']} não é fêmea ativa.');
      return;
    }
    if (vacas.any((v) => v['id'] == a['id'])) {
      avisar(context, 'Brinco ${a['brinco']} já está no protocolo.');
      return;
    }
    setState(() => vacas.add(a));
  }

  Future<void> _digitar() async {
    final c = await pedirNumero(context, titulo: 'Número do brinco');
    if (c != null && c.trim().isNotEmpty) _adicionar(c.trim());
  }

  Future<void> _escolher() async {
    final r = await pickAnimais(context, titulo: 'Vacas do protocolo', iniciais: [for (final v in vacas) v['id'] as int]);
    if (r == null) return;
    setState(() => vacas
      ..clear()
      ..addAll(r.where((a) => a['sexo'] == 'F')));
  }

  Future<void> _salvar() async {
    if (vacas.isEmpty) {
      avisar(context, 'Leia ou escolha as vacas.');
      return;
    }
    await Db.salvarProtocolo(
      id: p?['id'] as int?,
      nome: nome,
      inicio: inicio,
      etapas: [for (final (dia, n) in protocolosIatf[nome]!) {'dia': dia, 'nome': n}],
      femeas: [for (final v in vacas) v['id'] as int],
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    if (await confirmar(context, 'Excluir protocolo?', 'As inseminações já lançadas continuam.', ok: 'Excluir')) {
      await Db.excluir('protocolos', p!['id'] as int);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? 'Novo protocolo' : 'Protocolo'),
        actions: [
          if (p != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      bottomNavigationBar: BotaoSalvar(onPressed: _salvar),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        escolha('Protocolo', nome, protocolosIatf.keys.toList(), (v) => setState(() => nome = v!)),
        gap,
        DateField(label: 'D0 (início)', value: inicio, obrigatorio: true, onChanged: (v) => setState(() => inicio = v!)),
        gap,
        for (final (dia, n) in protocolosIatf[nome]!)
          ListTile(
            dense: true,
            leading: Text('D$dia', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            title: Text(n),
            trailing: Text(br(Db.dataEtapa(inicio, dia))),
          ),
        const Divider(),
        Text('${vacas.length} ${vacas.length == 1 ? 'vaca' : 'vacas'} · encoste o bastão no brinco para incluir',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in vacas)
            InputChip(label: Text(txt(v['brinco'])), onDeleted: () => setState(() => vacas.remove(v))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(onPressed: _digitar, icon: const Icon(Icons.dialpad), label: const Text('Digitar brinco')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(onPressed: _escolher, icon: const Icon(Icons.checklist), label: const Text('Escolher')),
          ),
        ]),
      ]),
    );
  }
}
