import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../util/util.dart';
import 'base.dart';

class SaidasPage extends StatelessWidget {
  const SaidasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Vendas e saídas',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Nova saída'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SaidaFormPage())),
      ),
      corpo: AoMudar<List<Reg>>(
        carregar: Db.saidas,
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio('Nenhuma venda ou saída registrada.', icone: Icons.sell_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final s = lista[i];
              final venda = s['tipo'] == 'Venda';
              return ListTile(
                leading: Icon(venda ? Icons.sell_outlined : Icons.logout),
                title: Text('${s['tipo']} · ${s['quantidade'] ?? 0} cab.'
                    '${venda && s['valor_total'] != null ? ' · ${moeda(s['valor_total'] as num)}' : ''}'),
                subtitle: Text([
                  br(s['data']),
                  if (txt(s['destino']).isNotEmpty) txt(s['destino']),
                  if (txt(s['brincos']).isNotEmpty) 'Brincos: ${s['brincos']}',
                ].join(' · ')),
                onTap: () => _detalhe(context, s),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _detalhe(BuildContext context, Reg s) async {
    final qtd = (s['quantidade'] as int?) ?? 0;
    final peso = s['peso_total'] as num?;
    final valor = s['valor_total'] as num?;
    final excluir = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${s['tipo']} de ${br(s['data'])}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Info('Cabeças', '$qtd'),
              Info('Peso total', kg(peso)),
              if (peso != null && qtd > 0) Info('Peso médio', kg(peso / qtd)),
              Info('Valor total', moeda(valor)),
              if (valor != null && qtd > 0) Info('Por cabeça', moeda(valor / qtd)),
              if (valor != null && peso != null && peso > 0) Info('Por kg vivo', moeda(valor / peso)),
              Info('Comprador / destino', txt(s['destino'])),
              Info('Brincos', txt(s['brincos'])),
              Info('Observações', txt(s['obs'])),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fechar')),
        ],
      ),
    );
    if (excluir != true || !context.mounted) return;
    if (await confirmar(context, 'Excluir saída?',
        'O registro será apagado e os animais voltarão a ficar ativos no rebanho.',
        ok: 'Excluir')) {
      await Db.excluirSaida(s['id'] as int);
    }
  }
}

class SaidaFormPage extends StatefulWidget {
  const SaidaFormPage({super.key, this.animais = const []});

  /// Animais já escolhidos (ex.: saída lançada da ficha ou do Modo Curral).
  final List<Reg> animais;

  @override
  State<SaidaFormPage> createState() => _SaidaFormPageState();
}

class _SaidaFormPageState extends State<SaidaFormPage> {
  String? tipo = 'Venda';
  String data = hojeIso();
  late List<Reg> animais = [...widget.animais];
  final peso = TextEditingController();
  final valor = TextEditingController();
  final destino = TextEditingController();
  final obs = TextEditingController();
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    peso.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [peso, valor, destino, obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolher() async {
    final r = await pickAnimais(context, iniciais: [for (final a in animais) a['id'] as int]);
    if (r != null) setState(() => animais = r);
  }

  void _somarUltimosPesos() {
    final pesos = animais.map((a) => a['ultimo_peso'] as num?).whereType<num>().toList();
    if (pesos.isEmpty) {
      avisar(context, 'Os animais escolhidos não têm pesagem.');
      return;
    }
    peso.text = num1(pesos.fold<num>(0, (a, b) => a + b));
    setState(() {});
    if (pesos.length < animais.length) {
      avisar(context, 'Somados ${pesos.length} de ${animais.length} (alguns sem pesagem).');
    }
  }

  Future<void> salvar() async {
    if (animais.isEmpty) {
      avisar(context, 'Selecione os animais.');
      return;
    }
    final ok = await confirmar(
      context,
      'Confirmar ${tipo!.toLowerCase()}',
      '${animais.length} animal(is) sairão do rebanho ativo.',
    );
    if (!ok) return;
    setState(() => salvando = true);
    await Db.registrarSaida({
      'tipo': tipo,
      'data': data,
      'peso_total': lerNumero(peso.text),
      'valor_total': tipo == 'Venda' ? lerNumero(valor.text) : null,
      'destino': nulo(destino.text),
      'obs': nulo(obs.text),
    }, [for (final a in animais) a['id'] as int]);
    if (!mounted) return;
    avisar(context, 'Saída registrada.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final venda = tipo == 'Venda';
    final p = lerNumero(peso.text);
    final v = lerNumero(valor.text);
    final n = animais.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Nova saída')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          escolha('Tipo', tipo, statusPorSaida.keys.toList(), (x) => setState(() => tipo = x)),
          gap,
          DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (x) => setState(() => data = x!)),
          gap,
          OutlinedButton.icon(
            icon: const Icon(Icons.checklist),
            label: Text(n == 0 ? 'Selecionar animais' : '$n animal(is) selecionado(s) – alterar'),
            onPressed: _escolher,
          ),
          if (n > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in animais)
                    InputChip(
                      label: Text(txt(a['brinco'])),
                      onDeleted: () => setState(() => animais = [...animais]..remove(a)),
                    ),
                ],
              ),
            ),
          gap,
          Row(
            children: [
              Expanded(child: campoTexto(peso, 'Peso total vivo', numero: true, sufixo: 'kg')),
              IconButton(
                tooltip: 'Somar últimas pesagens',
                icon: const Icon(Icons.functions),
                onPressed: n == 0 ? null : _somarUltimosPesos,
              ),
            ],
          ),
          if (venda) ...[
            gap,
            TextField(
              controller: valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor total', prefixText: r'R$ '),
              onChanged: (_) => setState(() {}),
            ),
          ],
          gap,
          campoTexto(destino, venda ? 'Comprador' : 'Destino / causa'),
          gap,
          campoTexto(obs, 'Observações', linhas: 3),
          if (venda && v != null && n > 0)
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Info('Por cabeça', moeda(v / n)),
                    if (p != null && p > 0) Info('Por kg vivo', moeda(v / p)),
                    if (p != null && p > 0) Info('Peso médio', kg(p / n)),
                  ],
                ),
              ),
            ),
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
