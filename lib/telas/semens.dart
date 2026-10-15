import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../util/util.dart';

/// Cadastro de sêmen (touros): partida, preço por dose e doses no botijão.
/// Cada partida do mesmo touro é um cadastro, com o estoque separado.
/// O Modo Inseminação dá baixa de uma dose a cada inseminação.
class SemensPage extends StatelessWidget {
  const SemensPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sêmen e touros')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Novo sêmen',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SemenFormPage())),
        child: const Icon(Icons.add, size: 32),
      ),
      body: AoMudar<List<Reg>>(
        carregar: Db.semens,
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio('Nenhum sêmen cadastrado.\nToque em + para cadastrar o touro, o preço da dose e as doses do botijão.',
                icone: Icons.science_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) => _SemenTile(lista[i]),
          );
        },
      ),
    );
  }
}

/// Resumo de uso do sêmen: "8 usadas · 5 prenhes · R$ 72,00/prenhez".
String usoSemen(Reg s) {
  final usadas = (s['usadas'] as num? ?? 0).toInt();
  final prenhes = (s['prenhes'] as num? ?? 0).toInt();
  final custo = (s['custo'] as num? ?? 0);
  return [
    '$usadas ${usadas == 1 ? 'usada' : 'usadas'}',
    '$prenhes ${prenhes == 1 ? 'prenhe' : 'prenhes'}',
    if (prenhes > 0 && custo > 0) '${moeda(custo / prenhes)}/prenhez',
  ].join(' · ');
}

class _SemenTile extends StatelessWidget {
  const _SemenTile(this.s);
  final Reg s;

  @override
  Widget build(BuildContext context) {
    final doses = (s['doses'] as num?)?.toInt() ?? 0;
    final linhas = [
      [
        if (txt(s['partida']).isNotEmpty) 'Partida ${s['partida']}',
        if (txt(s['raca']).isNotEmpty) txt(s['raca']),
        if (txt(s['central']).isNotEmpty) txt(s['central']),
      ].join(' · '),
      [if (s['preco_dose'] is num) '${moeda(s['preco_dose'] as num)}/dose', usoSemen(s)].join(' · '),
    ].where((l) => l.isNotEmpty).toList();
    return ListTile(
      leading: const Icon(Icons.science_outlined),
      title: Text(txt(s['touro']), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(linhas.join('\n')),
      isThreeLine: linhas.length > 1,
      trailing: Text(doses > 0 ? '$doses ${doses == 1 ? 'dose' : 'doses'}' : 'sem estoque',
          style: TextStyle(fontWeight: FontWeight.w700, color: doses > 0 ? null : Colors.red)),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SemenFormPage(semen: s))),
    );
  }
}

class SemenFormPage extends StatefulWidget {
  const SemenFormPage({super.key, this.semen});
  final Reg? semen;

  @override
  State<SemenFormPage> createState() => _SemenFormPageState();
}

class _SemenFormPageState extends State<SemenFormPage> {
  late final s = widget.semen;
  late final touro = TextEditingController(text: txt(s?['touro']));
  late final partida = TextEditingController(text: txt(s?['partida']));
  late final raca = TextEditingController(text: txt(s?['raca']));
  late final central = TextEditingController(text: txt(s?['central']));
  late final preco = TextEditingController(
      text: s?['preco_dose'] is num ? numeroBr((s!['preco_dose'] as num).toDouble(), casas: 2) : '');
  late final doses = TextEditingController(text: s?['doses'] == null ? '' : '${s!['doses']}');
  late final obs = TextEditingController(text: txt(s?['obs']));

  @override
  void dispose() {
    for (final c in [touro, partida, raca, central, preco, doses, obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (touro.text.trim().isEmpty) {
      avisar(context, 'Informe o nome do touro.');
      return;
    }
    await Db.salvarSemen({
      'touro': touro.text.trim(),
      'partida': nulo(partida.text),
      'raca': nulo(raca.text),
      'central': nulo(central.text),
      'preco_dose': lerNumero(preco.text),
      'doses': lerNumero(doses.text)?.round() ?? 0,
      'obs': nulo(obs.text),
    }, id: s?['id'] as int?);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    if (await confirmar(context, 'Excluir sêmen?',
        'O cadastro sai da lista. As inseminações já feitas continuam com o nome do touro.',
        ok: 'Excluir')) {
      await Db.excluir('semens', s!['id'] as int);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(s == null ? 'Novo sêmen' : 'Editar sêmen'),
        actions: [
          if (s != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      bottomNavigationBar: BotaoSalvar(onPressed: _salvar),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          campoTexto(touro, 'Touro *', foco: s == null),
          gap,
          campoTexto(partida, 'Partida'),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Partida diferente do mesmo touro? Cadastre de novo, para o estoque ficar separado.'),
          ),
          gap,
          campoTexto(raca, 'Raça'),
          gap,
          campoTexto(central, 'Central / fornecedor'),
          gap,
          campoTexto(preco, 'Preço por dose', numero: true, sufixo: 'R\$'),
          gap,
          campoTexto(doses, 'Doses no botijão', numero: true),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Cada inseminação no Modo Inseminação dá baixa de uma dose.'),
          ),
          if (s != null) ...[
            gap,
            Text(usoSemen(s!), style: Theme.of(context).textTheme.bodyLarge),
          ],
          gap,
          campoTexto(obs, 'Observações', linhas: 3),
        ],
      ),
    );
  }
}
