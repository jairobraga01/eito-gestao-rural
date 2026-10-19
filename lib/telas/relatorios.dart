import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/manejo.dart' show intervaloEntrePartosRebanho;
import '../dados/mapa.dart' show lotacaoPiquetes;
import '../dados/relatorio_fazenda.dart';
import '../dispositivos/arquivo_stub.dart' if (dart.library.js_interop) '../dispositivos/arquivo_web.dart';
import '../dados/resumo_periodo.dart';
import '../util/util.dart';
import 'base.dart';
import 'indicadores.dart';
import 'projecao_abate.dart';
import 'ranking_matrizes.dart';
import 'resumo_semanal.dart';

// ---------- Consultas compartilhadas com o Painel ----------

/// Fêmeas ativas prenhes com parto previsto até daqui a [dias] dias (inclui atrasados).
Future<List<Reg>> partosPrevistos(int dias) async {
  final limite = somaDias(hojeIso(), dias);
  return (await Db.reproducoes(filtro: 'Prenhe'))
      .where((r) =>
          r['femea_status'] == 'Ativo' &&
          r['parto_previsto'] != null &&
          txt(r['parto_previsto']).compareTo(limite) <= 0)
      .toList()
    ..sort((a, b) => txt(a['parto_previsto']).compareTo(txt(b['parto_previsto'])));
}

/// Serviços com mais de 30 dias ainda sem diagnóstico.
Future<List<Reg>> diagnosticosAtrasados() async {
  final limite = somaDias(hojeIso(), -30);
  return (await Db.reproducoes(filtro: 'Pendente'))
      .where((r) => r['femea_status'] == 'Ativo' && txt(r['data']).compareTo(limite) <= 0)
      .toList()
    ..sort((a, b) => txt(a['data']).compareTo(txt(b['data'])));
}

/// Manejos sanitários dos animais ativos desta propriedade.
List<(Reg, Reg)> _sanidadeAtivos() {
  final r = <(Reg, Reg)>[];
  for (final s in Db.registros('sanidade')) {
    final a = Db.registro('animais', s['animal_id']);
    if (a == null || a['status'] != 'Ativo' || a['propriedade_id'] != Db.pid) continue;
    r.add((s, a));
  }
  return r;
}

/// Próximas aplicações (inclui atrasadas) ainda não refeitas.
Future<List<Reg>> aplicacoesProximas(int dias) async {
  final limite = somaDias(hojeIso(), dias);
  final todos = _sanidadeAtivos();
  // Última data de cada produto em cada animal.
  final ultima = <String, String>{};
  for (final (s, _) in todos) {
    final k = '${s['animal_id']}|${txt(s['produto']).toLowerCase()}';
    final d = txt(s['data']);
    if ((ultima[k] ?? '').compareTo(d) < 0) ultima[k] = d;
  }
  final grupos = <String, Reg>{};
  for (final (s, _) in todos) {
    final prox = s['proxima'];
    if (prox == null || txt(prox).compareTo(limite) > 0) continue;
    final k = '${s['animal_id']}|${txt(s['produto']).toLowerCase()}';
    if (txt(s['data']).compareTo(ultima[k] ?? '') < 0) continue; // já refeita depois
    final g = '${s['produto']}|${s['tipo']}|$prox';
    final atual = grupos[g];
    grupos[g] = {
      'produto': s['produto'],
      'tipo': s['tipo'],
      'proxima': prox,
      'qtd': ((atual?['qtd'] as int?) ?? 0) + 1,
    };
  }
  return grupos.values.toList()..sort((a, b) => txt(a['proxima']).compareTo(txt(b['proxima'])));
}

/// Animais ainda dentro do período de carência.
Future<List<Reg>> animaisEmCarencia() async {
  final hoje = hojeIso();
  final r = <Reg>[];
  for (final (s, a) in _sanidadeAtivos()) {
    final dias = s['carencia'] is num ? (s['carencia'] as num).toInt() : 0;
    if (dias <= 0 || s['data'] == null) continue;
    final libera = somaDias(txt(s['data']), dias);
    if (libera.compareTo(hoje) < 0) continue;
    r.add({'id': a['id'], 'brinco': a['brinco'], 'nome': a['nome'], 'produto': s['produto'], 'libera': libera});
  }
  return r..sort((a, b) => txt(a['libera']).compareTo(txt(b['libera'])));
}

Map<String, int> _contagem(List<Reg> animais, String Function(Reg) chave) {
  final c = <String, int>{};
  for (final a in animais) {
    final k = chave(a);
    c[k] = (c[k] ?? 0) + 1;
  }
  final ordenado = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in ordenado) e.key: e.value};
}

// ---------- Relatório ----------

/// Situação de hoje: rebanho, partos e sanidade próximos, carência e GMD.
class _Atual {
  late int ativos;
  late Map<String, int> porCategoria, porLote, porSexo;
  late List<Reg> partos;
  late List<Reg> proximas;
  late List<Reg> carencia;
  final gmds = <(Reg, double, int)>[];

  double? get gmdMedio =>
      gmds.isEmpty ? null : gmds.map((g) => g.$2).reduce((a, b) => a + b) / gmds.length;
}

Future<_Atual> _carregarAtual() async {
  final r = _Atual();
  final ativos = await Db.animais(soAtivos: true);
  r.porCategoria = _contagem(ativos, (a) => txt(a['categoria']).trim().isEmpty ? 'Sem categoria' : txt(a['categoria']).trim());
  r.porLote = _contagem(ativos, (a) => txt(a['lote_nome']).isEmpty ? 'Sem lote' : txt(a['lote_nome']));
  r.porSexo = _contagem(ativos, (a) => a['sexo'] == 'F' ? 'Fêmeas' : 'Machos');
  r.ativos = ativos.length;
  r.partos = await partosPrevistos(90);
  r.proximas = await aplicacoesProximas(30);
  r.carencia = await animaisEmCarencia();

  // GMD: da primeira à última pesagem de cada animal ativo.
  final idsAtivos = {for (final a in ativos) a['id']};
  final porAnimal = <Object?, List<Reg>>{};
  for (final p in await Db.pesagens()) {
    if (!idsAtivos.contains(p['animal_id'])) continue;
    porAnimal.putIfAbsent(p['animal_id'], () => []).add(p);
  }
  for (final l in porAnimal.values) {
    if (l.length < 2) continue;
    l.sort((a, b) {
      final c = txt(a['data']).compareTo(txt(b['data']));
      return c != 0 ? c : ((a['id'] as num?) ?? 0).compareTo((b['id'] as num?) ?? 0);
    });
    final dias = diasEntre(txt(l.first['data']), txt(l.last['data']));
    if (dias <= 0) continue;
    final ganho = (l.last['peso'] as num) - (l.first['peso'] as num);
    r.gmds.add((l.last, ganho / dias, dias));
  }
  r.gmds.sort((a, b) => b.$2.compareTo(a.$2));
  return r;
}

String _pct(double? v) => v == null ? '-' : '${(v * 100).toStringAsFixed(0)}%';

class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({super.key});

  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _RelatoriosPageState extends State<RelatoriosPage> {
  bool anual = false;
  int ano = DateTime.now().year;
  int mes = DateTime.now().month;

  void _andar(int passo) => setState(() {
        if (anual) {
          ano += passo;
          return;
        }
        final d = DateTime(ano, mes + passo);
        ano = d.year;
        mes = d.month;
      });

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Relatórios',
      acoes: [
        IconButton(
          tooltip: 'Relatório da fazenda (PDF)',
          icon: const Icon(Icons.picture_as_pdf_outlined),
          onPressed: () async {
            final hoje = hojeIso();
            final html = htmlRelatorioFazenda(
              hoje: hoje,
              ativos: await Db.animais(soAtivos: true),
              lotes: await Db.lotes(soAtivos: true),
              piquetes: await Db.piquetes(),
              lotacao: lotacaoPiquetes(),
              prenhes: (await Db.reproducoes(filtro: 'Prenhe')).where((r) => r['femea_status'] == 'Ativo').length,
              partos90: (await partosPrevistos(90)).length,
              emCarencia: (await animaisEmCarencia()).length,
              aplicacoes30: (await aplicacoesProximas(30)).length,
            );
            if (!imprimirHtml(html) && context.mounted) {
              avisar(context, 'Não deu para abrir a impressão neste aparelho.');
            }
          },
        ),
        IconButton(
          tooltip: 'Resumo da semana (WhatsApp)',
          icon: const Icon(Icons.share),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResumoSemanalPage())),
        ),
        IconButton(
          tooltip: 'Projeção de abate',
          icon: const Icon(Icons.trending_up),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjecaoAbatePage())),
        ),
      ],
      corpo: AoMudar<(ResumoPeriodo, List<ResumoPeriodo>?, _Atual)>(
        carregar: () async => (
          anual ? ResumoPeriodo.ano(ano) : ResumoPeriodo.mes(ano, mes),
          anual ? ResumoPeriodo.mesesDoAno(ano) : null,
          await _carregarAtual(),
        ),
        builder: (context, d) {
          final (p, meses, r) = d;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Mensal')),
                    ButtonSegment(value: true, label: Text('Anual')),
                  ],
                  selected: {anual},
                  onSelectionChanged: (s) => setState(() => anual = s.first),
                ),
              ),
              Row(children: [
                IconButton(tooltip: 'Anterior', icon: const Icon(Icons.chevron_left), onPressed: () => _andar(-1)),
                Expanded(
                  child: Text(anual ? '$ano' : '${nomesMeses[mes - 1]} de $ano',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(tooltip: 'Próximo', icon: const Icon(Icons.chevron_right), onPressed: () => _andar(1)),
              ]),
              ..._periodo(context, p),
              if (meses != null) ...[
                const Secao('Mês a mês'),
                _MesAMes(meses),
              ],
              ..._atual(r),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _periodo(BuildContext context, ResumoPeriodo p) {
    final media = p.gmdMedio;
    final custo = p.custoPorPrenhez;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width >= 720 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.6,
          children: [
            Kpi('Nascimentos', '${p.nascimentos}', icone: Icons.child_friendly_outlined),
            Kpi('Vacas inseminadas', '${p.inseminadas}', icone: Icons.favorite_border),
            Kpi('Taxa de prenhez', _pct(p.taxaPrenhez), icone: Icons.percent, cor: Colors.green),
            Kpi('Partos previstos', '${p.partosPrevistos}', icone: Icons.event),
            Kpi('Vacinações', '${p.vacinacoes}', icone: Icons.vaccines_outlined),
            Kpi('GMD médio', media == null ? '-' : gmd(media), icone: Icons.monitor_weight_outlined),
            Kpi('Saídas', '${p.saidas} cab.', icone: Icons.sell_outlined, cor: Colors.orange),
            Kpi('Custo por prenhez', custo == null ? '-' : moeda(custo), icone: Icons.science_outlined),
          ],
        ),
      ),
      const Secao('Reprodução'),
      _linha('Nascimentos', '${p.nascimentos} (${p.nascMachos} machos, ${p.nascFemeas} fêmeas)'),
      _linha('Serviços (IA, IATF, TE e monta)', '${p.servicos}'),
      _linha('Prenhes / vazias / sem diagnóstico', '${p.prenhes} / ${p.vazias} / ${p.pendentes}'),
      _linha('Gasto com sêmen', moeda(p.custoSemen)),
      _linha('Chuva', '${num1(p.chuvaMm)} mm'),
      const Secao('Sanidade e pesagens'),
      _linha('Manejos sanitários', '${p.manejosSanitarios}'),
      if (p.vacinasPorProduto.isNotEmpty) Barras(_ordenado(p.vacinasPorProduto)),
      _linha('Pesagens', '${p.pesagens}'),
      _linha('GMD médio', media == null ? 'precisa de 2 pesagens no período' : '${gmd(media)} (${p.gmds.length} animais)'),
      const Secao('Compras e entradas'),
      if (p.entradasPorTipo.isEmpty) _linha('Nenhuma', ''),
      for (final e in _ordenado(p.entradasPorTipo).entries) _linha(e.key, '${e.value} cab.'),
      if (p.cabecasCompradas > 0 && p.valorCompras > 0) ...[
        _linha('Valor das compras', moeda(p.valorCompras)),
        _linha('Média por cabeça comprada', moeda(p.valorCompras / p.cabecasCompradas)),
      ],
      const Secao('Vendas e saídas'),
      if (p.saidasPorTipo.isEmpty) _linha('Nenhuma', ''),
      for (final e in _ordenado(p.saidasPorTipo).entries) _linha(e.key, '${e.value} cab.'),
      if (p.cabecasVendidas > 0 && p.valorVendas > 0) ...[
        _linha('Valor das vendas', moeda(p.valorVendas)),
        _linha('Média por cabeça vendida', moeda(p.valorVendas / p.cabecasVendidas)),
      ],
    ];
  }

  Widget _linha(String rotulo, String valor) => ListTile(dense: true, title: Text(rotulo), trailing: Text(valor));

  Map<String, int> _ordenado(Map<String, int> m) =>
      {for (final e in m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) e.key: e.value};

  List<Widget> _atual(_Atual r) {
    final media = r.gmdMedio;
    return [
      const Divider(height: 32),
      Secao('Hoje: ${r.ativos} cabeças ativas'),
      Barras({for (final e in r.porSexo.entries) e.key: e.value}),
      const Secao('Por categoria'),
      Barras({for (final e in r.porCategoria.entries) e.key: e.value}),
      const Secao('Por lote / pasto'),
      Barras({for (final e in r.porLote.entries) e.key: e.value}),
      if (intervaloEntrePartosRebanho() case (final iep?, final n))
        ListTile(
          dense: true,
          title: const Text('Intervalo entre partos'),
          trailing: Text('${iep.round()} dias ($n ${n == 1 ? 'vaca' : 'vacas'})'),
        ),
      ListTile(
        leading: const Icon(Icons.trending_up),
        title: const Text('Projeção de abate'),
        subtitle: const Text('Quando cada lote chega ao peso de venda e quanto vale'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjecaoAbatePage())),
      ),
      ListTile(
        leading: const Icon(Icons.emoji_events_outlined),
        title: const Text('Ranking de matrizes'),
        subtitle: const Text('Prenhez, intervalo entre partos e desmama das crias'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RankingMatrizesPage())),
      ),
      ListTile(
        leading: const Icon(Icons.child_care),
        title: const Text('Indicadores de cria'),
        subtitle: const Text('Natalidade, desmame, kg por matriz, mortes e prenhez pelo ECC'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IndicadoresCriaPage())),
      ),
      ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: const Text('Fluxo de caixa projetado'),
        subtitle: const Text('Vendas previstas, parcelas e custos dos próximos 6 meses'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FluxoCaixaPage())),
      ),
      ListTile(
        leading: const Icon(Icons.assignment_outlined),
        title: const Text('Declaração de rebanho'),
        subtitle: const Text('Saldo nas colunas do SIDAGO (Agrodefesa) e conferência'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeclaracaoRebanhoPage())),
      ),
      ListTile(
        leading: const Icon(Icons.share),
        title: const Text('Resumo da semana'),
        subtitle: const Text('Para mandar pelo WhatsApp'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResumoSemanalPage())),
      ),
      Secao('Partos previstos (próximos 90 dias): ${r.partos.length}'),
      if (r.partos.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nenhum.')),
      for (final p in r.partos)
        ListTile(
          dense: true,
          leading: const Icon(Icons.event),
          title: Text(rotulo(p)),
          trailing: Text(br(p['parto_previsto'])),
        ),
      const Secao('Desenvolvimento (GMD de todo o histórico)'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(media == null
            ? 'São necessárias ao menos duas pesagens por animal.'
            : 'GMD médio: ${gmd(media)} (${r.gmds.length} animais)'),
      ),
      for (final g in r.gmds.take(15))
        ListTile(
          dense: true,
          title: Text(rotulo(g.$1)),
          subtitle: Text('Último peso ${kg(g.$1['peso'] as num)} · ${g.$3} dias'),
          trailing: Text(gmd(g.$2)),
        ),
      Secao('Sanidade – próximos 30 dias: ${r.proximas.length}'),
      for (final s in r.proximas)
        ListTile(
          dense: true,
          leading: const Icon(Icons.vaccines_outlined),
          title: Text('${s['produto']} (${s['qtd']} animais)'),
          trailing: Text(br(s['proxima'])),
        ),
      Secao('Em carência: ${r.carencia.length}'),
      for (final c in r.carencia)
        ListTile(
          dense: true,
          leading: const Icon(Icons.block, color: Colors.red),
          title: Text('${rotulo(c)} · ${c['produto']}'),
          trailing: Text('libera ${br(c['libera'])}'),
        ),
    ];
  }
}

/// Tabela do ano, um mês por linha.
class _MesAMes extends StatelessWidget {
  const _MesAMes(this.meses);
  final List<ResumoPeriodo> meses;

  @override
  Widget build(BuildContext context) {
    const colunas = ['Mês', 'Nasc.', 'Insem.', 'Prenhes', 'Prenhez', 'Vacin.', 'Pesag.', 'Saídas'];
    Widget cel(String t, {bool negrito = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(t, textAlign: TextAlign.right, style: negrito ? const TextStyle(fontWeight: FontWeight.w700) : null),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(horizontalInside: BorderSide(color: Theme.of(context).dividerColor)),
        children: [
          TableRow(children: [for (final c in colunas) cel(c, negrito: true)]),
          for (final (i, m) in meses.indexed)
            TableRow(children: [
              cel(nomesMeses[i].substring(0, 3)),
              cel('${m.nascimentos}'),
              cel('${m.inseminadas}'),
              cel('${m.prenhes}'),
              cel(_pct(m.taxaPrenhez)),
              cel('${m.vacinacoes}'),
              cel('${m.pesagens}'),
              cel('${m.saidas}'),
            ]),
        ],
      ),
    );
  }
}
