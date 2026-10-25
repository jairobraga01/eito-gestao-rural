// Relatório financeiro geral do ano. Só o dono da conta abre.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/db.dart';
import '../dados/financeiro.dart';
import '../dados/guarai.dart';
import '../dados/indicacoes.dart';
import '../dados/negocio.dart';
import '../dados/relatorio_html.dart';
import '../dispositivos/arquivo_stub.dart' if (dart.library.js_interop) '../dispositivos/arquivo_web.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';
import 'financeiro.dart' show entregarArquivo;
import 'painel_gado.dart';

/// App do gado de Guaraí (compras, vendas, despesas e pesagens), aberto pelo relatório.
const siteGadoGuarai = 'https://gado-guarai-jairo.web.app';

const _meses = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

class RelatorioFinanceiroPage extends StatefulWidget {
  const RelatorioFinanceiroPage({super.key});

  @override
  State<RelatorioFinanceiroPage> createState() => _RelatorioFinanceiroPageState();
}

class _RelatorioFinanceiroPageState extends State<RelatorioFinanceiroPage> {
  int ano = DateTime.now().year;

  Future<void> _importarGuarai(BuildContext context) async {
    final texto = await escolherArquivoTexto();
    if (texto == null || !context.mounted) return;
    final Map<String, Object?> b;
    try {
      b = lerBackupGuarai(texto);
    } catch (e) {
      avisar(context, e is FormatException ? e.message : 'Não deu para ler o arquivo.');
      return;
    }
    final nome = '${Db.registro('propriedades', Db.pid)?['nome'] ?? 'propriedade aberta'}';
    final qc = (b['compras'] as List?)?.length ?? 0, qv = (b['vendas'] as List?)?.length ?? 0;
    final qd = (b['despesas'] as List?)?.length ?? 0;
    if (!await confirmar(
        context,
        'Importar para $nome?',
        '$qc compra(s), $qv venda(s) e $qd despesa(s) do Gado Guaraí entram na propriedade $nome. '
            'Os animais ganham a numeração gg_c01_001, gg_c01_002... '
            'O que já foi importado antes não entra de novo.',
        ok: 'Importar')) {
      return;
    }
    final ResultadoGuarai r;
    try {
      r = await importarGuarai(b);
    } on RegistroDuplicado catch (e) {
      if (context.mounted) avisar(context, e.mensagem);
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Importado'),
        content: Text([r.resumo, ...r.avisos].join('\n\n')),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

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
          tooltip: 'Salvar em PDF ou imprimir',
          icon: const Icon(Icons.picture_as_pdf_outlined),
          onPressed: () {
            if (!imprimirHtml(htmlRelatorioFinanceiro(ano, hojeIso()))) {
              avisar(context, 'Não deu para abrir a impressão neste aparelho.');
            }
          },
        ),
        IconButton(
          tooltip: 'Baixar planilha (Excel)',
          icon: const Icon(Icons.download_outlined),
          onPressed: () => entregarArquivo(context, 'relatorio-financeiro-$ano.csv', planilhaRelatorioFinanceiro(ano)),
        ),
      ],
      corpo: AoMudar<(RelatorioFinanceiro, PosicaoFinanceira, ResumoGado, RelatorioFinanceiro)>(
        carregar: () async =>
            (relatorioFinanceiro(ano), PosicaoFinanceira(hojeIso()), resumoGado(ano), relatorioFinanceiro(ano - 1)),
        builder: (context, d) {
          final (r, p, g, ant) = d;
          final pa = ant.porMes;
          final pm = r.porMes;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            // Relatório Gado Guaraí: só na conta criador/admin (admins/{uid}).
            FutureBuilder<bool>(
              future: Indicacoes.souAdmin(),
              builder: (context, adm) => adm.data != true
                  ? const SizedBox.shrink()
                  : Card(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined, color: Color(0xFF2F6A40)),
                  title: const Text('Painel do gado', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Resumo, compras, vendas, saídas, despesas e pesagens, no formato do Gado Guaraí'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PainelGadoPage())),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Importar backup do Gado Guaraí'),
                  subtitle: const Text('Traz compras, vendas, despesas e pesagens para a propriedade aberta'),
                  onTap: () => _importarGuarai(context),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Abrir o Gado Guaraí'),
                  onTap: () => launchUrl(Uri.parse(siteGadoGuarai), mode: LaunchMode.externalApplication),
                ),
              ]),
            ),
            ),
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
                _Quadro('Receitas', moeda(r.receitas), Colors.green, anterior: ant.receitas, ano: ano - 1, atual: r.receitas),
                _Quadro('Despesas', moeda(r.despesas), Cores.alerta, anterior: ant.despesas, ano: ano - 1, atual: r.despesas),
                _Quadro('Resultado', moeda(r.resultado), r.resultado >= 0 ? Colors.green : Cores.alerta,
                    anterior: ant.resultado, ano: ano - 1, atual: r.resultado),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Entram as contas pagas no ano e as vendas, compras e custos lançados que ainda não viraram conta.',
                  style: TextStyle(color: Colors.black54)),
            ),
            if (g.cabecasCompradas > 0 || g.cabecasVendidas > 0) ...[
              const Secao('Compra e venda de gado'),
              ListTile(
                dense: true,
                title: Text('Compras · ${g.cabecasCompradas} cab.'),
                subtitle: g.cabecasCompradas > 0 ? Text('Média ${moeda(g.totalCompras / g.cabecasCompradas)} por cabeça') : null,
                trailing: Text(moeda(g.totalCompras)),
              ),
              ListTile(
                dense: true,
                title: Text('Vendas (líquido) · ${g.cabecasVendidas} cab.'),
                trailing: Text(moeda(g.liquidoVendas)),
              ),
              if (g.temLucro)
                ListTile(
                  dense: true,
                  title: Text(g.lucroVendas >= 0 ? 'Lucro das vendas' : 'Prejuízo das vendas'),
                  subtitle: const Text('Líquido menos o custo médio do lote de cada animal'),
                  trailing: Text(moeda(g.lucroVendas),
                      style: TextStyle(fontWeight: FontWeight.w700, color: g.lucroVendas < 0 ? Cores.alerta : Colors.green)),
                ),
            ],
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
                columns: [
                  const DataColumn(label: Text('Mês')),
                  const DataColumn(label: Text('Receitas'), numeric: true),
                  const DataColumn(label: Text('Despesas'), numeric: true),
                  const DataColumn(label: Text('Resultado'), numeric: true),
                  DataColumn(label: Text('Resultado ${ano - 1}'), numeric: true),
                ],
                rows: [
                  for (var i = 0; i < 12; i++)
                    if (pm[i].$1 != 0 || pm[i].$2 != 0 || pa[i].$1 != 0 || pa[i].$2 != 0)
                      DataRow(cells: [
                        DataCell(Text(_meses[i])),
                        DataCell(Text(moeda(pm[i].$1))),
                        DataCell(Text(moeda(pm[i].$2))),
                        DataCell(Text(moeda(pm[i].$1 - pm[i].$2),
                            style: TextStyle(color: pm[i].$1 - pm[i].$2 < 0 ? Cores.alerta : null))),
                        DataCell(Text(moeda(pa[i].$1 - pa[i].$2),
                            style: TextStyle(color: Colors.black54, fontStyle: pa[i].$1 - pa[i].$2 < 0 ? FontStyle.italic : null))),
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
  const _Quadro(this.titulo, this.valor, this.cor, {this.anterior, this.ano, this.atual});
  final String titulo, valor;
  final Color cor;

  /// Valor do ano anterior, para comparar.
  final double? anterior, atual;
  final int? ano;

  String? get _comparacao {
    if (anterior == null) return null;
    final base = 'Em $ano: ${moeda(anterior!)}';
    final a = atual;
    if (a == null || anterior == 0) return base;
    final v = (a - anterior!) / anterior!.abs() * 100;
    return '$base (${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)}%)';
  }

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
              if (_comparacao != null) ...[
                const SizedBox(height: 2),
                Text(_comparacao!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ]),
          ),
        ),
      );
}
