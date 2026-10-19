// Atividade rural do Imposto de Renda: os quadros que o contador digita no
// programa da Receita, com a planilha para baixar.
import 'package:flutter/material.dart';

import '../dados/imposto_renda.dart';
import '../util/util.dart';
import 'financeiro.dart' show DadosLcdprPage, entregarArquivo;

class ImpostoRendaPage extends StatefulWidget {
  const ImpostoRendaPage({super.key});

  @override
  State<ImpostoRendaPage> createState() => _ImpostoRendaPageState();
}

class _ImpostoRendaPageState extends State<ImpostoRendaPage> {
  // A declaração entregue neste ano é a do ano passado.
  int ano = DateTime.now().year - 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Imposto de Renda · Atividade rural'), actions: [
        IconButton(
          tooltip: 'Baixar a planilha',
          icon: const Icon(Icons.download_outlined),
          onPressed: () => entregarArquivo(context, 'IRPF_atividade_rural_$ano.csv', planilhaAtividadeRural(ano)),
        ),
      ]),
      body: AoMudar<AtividadeRuralIr>(
        carregar: () async => atividadeRural(ano),
        builder: (context, a) {
          final r = a.rebanho;
          const negrito = TextStyle(fontWeight: FontWeight.w700);
          Widget valor(String rotulo, String v, {bool forte = false}) => ListTile(
                dense: true,
                title: Text(rotulo, style: forte ? negrito : null),
                trailing: Text(v, style: forte ? negrito : null),
              );
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => ano--)),
              Text('Ano-calendário $ano', style: Theme.of(context).textTheme.titleLarge),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => ano++)),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Declaração de ${ano + 1}. Junta todas as propriedades e segue os quadros do programa da Receita.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            if (a.avisos.isNotEmpty)
              Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Conferir antes de declarar', style: negrito),
                    for (final x in a.avisos) Text('• $x'),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DadosLcdprPage())),
                        child: const Text('Dados do produtor e do imóvel'),
                      ),
                    ),
                  ]),
                ),
              ),
            const Secao('Dados e identificação do imóvel'),
            for (final p in a.imoveis)
              ListTile(
                dense: true,
                title: Text(txt(p['nome'])),
                subtitle: Text([
                  'NIRF/CIB ${txt(p['lcdpr_cod_itr']).isEmpty ? '-' : p['lcdpr_cod_itr']}',
                  condicoesExploracao[p['lcdpr_exploracao'] is num ? (p['lcdpr_exploracao'] as num).toInt() : 1] ?? '',
                  if (p['lcdpr_participacao'] is num) 'participação ${num1(p['lcdpr_participacao'] as num)}%',
                ].join(' · ')),
              ),
            const Secao('Receitas e despesas'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Table(
                columnWidths: const {0: FlexColumnWidth(1.2)},
                children: [
                  const TableRow(children: [
                    Text('Mês', style: negrito),
                    Text('Receita', style: negrito, textAlign: TextAlign.right),
                    Text('Despesas', style: negrito, textAlign: TextAlign.right),
                  ]),
                  for (final m in a.meses)
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(nomeMes(m.mes))),
                      Text(moeda(m.receita), textAlign: TextAlign.right),
                      Text(moeda(m.despesas), textAlign: TextAlign.right),
                    ]),
                  TableRow(children: [
                    const Text('Total', style: negrito),
                    Text(moeda(a.receitaBruta), style: negrito, textAlign: TextAlign.right),
                    Text(moeda(a.despesas), style: negrito, textAlign: TextAlign.right),
                  ]),
                ],
              ),
            ),
            if (a.investimento > 0) valor('Dos quais investimentos', moeda(a.investimento)),
            const Secao('Apuração do resultado'),
            valor('Receita bruta total', moeda(a.receitaBruta)),
            valor('Despesas de custeio e investimentos', moeda(a.despesas)),
            valor('Resultado I', moeda(a.resultadoReal), forte: true),
            valor('20% da receita bruta', moeda(a.resultadoArbitrado)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                a.receitaBruta <= 0
                    ? 'Sem receita no ano.'
                    : a.compensaArbitrar
                        ? 'O lucro passou de 20% da receita: a opção pelo arbitramento (20%) dá menos imposto, mas perde o prejuízo a compensar.'
                        : 'O resultado real é menor que 20% da receita: declare pelo resultado real.',
              ),
            ),
            const Secao('Movimentação do rebanho (bovinos)'),
            valor('Estoque inicial', '${r.estoqueInicial}'),
            valor('Aquisições no ano', '${r.aquisicoes}'),
            valor('Nascidos no ano', '${r.nascimentos}'),
            if (r.outrasEntradas > 0) valor('Outras entradas', '${r.outrasEntradas}'),
            valor('Consumo e perdas', '${r.consumoPerdas}'),
            valor('Vendas no ano', '${r.vendas}'),
            valor('Estoque final', '${r.estoqueFinal}', forte: true),
            const Secao('Bens da atividade rural'),
            if (a.bens.isEmpty)
              const ListTile(dense: true, title: Text('Nenhum bem lançado no Patrimônio.')),
            for (final b in a.bens) valor('${txt(b['nome'])} (${txt(b['tipo'])})', moeda(b['valor'] as num?)),
            const Secao('Dívidas vinculadas à atividade rural'),
            if (a.dividas.isEmpty) const ListTile(dense: true, title: Text('Nenhuma dívida no período.')),
            for (final d in a.dividas)
              ListTile(
                dense: true,
                title: Text(d.discriminacao),
                subtitle: Text('31/12/${ano - 1}: ${moeda(d.saldoAnterior)} · 31/12/$ano: ${moeda(d.saldoAtual)}'
                    ' · pago no ano: ${moeda(d.pagoNoAno)}'),
              ),
          ]);
        },
      ),
    );
  }
}
