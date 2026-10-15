import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/manejo.dart';
import '../util/util.dart';

/// Quando cada lote chega ao peso de venda, pelo GMD, e quanto vale na arroba informada.
class ProjecaoAbatePage extends StatefulWidget {
  const ProjecaoAbatePage({super.key});

  @override
  State<ProjecaoAbatePage> createState() => _ProjecaoAbatePageState();
}

class _ProjecaoAbatePageState extends State<ProjecaoAbatePage> {
  static Reg get _salvo => Db.registro('config', 'abate') ?? const {};
  late final alvo = TextEditingController(text: _num(_salvo['alvo'], '540'));
  late final rendimento = TextEditingController(text: _num(_salvo['rendimento'], '52'));
  late final arroba = TextEditingController(text: _num(_salvo['arroba'], ''));

  static String _num(Object? v, String padrao) => v is num ? numeroBr(v.toDouble(), casas: v % 1 == 0 ? 0 : 2) : padrao;

  @override
  void dispose() {
    for (final c in [alvo, rendimento, arroba]) {
      c.dispose();
    }
    super.dispose();
  }

  void _mudou() {
    setState(() {});
    Db.salvarConfig('abate', {
      'alvo': lerNumero(alvo.text),
      'rendimento': lerNumero(rendimento.text),
      'arroba': lerNumero(arroba.text),
    });
  }

  Widget _campo(TextEditingController c, String rotulo, {String? sufixo, String? prefixo}) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _mudou(),
          decoration: InputDecoration(labelText: rotulo, suffixText: sufixo, prefixText: prefixo),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pesoAlvo = lerNumero(alvo.text) ?? 0;
    final rend = (lerNumero(rendimento.text) ?? 52) / 100;
    final preco = lerNumero(arroba.text);
    final hoje = hojeIso();
    return Scaffold(
      appBar: AppBar(title: const Text('Projeção de abate')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            _campo(alvo, 'Peso de venda', sufixo: 'kg'),
            const SizedBox(width: 12),
            _campo(rendimento, 'Rendimento', sufixo: '%'),
            const SizedBox(width: 12),
            _campo(arroba, 'Arroba', prefixo: r'R$ '),
          ]),
        ),
        if (pesoAlvo <= 0)
          const Vazio('Informe o peso de venda.')
        else
          AoMudar<List<ProjecaoLote>>(
            carregar: () async => projecaoAbate(pesoAlvo),
            builder: (context, lotes) {
              if (lotes.isEmpty) {
                return const Vazio('Nenhum animal ativo com pesagem.', icone: Icons.monitor_weight_outlined);
              }
              return Column(children: [
                for (final l in lotes) _lote(l, pesoAlvo, rend, preco, hoje),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'GMD de cada animal da primeira à última pesagem. Valor = peso × rendimento ÷ 15 kg × arroba.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ]);
            },
          ),
      ]),
    );
  }

  Widget _lote(ProjecaoLote l, double alvo, double rend, double? preco, String hoje) {
    final n = l.animais.length;
    final g = l.gmdMedio;
    final dias = l.diasMediana;
    final valorHoje = preco == null ? null : l.animais.fold<double>(0, (s, a) => s + valorArroba(a.peso, rend, preco));
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: Text('${l.nome} · $n cab.', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          'Peso médio ${kg(l.pesoMedio)}${g == null ? '' : ' · GMD ${gmd(g)}'}',
          l.prontos == n
              ? 'Todos no peso'
              : dias == null
                  ? 'Sem GMD para projetar (faltam pesagens)'
                  : 'Metade no peso em ${br(somaDias(hoje, dias))} ($dias dias)${l.prontos > 0 ? ' · ${l.prontos} já no peso' : ''}',
          if (preco != null) 'Vale hoje ${moeda(valorHoje)} · no peso ${moeda(n * valorArroba(alvo, rend, preco))}',
        ].join('\n')),
        children: [
          for (final a in l.animais)
            ListTile(
              dense: true,
              title: Text(rotulo(a.animal)),
              subtitle: Text('${kg(a.peso)}${a.gmd == null ? '' : ' · ${gmd(a.gmd!)}'}'),
              trailing: Text(a.dias == 0
                  ? 'no peso'
                  : a.dias == null
                      ? '-'
                      : br(somaDias(hoje, a.dias!))),
            ),
        ],
      ),
    );
  }
}
