import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dados/indicadores.dart';
import '../util/util.dart';

String _pct(double? v) => v == null ? '-' : '${(v * 100).round()}%';

/// Rebanho ativo por faixa de idade e sexo, como pedem as declarações estaduais.
class DeclaracaoRebanhoPage extends StatefulWidget {
  const DeclaracaoRebanhoPage({super.key});

  @override
  State<DeclaracaoRebanhoPage> createState() => _DeclaracaoRebanhoPageState();
}

class _DeclaracaoRebanhoPageState extends State<DeclaracaoRebanhoPage> {
  String data = hojeIso();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Declaração de rebanho')),
      body: AoMudar<List<LinhaDeclaracao>>(
        carregar: () async => declaracaoRebanho(data),
        builder: (context, linhas) {
          final texto = textoDeclaracao(data, linhas);
          final m = linhas.fold(0, (s, l) => s + l.machos), f = linhas.fold(0, (s, l) => s + l.femeas);
          return ListView(padding: const EdgeInsets.all(16), children: [
            DateField(label: 'Idade calculada em', value: data, obrigatorio: true, onChanged: (x) => setState(() => data = x!)),
            const SizedBox(height: 8),
            const Text('Animais ativos hoje, com a idade na data escolhida. Confira com o saldo do órgão de defesa do seu estado.'),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {0: FlexColumnWidth(2)},
              children: [
                const TableRow(children: [
                  Text('Faixa', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('Machos', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('Fêmeas', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('Total', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                for (final l in linhas)
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(l.faixa)),
                    Text('${l.machos}', textAlign: TextAlign.right),
                    Text('${l.femeas}', textAlign: TextAlign.right),
                    Text('${l.total}', textAlign: TextAlign.right),
                  ]),
                TableRow(children: [
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
                  Text('$m', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('$f', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${m + f}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: texto));
                if (context.mounted) avisar(context, 'Declaração copiada.');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar texto'),
            ),
          ]);
        },
      ),
    );
  }
}

/// Natalidade, desmame, kg desmamado por matriz, mortes e prenhez pelo escore corporal.
class IndicadoresCriaPage extends StatefulWidget {
  const IndicadoresCriaPage({super.key});

  @override
  State<IndicadoresCriaPage> createState() => _IndicadoresCriaPageState();
}

class _IndicadoresCriaPageState extends State<IndicadoresCriaPage> {
  int ano = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Indicadores de cria')),
      body: AoMudar<(IndicadoresCria, Map<String, (int, int)>)>(
        carregar: () async => (indicadoresCria(ano), prenhezPorEcc()),
        builder: (context, d) {
          final (r, ecc) = d;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => ano--)),
              Text('$ano', style: Theme.of(context).textTheme.titleLarge),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => ano++)),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                Info('Matrizes em 1º/jan', '${r.matrizes}'),
                Info('Nascimentos', '${r.nascimentos} (natalidade ${_pct(r.natalidade)})'),
                Info('Desmamados', '${r.desmamados} (desmame ${_pct(r.taxaDesmame)})'),
                Info('Peso médio na desmama', kg(r.pesoMedioDesmama)),
                Info('Kg desmamado por matriz', kg(r.kgPorMatriz)),
                Info('Mortalidade até 1 ano', '${r.mortesBezerros} (${_pct(r.mortalidadeBezerros)})'),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Matrizes são as fêmeas com 24 meses ou mais (ou categoria Vaca) no início do ano. '
                  'Desmama conta as pesagens com o evento Desmama.'),
            ),
            const Secao('Mortes no ano por causa'),
            Barras(r.mortesPorCausa),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('A causa vem do campo "Destino / causa" da saída por morte.'),
            ),
            const Secao('Prenhez pelo escore corporal (ECC)'),
            for (final e in ecc.entries)
              ListTile(
                dense: true,
                title: Text('ECC ${e.key}'),
                trailing: Text(e.value.$2 == 0 ? 'sem dados' : '${_pct(e.value.$1 / e.value.$2)} de ${e.value.$2}'),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Usa o último escore lançado até 90 dias antes de cada serviço. Lance o ECC pela ficha do Modo Curral.'),
            ),
          ]);
        },
      ),
    );
  }
}

/// Próximos 6 meses: vendas pela projeção de abate, parcelas de dívidas e custos médios.
class FluxoCaixaPage extends StatelessWidget {
  const FluxoCaixaPage({super.key});

  static const _meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fluxo de caixa projetado')),
      body: AoMudar<FluxoCaixa>(
        carregar: () async => fluxoCaixa(hojeIso()),
        builder: (context, f) {
          var soma = 0.0;
          final acumulado = [for (final m in f.meses) soma += m.saldo];
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Vendas: animais que chegam ao peso alvo da Projeção de abate, pela arroba salva lá. '
                'Parcelas: dívidas em aberto (as vencidas entram no primeiro mês). '
                'Custos: média dos últimos 3 meses (${moeda(f.custoMensal)} por mês).'
                '${f.semArroba ? '\n\nInforme o preço da arroba na Projeção de abate para incluir as vendas.' : ''}',
              ),
            ),
            for (final (i, m) in f.meses.indexed)
              Builder(builder: (context) {
                final mes = '${_meses[int.parse(m.mes.substring(5)) - 1]}/${m.mes.substring(2, 4)}';
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: Text(mes, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                        Text(moeda(m.saldo),
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: m.saldo < 0 ? Colors.red : Colors.green.shade700)),
                      ]),
                      Info('Vendas', m.vendas == 0 ? '' : '${moeda(m.vendas)} (${m.cabecas} cab.)'),
                      Info('Parcelas', m.parcelas == 0 ? '' : '- ${moeda(m.parcelas)}'),
                      Info('Custos', m.custos == 0 ? '' : '- ${moeda(m.custos)}'),
                      Info('Acumulado', moeda(acumulado[i])),
                    ]),
                  ),
                );
              }),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Peso de venda e rendimento: os mesmos da Projeção de abate. '
                  'É uma estimativa: confira antes de decidir.'),
            ),
          ]);
        },
      ),
    );
  }
}
