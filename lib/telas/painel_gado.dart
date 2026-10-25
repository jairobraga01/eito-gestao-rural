// Painel do gado, no mesmo formato do app Gado Guaraí (abas Resumo, Compras,
// Vendas, Saídas, Despesas e Pesagens). Só o dono abre, pelo Relatório financeiro.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/painel_gado.dart';
import '../util/util.dart';
import 'custos.dart';
import 'entradas.dart';
import 'vendas.dart';

// Cores do caderno de campo do Gado Guaraí.
const _bg = Color(0xFFEEF1EA), _surface = Color(0xFFFBFCF9), _sunk = Color(0xFFE3E8DE);
const _ink = Color(0xFF18201B), _muted = Color(0xFF5A675F), _line = Color(0xFFCDD5C8);
const _accent = Color(0xFF2F6A40), _brass = Color(0xFF9A6A14), _neg = Color(0xFFAE3A2C);
const _num = TextStyle(fontFamily: 'monospace', fontFeatures: [FontFeature.tabularFigures()], color: _ink);
const _mesesCurtos = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

String _n2(num v) => numeroBr(v.toDouble(), casas: 2);
String _n0(num v) => numeroBr(v.toDouble(), casas: 0);
String _mes(String ym) => ym.length < 7 ? ym : '${_mesesCurtos[int.parse(ym.substring(5, 7)) - 1]}/${ym.substring(0, 4)}';
Color _sinal(num v) => v < 0 ? _neg : _accent;

class PainelGadoPage extends StatefulWidget {
  const PainelGadoPage({super.key});

  @override
  State<PainelGadoPage> createState() => _PainelGadoPageState();
}

class _PainelGadoPageState extends State<PainelGadoPage> with SingleTickerProviderStateMixin {
  late final abas = TabController(length: 6, vsync: this)..addListener(() => setState(() {}));
  String filtro = '';
  late String exercicio = exercicioAtual(hojeIso());
  final abertas = <int>{};

  @override
  void dispose() {
    abas.dispose();
    super.dispose();
  }

  Widget? _fab() {
    final (rotulo, pagina) = switch (abas.index) {
      1 => ('+ Nova compra', const EntradaFormPage() as Widget),
      2 => ('+ Nova venda', const SaidaFormPage()),
      3 => ('+ Nova saída', const SaidaFormPage(tipoInicial: 'Morte')),
      4 => ('+ Nova despesa', const CustoFormPage()),
      _ => ('', const SizedBox()),
    };
    if (rotulo.isEmpty) return null;
    return FloatingActionButton.extended(
      heroTag: null,
      backgroundColor: _accent,
      foregroundColor: Colors.white,
      label: Text(rotulo, style: const TextStyle(fontWeight: FontWeight.w700)),
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => pagina)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Db.ehDono) {
      return Scaffold(
          appBar: AppBar(title: const Text('Painel do gado')),
          body: const Vazio('Só o dono da conta vê o painel do gado.', icone: Icons.lock_outline));
    }
    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: _bg),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
          title: Text.rich(TextSpan(children: [
            const TextSpan(text: 'PAINEL DO ', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .5)),
            const TextSpan(
                text: 'GADO', style: TextStyle(fontWeight: FontWeight.w800, color: _accent, letterSpacing: .5)),
            TextSpan(
                text: '   ${Db.registro('propriedades', Db.pid)?['nome'] ?? ''}',
                style: const TextStyle(fontSize: 13, color: _muted)),
          ])),
          bottom: TabBar(
            controller: abas,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: _ink,
            unselectedLabelColor: _muted,
            indicatorColor: _accent,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            tabs: const [
              Tab(text: 'Resumo'),
              Tab(text: 'Compras'),
              Tab(text: 'Vendas'),
              Tab(text: 'Saídas'),
              Tab(text: 'Despesas'),
              Tab(text: 'Pesagens'),
            ],
          ),
        ),
        floatingActionButton: _fab(),
        body: AoMudar<PainelGado>(
          carregar: () async => PainelGado(),
          builder: (context, t) => TabBarView(controller: abas, children: [
            _pagina([..._resumo(t)]),
            _pagina(_compras(t)),
            _pagina(_vendas(t)),
            _pagina(_saidas(t)),
            _pagina(_despesas(t)),
            _pagina(_pesagensAba(t)),
          ]),
        ),
      ),
    );
  }

  Widget _pagina(List<Widget> filhos) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filhos),
            ),
          ),
        ],
      );

  // ---------------------------------------------------------------- Resumo

  List<Widget> _resumo(PainelGado t) {
    final p = t.periodo(filtro);
    final maxMed = t.compras.fold<double>(1, (m, c) => math.max(m, c.media));
    return [
      _Kpis([
        _Kpi('Cabeças no pasto', _n0(t.noPasto), dica: 'de ${_n0(t.totalCab)} no total', grande: true),
        _Kpi('Custo total', moeda(t.custoTotal), dica: 'compra + custeio'),
        _Kpi('Custo por cabeça', moeda(t.custoCab), dica: 'custo total ÷ ${t.totalCab} cab.'),
        _Kpi('Saldo de caixa', moeda(t.caixa), dica: 'vendas − compras − despesas', cor: _sinal(t.caixa)),
      ]),
      _sec,
      _Grade([
        _Painel('Rebanho', [
          _Linha('Rebanho existente e nascidos', _n0(t.outrasEntradas)),
          _Linha('Compradas (${t.compras.length} compras)', '+ ${_n0(t.comprado)}'),
          _Linha('Vendidas', '− ${_n0(t.vendido)}'),
          _Linha('Outras saídas', '− ${_n0(t.saidasCab)}'),
          _Linha('No pasto', _n0(t.noPasto), total: true),
        ]),
        _Painel('Custos', [
          _Linha('Compra do gado', moeda(t.gastoCompra)),
          _Linha('Custeio (despesas)', moeda(t.custeio)),
          _Linha('Total', moeda(t.custoTotal), total: true),
          _Linha('Média de compra/cab.', moeda(t.mediaCompra)),
          _Linha('Custeio/cab. no pasto', moeda(t.custeioCab)),
        ]),
        _Painel('Caixa', [
          _Linha('Vendas (líquido)', moeda(t.liquidoVendas), cor: _accent),
          _Linha('Compras', '− ${moeda(t.gastoCompra)}', cor: _neg),
          _Linha('Despesas', '− ${moeda(t.custeio)}', cor: _neg),
          _Linha('Saldo', moeda(t.caixa), total: true, cor: _sinal(t.caixa)),
        ]),
      ]),
      _sec,
      _Painel('Resultado do período', [
        DropdownButton<String>(
          value: filtro,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: '', child: Text('Todo o período')),
            for (final a in {for (final m in t.meses) m.substring(0, 4)})
              DropdownMenuItem(value: a, child: Text('Ano $a')),
            for (final m in t.meses) DropdownMenuItem(value: m, child: Text(_mes(m))),
          ],
          onChanged: (x) => setState(() => filtro = x ?? ''),
        ),
        const SizedBox(height: 8),
        _Grade([
          Column(children: [
            _Linha('Cabeças compradas', _n0(p.qc)),
            _Linha('Cabeças vendidas', _n0(p.qv)),
            _Linha('Outras saídas', _n0(p.qs)),
          ]),
          Column(children: [
            _Linha('Compras', moeda(p.compras)),
            _Linha('Despesas', moeda(p.despesas)),
            _Linha('Vendas (líquido)', moeda(p.vendas)),
          ]),
          Column(children: [
            _Linha('Lucro das vendas', moeda(p.lucro), cor: _sinal(p.lucro)),
            _Linha('Caixa do período', moeda(p.caixa), total: true, cor: _sinal(p.caixa)),
          ]),
        ], semCaixa: true),
      ]),
      _sec,
      _Cabecalho('Custo médio por cabeça em cada compra', direita: 'média geral ${moeda(t.mediaCompra)}'),
      if (t.compras.isEmpty)
        const _Vazio('Nenhuma compra lançada ainda. Use a aba Compras para lançar a primeira.')
      else
        _Painel(null, [
          for (final c in t.compras)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 92, child: Text('${c.n}ª · ${br(c.data).length >= 5 ? br(c.data).substring(0, 5) : '-'}', style: const TextStyle(fontSize: 13))),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, cx) => Stack(children: [
                      Container(height: 14, decoration: BoxDecoration(color: _sunk, borderRadius: BorderRadius.circular(3))),
                      Container(
                          height: 14,
                          width: cx.maxWidth * c.media / maxMed,
                          decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(3))),
                      Positioned(
                          left: cx.maxWidth * t.mediaCompra / maxMed - 1,
                          child: Container(width: 2, height: 14, color: _brass)),
                    ]),
                  ),
                ),
                SizedBox(width: 110, child: Text(moeda(c.media), textAlign: TextAlign.right, style: _num.copyWith(fontSize: 13))),
              ]),
            ),
        ]),
      _sec,
      _Cabecalho('Despesas por mês · exercício ${_exTitulo(exercicio)}'),
      _barrasDespesas(t),
    ];
  }

  String _exTitulo(String ex) => '${ex.substring(0, 4)}/${mesesExercicio(ex).last.substring(0, 4)}';

  Widget _barrasDespesas(PainelGado t) {
    final ms = mesesExercicio(exercicio);
    final grade = t.despesasExercicio(exercicio);
    final tot = [for (var i = 0; i < 12; i++) grade.values.fold(0.0, (s, l) => s + l[i])];
    final maior = tot.fold<double>(1, math.max);
    return _Painel(null, [
      SizedBox(
        height: 150,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: Tooltip(
                message: '${_mes(ms[i])}: ${moeda(tot[i])}',
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 120 * tot[i] / maior,
                    decoration: const BoxDecoration(color: _brass, borderRadius: BorderRadius.vertical(top: Radius.circular(3))),
                  ),
                  const SizedBox(height: 4),
                  Text(_mesesCurtos[int.parse(ms[i].substring(5)) - 1], style: const TextStyle(fontSize: 11, color: _muted)),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }

  // --------------------------------------------------------------- Compras

  List<Widget> _compras(PainelGado t) {
    if (t.compras.isEmpty) {
      return const [_Vazio('Nenhuma compra lançada. Toque em “+ Nova compra” para lançar data, lotes, nota e frete.')];
    }
    return [
      _Kpis([
        _Kpi('Compras', '${t.compras.length}', grande: true),
        _Kpi('Cabeças compradas', _n0(t.comprado), grande: true),
        _Kpi('Total pago', moeda(t.gastoCompra)),
        _Kpi('Média/cabeça', moeda(t.mediaCompra)),
      ]),
      _sec,
      for (final c in t.compras.reversed) _cartaoCompra(c),
    ];
  }

  Widget _cartaoCompra(CompraPainel c) {
    final aberta = abertas.contains(c.entrada['id']);
    final lotes = c.lotes;
    final cv = c.comissaoVendPct / 100, cc = c.comissaoPct / 100;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: _surface, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => aberta ? abertas.remove(c.entrada['id']) : abertas.add(c.entrada['id'] as int)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              SizedBox(
                width: 52,
                child: Column(children: [
                  Text('${c.n}ª', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _accent, height: 1)),
                  const Text('COMPRA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _muted, letterSpacing: .8)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${br(c.data)} · ${c.qtd} cab.', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                      [
                        if (txt(c.entrada['origem']).isNotEmpty) txt(c.entrada['origem']),
                        if (lotes.isNotEmpty) '${lotes.length} lote${lotes.length > 1 ? 's' : ''}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 13, color: _muted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(moeda(c.total), style: _num.copyWith(fontWeight: FontWeight.w600)),
                Text('${moeda(c.media)}/cab.', style: const TextStyle(fontSize: 13, color: _muted)),
              ]),
            ]),
          ),
        ),
        if (aberta) ...[
          const Divider(height: 1, color: _line),
          if (lotes.isNotEmpty)
            _Tabela(
              colunas: ['Lote', 'Qtd', 'Valor/cab', 'Subtotal', 'Com. vend. ${_n2(cv * 100)}%', 'Valor vendedor',
                  'Com. comp. ${_n2(cc * 100)}%', 'Total lote', 'Média'],
              linhas: [
                for (final (i, l) in lotes.indexed)
                  () {
                    final q = (l['qtd'] as num? ?? 0), v = (l['valor'] as num? ?? 0), sub = q * v;
                    return [
                      '${i + 1}', _n0(q), _n2(v), _n2(sub), _n2(sub * cv), _n2(sub - sub * cv), _n2(sub * cc),
                      _n2(sub + sub * cc), _n2(q > 0 ? (sub + sub * cc) / q : 0),
                    ];
                  }(),
              ],
              rodape: ['Total', _n0(c.qtd), '', _n2(c.subtotal), _n2(c.subtotal * cv), _n2(c.subtotal * (1 - cv)),
                _n2(c.comissao), _n2(c.subtotal + c.comissao), ''],
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              _Linha('Subtotal + comissão comprador', moeda(c.subtotal + c.comissao)),
              _Linha('Nota', moeda(c.nota)),
              _Linha('Frete', moeda(c.frete)),
              _Linha('Total pago', moeda(c.total), total: true),
              _Linha('Média/custo por cabeça', moeda(c.media)),
              if (_peso(c.entrada) > 0)
                _Linha('Peso de entrada', '${_n0(_peso(c.entrada))} kg · ${_n2(_peso(c.entrada) / (c.qtd == 0 ? 1 : c.qtd))} kg/cab'),
              if (txt(c.entrada['obs']).isNotEmpty) _Linha(txt(c.entrada['obs']), ''),
            ]),
          ),
        ],
      ]),
    );
  }

  double _peso(Reg e) => (e['peso_total'] as num? ?? 0).toDouble();

  // ---------------------------------------------------------------- Vendas

  List<Widget> _vendas(PainelGado t) {
    if (t.vendas.isEmpty) {
      return const [_Vazio('Nenhuma venda lançada. Toque em “+ Nova venda” para lançar quantidade, preço e descontos.')];
    }
    final cu = t.custoVendidas;
    return [
      _Kpis([
        _Kpi('Cabeças vendidas', _n0(t.vendido), grande: true),
        _Kpi('Valor líquido', moeda(t.liquidoVendas), dica: 'bruto ${moeda(t.brutoVendas)}'),
        _Kpi('Custo das vendidas', moeda(cu), dica: 'compra + custeio por cabeça-dia'),
        _Kpi('Lucro', moeda(t.lucro),
            cor: _sinal(t.lucro), dica: cu > 0 ? '${numeroBr(t.lucro / cu * 100, casas: 1)}% sobre o custo' : null),
      ]),
      _sec,
      const _Cabecalho('Vendas'),
      _Tabela(
        colunas: const ['Data', 'Qtd', 'Líquido', 'Custo', 'Lucro', 'Margem', 'Peso kg', '@/cab', 'Bruto/cab', 'Bruto',
          'Descontos', 'Líq./cab', 'Destino'],
        linhas: [
          for (final v in t.vendas.reversed)
            [
              br(v.data), _n0(v.qtd), _n2(v.liquido), _n2(v.custo), _n2(v.lucro),
              '${numeroBr(v.margem * 100, casas: 1)}%', v.peso > 0 ? _n0(v.peso) : '—',
              v.arrobas > 0 && v.qtd > 0 ? _n2(v.arrobas / v.qtd) : '—', _n2(v.qtd > 0 ? v.bruto / v.qtd : 0),
              _n2(v.bruto), _n2(v.descontos), _n2(v.qtd > 0 ? v.liquido / v.qtd : 0), txt(v.saida['destino']),
            ],
        ],
        cores: {4: (i) => _sinal(t.vendas.reversed.elementAt(i).lucro), 5: (i) => _sinal(t.vendas.reversed.elementAt(i).lucro)},
        rodape: ['Total', _n0(t.vendido), _n2(t.liquidoVendas), _n2(cu), _n2(t.lucro), '', '', '', '', _n2(t.brutoVendas),
          _n2(t.brutoVendas - t.liquidoVendas), '', ''],
      ),
      const SizedBox(height: 8),
      const Text(
          'Custo por cabeça vendida = compra do animal + despesas do lote e gerais divididas por cabeça-dia '
          '(quem ficou mais tempo na fazenda leva mais custo) + sêmen.',
          style: TextStyle(fontSize: 13, color: _muted)),
    ];
  }

  // ---------------------------------------------------------------- Saídas

  List<Widget> _saidas(PainelGado t) => [
        _Kpis([
          _Kpi('Saídas (sem venda)', _n0(t.saidasCab), grande: true),
          _Kpi('Vendidas', _n0(t.vendido), grande: true),
          _Kpi('Total de cabeças', _n0(t.totalCab), grande: true),
          _Kpi('No pasto', _n0(t.noPasto), grande: true),
        ]),
        _sec,
        if (t.outrasSaidas.isEmpty)
          const _Vazio('Nenhuma saída lançada. Use “+ Nova saída” para registrar morte, consumo, doação ou transferência. '
              'As vendas já descontam do rebanho sozinhas.')
        else
          _Tabela(
            colunas: const ['Data', 'Qtd', 'Motivo', 'Observação'],
            linhas: [
              for (final s in t.outrasSaidas.reversed)
                [br(s['data']), _n0(s['quantidade'] as num? ?? 0), txt(s['tipo']), txt(s['obs'])],
            ],
          ),
      ];

  // -------------------------------------------------------------- Despesas

  List<Widget> _despesas(PainelGado t) {
    final ms = mesesExercicio(exercicio);
    final grade = t.despesasExercicio(exercicio);
    final totM = [for (var i = 0; i < 12; i++) grade.values.fold(0.0, (s, l) => s + l[i])];
    final totEx = totM.fold(0.0, (s, x) => s + x);
    final cab = t.noPasto == 0 ? 1 : t.noPasto;
    String cel(double v) => v == 0 ? '·' : _n2(v);
    return [
      _Kpis([
        _Kpi('Despesas no exercício', moeda(totEx)),
        _Kpi('Por cabeça no pasto', moeda(totEx / cab)),
        _Kpi('Total geral de custos', moeda(t.custoTotal)),
        _Kpi('Custo médio/cabeça', moeda(t.custoCab)),
      ]),
      _sec,
      _Cabecalho('Exercício ${_exTitulo(exercicio)}',
          acao: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                tooltip: 'Exercício anterior',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => exercicio = '${int.parse(exercicio.substring(0, 4)) - 1}${exercicio.substring(4)}')),
            IconButton(
                tooltip: 'Próximo exercício',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => exercicio = '${int.parse(exercicio.substring(0, 4)) + 1}${exercicio.substring(4)}')),
          ])),
      _Tabela(
        colunas: ['Tipo', for (final m in ms) '${_mesesCurtos[int.parse(m.substring(5)) - 1]}/${m.substring(2, 4)}', 'Total'],
        linhas: [
          for (final e in grade.entries) [e.key, ...e.value.map(cel), cel(e.value.fold(0.0, (s, x) => s + x))],
        ],
        rodape: ['Total mensal', ...totM.map(_n2), _n2(totEx)],
        rodape2: ['Por cabeça (${t.noPasto})', ...totM.map((v) => _n2(v / cab)), _n2(totEx / cab)],
      ),
      _sec,
      const _Cabecalho('Lançamentos'),
      if (t.despesas.isEmpty)
        const _Vazio('Nenhuma despesa lançada. Use “+ Nova despesa” para lançar aluguel, proteinado, remédio, vacina e outras.')
      else
        _Tabela(
          colunas: const ['Data', 'Tipo', 'Descrição', 'Valor'],
          linhas: [
            for (final d in t.despesas)
              [br(d['data']), txt(d['categoria']), txt(d['descricao']), _n2(d['valor'] as num)],
          ],
          aoTocar: (i) => Navigator.push(
              context, MaterialPageRoute(builder: (_) => CustoFormPage(custo: t.despesas[i]))),
        ),
    ];
  }

  // -------------------------------------------------------------- Pesagens

  List<Widget> _pesagensAba(PainelGado t) {
    final ult = t.pesagens.firstOrNull;
    return [
      _Kpis([
        _Kpi('Pesagens', '${t.pesagens.length}', grande: true),
        _Kpi('Última · peso médio', ult == null ? '—' : '${_n2(ult.medio)} kg', dica: ult == null ? null : br(ult.data)),
        _Kpi('@ por cabeça', ult == null ? '—' : _n2(ult.arrCab), dica: ult == null ? null : 'rendimento ${_n2(ult.rend * 100)}%'),
        _Kpi('Ganho diário', ult?.gmd == null ? '—' : '${_n2(ult!.gmd!)} kg',
            dica: ult?.dias == null ? 'precisa de 2 pesagens' : 'em ${ult!.dias} dias'),
      ]),
      _sec,
      if (t.pesagens.isEmpty)
        const _Vazio('Nenhuma pesagem lançada. Pese os animais pelo Modo Curral ou pela ficha do animal.')
      else ...[
        const _Cabecalho('Pesagens', direita: 'Ganho comparado à pesagem anterior do mesmo lote'),
        _Tabela(
          colunas: const ['Data', 'Lote', 'Cab.', 'Peso total kg', 'Média kg', '@/cab', 'Ganho kg/cab', 'Dias', 'GMD kg/dia',
            '@ produzidas/cab'],
          linhas: [
            for (final p in t.pesagens)
              [
                br(p.data), txt(Db.registro('lotes', p.loteId)?['nome']).isEmpty ? 'Rebanho' : txt(Db.registro('lotes', p.loteId)!['nome']),
                _n0(p.qtd), _n0(p.pesoTotal), _n2(p.medio), _n2(p.arrCab), p.ganho == null ? '—' : _n2(p.ganho!),
                p.dias == null ? '—' : '${p.dias}', p.gmd == null ? '—' : _n2(p.gmd!),
                p.arrProduzidas == null ? '—' : _n2(p.arrProduzidas!),
              ],
          ],
        ),
      ],
    ];
  }
}

const _sec = SizedBox(height: 28);

class _Kpi {
  const _Kpi(this.rotulo, this.valor, {this.dica, this.grande = false, this.cor});
  final String rotulo, valor;
  final String? dica;
  final bool grande;
  final Color? cor;
}

class _Kpis extends StatelessWidget {
  const _Kpis(this.itens);
  final List<_Kpi> itens;

  @override
  Widget build(BuildContext context) {
    final porLinha = MediaQuery.sizeOf(context).width < 760 ? 2 : 4;
    Widget celula(_Kpi k) => Container(
          color: _surface,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k.rotulo.toUpperCase(),
                style: const TextStyle(fontSize: 12, letterSpacing: 1, color: _muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(k.valor,
                  style: k.grande
                      ? TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1, color: k.cor ?? _ink)
                      : _num.copyWith(fontSize: 20, fontWeight: FontWeight.w600, color: k.cor ?? _ink)),
            ),
            if (k.dica != null) ...[
              const SizedBox(height: 4),
              Text(k.dica!, style: const TextStyle(fontSize: 13, color: _muted)),
            ],
          ]),
        );
    final linhas = <Widget>[];
    for (var i = 0; i < itens.length; i += porLinha) {
      linhas.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = i; j < i + porLinha; j++) ...[
            if (j > i) const SizedBox(width: 1),
            Expanded(child: j < itens.length ? celula(itens[j]) : Container(color: _surface)),
          ],
        ]),
      ));
      if (i + porLinha < itens.length) linhas.add(const SizedBox(height: 1));
    }
    return Container(
      decoration: BoxDecoration(color: _line, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: linhas),
    );
  }
}

class _Painel extends StatelessWidget {
  const _Painel(this.titulo, this.filhos);
  final String? titulo;
  final List<Widget> filhos;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _surface, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (titulo != null) ...[
            Text(titulo!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 8),
          ],
          ...filhos,
        ]),
      );
}

class _Grade extends StatelessWidget {
  const _Grade(this.filhos, {this.semCaixa = false});
  final List<Widget> filhos;
  final bool semCaixa;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 760) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, f) in filhos.indexed) ...[if (i > 0) SizedBox(height: semCaixa ? 4 : 12), f],
      ]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, f) in filhos.indexed) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: f)],
      ]),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor, {this.total = false, this.cor});
  final String rotulo, valor;
  final bool total;
  final Color? cor;

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.only(top: total ? 2 : 0),
        padding: EdgeInsets.only(top: total ? 7 : 5, bottom: 5),
        decoration: BoxDecoration(
          border: total
              ? const Border(top: BorderSide(color: _ink, width: 1.5))
              : const Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(children: [
          Expanded(
              child: Text(rotulo,
                  style: TextStyle(fontSize: 15, color: _ink, fontWeight: total ? FontWeight.w700 : FontWeight.normal))),
          Text(valor,
              style: _num.copyWith(fontSize: 15, color: cor ?? _ink, fontWeight: total ? FontWeight.w700 : FontWeight.normal)),
        ]),
      );
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho(this.titulo, {this.direita, this.acao});
  final String titulo;
  final String? direita;
  final Widget? acao;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(titulo.toUpperCase(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: .6, color: _ink)),
            if (direita != null) Text(direita!, style: const TextStyle(fontSize: 13, color: _muted)),
            if (acao != null) acao!,
          ],
        ),
      );
}

class _Vazio extends StatelessWidget {
  const _Vazio(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: _sunk, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
        child: Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
      );
}

class _Tabela extends StatelessWidget {
  const _Tabela({required this.colunas, required this.linhas, this.rodape, this.rodape2, this.cores = const {}, this.aoTocar});
  final List<String> colunas;
  final List<List<String>> linhas;
  final List<String>? rodape, rodape2;
  final Map<int, Color Function(int linha)> cores;
  final ValueChanged<int>? aoTocar;

  @override
  Widget build(BuildContext context) {
    DataCell cel(String v, {Color? cor, bool negrito = false}) => DataCell(Text(v,
        style: _num.copyWith(fontSize: 14, color: cor ?? _ink, fontWeight: negrito ? FontWeight.w700 : FontWeight.normal)));
    return Container(
      decoration: BoxDecoration(color: _surface, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: const WidgetStatePropertyAll(_sunk),
          headingTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _muted),
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columnSpacing: 18,
          showCheckboxColumn: false,
          columns: [for (final c in colunas) DataColumn(label: Text(c))],
          rows: [
            for (final (i, l) in linhas.indexed)
              DataRow(
                onSelectChanged: aoTocar == null ? null : (_) => aoTocar!(i),
                cells: [for (final (j, v) in l.indexed) cel(v, cor: cores[j]?.call(i))],
              ),
            for (final r in [rodape, rodape2])
              if (r != null)
                DataRow(
                  color: const WidgetStatePropertyAll(_sunk),
                  cells: [for (final v in r) cel(v, negrito: true)],
                ),
          ],
        ),
      ),
    );
  }
}
