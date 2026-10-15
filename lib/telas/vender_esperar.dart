import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/estoque.dart';
import '../dados/gestao.dart' show ajustesArroba;
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';

/// Vender agora ou esperar: por lote, quanto o gado ganha de peso em 30, 60 e
/// 90 dias, quanto custa mantê-lo e o resultado em reais.
class VenderEsperarPage extends StatefulWidget {
  const VenderEsperarPage({super.key});

  @override
  State<VenderEsperarPage> createState() => _VenderEsperarPageState();
}

class _VenderEsperarPageState extends State<VenderEsperarPage> {
  static Reg get _salvo => Db.registro('config', 'abate') ?? const {};
  static String _n(Object? v) => v is num ? numeroBr(v.toDouble(), casas: v % 1 == 0 ? 0 : 2) : '';
  late final arroba = TextEditingController(text: _n(ajustesArroba().$2));
  late final custoFixo = TextEditingController(text: _n(_salvo['custo_fixo_dia']));
  late final variacao = TextEditingController(text: _n(_salvo['variacao_arroba']));

  @override
  void dispose() {
    for (final c in [arroba, custoFixo, variacao]) {
      c.dispose();
    }
    super.dispose();
  }

  void _mudou() {
    setState(() {});
    Db.salvarConfig('abate', {
      ...?Db.registro('config', 'abate'),
      'custo_fixo_dia': lerNumero(custoFixo.text),
      'variacao_arroba': lerNumero(variacao.text),
    }..remove('id'));
  }

  Widget _campo(TextEditingController c, String rotulo, {String? prefixo, String? sufixo, bool salvar = true}) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          onChanged: (_) => salvar ? _mudou() : setState(() {}),
          decoration: InputDecoration(labelText: rotulo, prefixText: prefixo, suffixText: sufixo),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lotes = venderOuEsperar(
      arroba: lerNumero(arroba.text),
      custoFixoDia: lerNumero(custoFixo.text) ?? 0,
      variacaoArroba: lerNumero(variacao.text) ?? 0,
    );
    return Pagina(
      titulo: 'Vender ou esperar',
      corpo: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              _campo(arroba, 'Arroba hoje', prefixo: r'R$ ', salvar: false),
              const SizedBox(width: 12),
              _campo(variacao, 'Arroba em 90 dias', sufixo: '%'),
            ]),
            gap,
            Row(children: [
              _campo(custoFixo, 'Outros custos por cabeça/dia', prefixo: r'R$ '),
            ]),
            const SizedBox(height: 8),
            const Text('O custo diário soma a dieta do cocho do lote e os outros custos (pasto, mão de obra). '
                'O peso futuro sai do GMD das pesagens. A arroba vem da última cotação lançada.'),
          ]),
        ),
        if (lotes.isEmpty)
          const Vazio('Lance a arroba em Cotação da arroba e pese os animais para ver a conta.', icone: Icons.balance),
        for (final l in lotes) _LoteVenda(l),
      ]),
    );
  }
}

class _LoteVenda extends StatelessWidget {
  const _LoteVenda(this.l);
  final VendaLote l;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final melhor = l.melhor;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${l.lote} · ${l.cabecas} cab.', style: tema.titleMedium),
          Text('Peso médio ${kg(l.peso)} · GMD ${l.gmd == null ? '-' : gmd(l.gmd!)} · '
              'custo ${moeda(l.custoDia)}/cab/dia'),
          Text('Vendendo hoje: ${moeda(l.valorHoje)} por cabeça · ${moeda(l.valorHoje * l.cabecas)} o lote'),
          const SizedBox(height: 8),
          if (l.cenarios.isEmpty)
            const Text('Sem GMD: pese de novo para comparar.')
          else ...[
            Table(
              columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.6), 3: FlexColumnWidth(1.6)},
              children: [
                const TableRow(children: [
                  Text('Esperar', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Peso', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Ganho/cab.', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Empata com @', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold)),
                ]),
                for (final c in l.cenarios)
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('${c.dias} dias')),
                    Text(kg(c.peso), textAlign: TextAlign.right),
                    Text(moeda(c.ganho),
                        textAlign: TextAlign.right, style: TextStyle(color: c.ganho >= 0 ? Cores.sucesso : Cores.alerta)),
                    Text(moeda(c.arrobaEmpate), textAlign: TextAlign.right),
                  ]),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (melhor == 0 ? Cores.alerta : Cores.sucesso).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                melhor == 0
                    ? 'Vender agora: esperar custa mais do que o boi engorda.'
                    : 'Esperar $melhor dias: ganha ${moeda(l.cenarios.firstWhere((c) => c.dias == melhor).ganho * l.cabecas)} no lote.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
