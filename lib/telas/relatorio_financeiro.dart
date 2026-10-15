// Relatório financeiro geral do ano. Só o dono da conta abre.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/db.dart';
import '../dados/financeiro.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';
import 'financeiro.dart' show entregarArquivo;

const _meses = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

class RelatorioFinanceiroPage extends StatefulWidget {
  const RelatorioFinanceiroPage({super.key});

  @override
  State<RelatorioFinanceiroPage> createState() => _RelatorioFinanceiroPageState();
}

class _RelatorioFinanceiroPageState extends State<RelatorioFinanceiroPage> {
  int ano = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    if (!Db.ehDono) {
      return const Pagina(
        titulo: 'Relatório financeiro',
        corpo: Vazio('Só o dono da conta vê o relatório financeiro.', icone: Icons.lock_outline),
      );
    }
    return Pagina(
      titulo: 'Relatório financeiro',
      acoes: [
        IconButton(
          tooltip: 'Enviar pelo WhatsApp',
          icon: const Icon(Icons.share),
          onPressed: () => launchUrl(
              Uri.parse('https://wa.me/?text=${Uri.encodeComponent(textoRelatorioFinanceiro(ano, hojeIso()))}'),
              mode: LaunchMode.externalApplication),
        ),
        IconButton(
          tooltip: 'Baixar planilha (Excel)',
          icon: const Icon(Icons.download_outlined),
          onPressed: () => entregarArquivo(context, 'relatorio-financeiro-$ano.csv', planilhaRelatorioFinanceiro(ano)),
        ),
      ],
      corpo: AoMudar<(RelatorioFinanceiro, PosicaoFinanceira)>(
        carregar: () async => (relatorioFinanceiro(ano), PosicaoFinanceira(hojeIso())),
        builder: (context, d) {
          final (r, p) = d;
          final pm = r.porMes;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Row(children: [
              IconButton(tooltip: 'Ano anterior', icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => ano--)),
              Expanded(
                child: Text('$ano',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(tooltip: 'Próximo ano', icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => ano++)),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _Quadro('Receitas', moeda(r.receitas), Colors.green),
                _Quadro('Despesas', moeda(r.despesas), Cores.alerta),
                _Quadro('Resultado', moeda(r.resultado), r.resultado >= 0 ? Colors.green : Cores.alerta),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Entram as contas pagas no ano e as vendas, compras e custos lançados que ainda não viraram conta.',
                  style: TextStyle(color: Colors.black54)),
            ),
            if (r.receitasPorCategoria.isNotEmpty) ...[
              const Secao('Receitas por categoria'),
              for (final e in r.receitasPorCategoria.entries)
                ListTile(dense: true, title: Text(e.key), trailing: Text(moeda(e.value))),
            ],
            if (r.despesasPorCategoria.isNotEmpty) ...[
              const Secao('Despesas por categoria'),
              for (final e in r.despesasPorCategoria.entries)
                ListTile(dense: true, title: Text(e.key), trailing: Text(moeda(e.value))),
            ],
            const Secao('Mês a mês'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Mês')),
                  DataColumn(label: Text('Receitas'), numeric: true),
                  DataColumn(label: Text('Despesas'), numeric: true),
                  DataColumn(label: Text('Resultado'), numeric: true),
                ],
                rows: [
                  for (var i = 0; i < 12; i++)
                    if (pm[i].$1 != 0 || pm[i].$2 != 0)
                      DataRow(cells: [
                        DataCell(Text(_meses[i])),
                        DataCell(Text(moeda(pm[i].$1))),
                        DataCell(Text(moeda(pm[i].$2))),
                        DataCell(Text(moeda(pm[i].$1 - pm[i].$2),
                            style: TextStyle(color: pm[i].$1 - pm[i].$2 < 0 ? Cores.alerta : null))),
                      ]),
                ],
              ),
            ),
            const Secao('Hoje'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.call_received, color: Colors.green),
              title: const Text('Contas a receber em aberto'),
              trailing: Text(moeda(p.aReceber)),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.call_made, color: Cores.alerta),
              title: const Text('Contas a pagar em aberto'),
              subtitle: p.atrasadas > 0 ? Text('${p.atrasadas} atrasada(s)') : null,
              trailing: Text(moeda(p.aPagar)),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Saldo devedor das dívidas'),
              subtitle: Text('Vence nos próximos 12 meses: ${moeda(p.parcelas12meses)}'),
              trailing: Text(moeda(p.saldoDividas)),
            ),
          ]);
        },
      ),
    );
  }
}

class _Quadro extends StatelessWidget {
  const _Quadro(this.titulo, this.valor, this.cor);
  final String titulo, valor;
  final Color cor;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 200,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 4),
              Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cor)),
            ]),
          ),
        ),
      );
}
