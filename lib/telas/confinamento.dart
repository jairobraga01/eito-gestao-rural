import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/confinamento.dart';
import '../dados/db.dart';
import '../dados/gestao.dart' show ajustesArroba;
import '../dados/proteinado.dart' show formulas, insumos;
import '../dados/relatorio_confinamento.dart';
import '../dispositivos/arquivo_stub.dart' if (dart.library.js_interop) '../dispositivos/arquivo_web.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';

String _q(double? v, [int casas = 1]) => v == null ? '-' : numeroBr(v, casas: casas);

/// Modo Confinamento: os ciclos de engorda no cocho, a leitura de cocho de cada
/// manhã com o trato sugerido e as contas (consumo, GMD, diária, arroba).
class ConfinamentoPage extends StatelessWidget {
  const ConfinamentoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Modo Confinamento',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Novo ciclo'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CicloFormPage())),
      ),
      corpo: AoMudar<List<Ciclo>>(
        carregar: () async => ciclos(),
        builder: (context, cs) {
          if (cs.isEmpty) {
            return const Vazio(
                'Nenhum ciclo de confinamento. Crie um ciclo para cada curral ou baia: o lote, a data e o peso de entrada, '
                'a dieta e a meta de saída. Depois, faça a leitura de cocho toda manhã.',
                icone: Icons.fence);
          }
          final hoje = hojeIso();
          final abertos = cs.where((c) => c.aberto).toList();
          final cab = abertos.fold<int>(0, (s, c) => s + c.cabecas);
          final kgHoje = abertos.fold<double>(0, (s, c) {
            final l = c.leituraDoDia(hoje);
            return s + (l == null ? c.trato(hoje, null) : ((l['kg_fornecido'] as num?)?.toDouble() ?? 0));
          });
          final lidos = abertos.where((c) => c.leituraDoDia(hoje) != null).length;
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
            if (abertos.isNotEmpty) ...[
              Card(
                color: Cores.oliva,
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeituraCochoPage())),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const Icon(Icons.fact_check_outlined, color: Colors.white, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Leitura de cocho e trato de hoje',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                          Text('$lidos de ${abertos.length} curral(is) lidos · $cab cab. · ${_q(kgHoje, 0)} kg previstos',
                              style: const TextStyle(color: Colors.white)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white),
                    ]),
                  ),
                ),
              ),
            ],
            for (final c in cs) _CicloCard(c, hoje),
          ]);
        },
      ),
    );
  }
}

class _CicloCard extends StatelessWidget {
  const _CicloCard(this.c, this.hoje);
  final Ciclo c;
  final String hoje;

  @override
  Widget build(BuildContext context) {
    final r = c.resultado(hoje);
    final saida = c.aberto ? c.saidaPrevista(hoje) : txt(c.reg['data_saida']);
    return Card(
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CicloPage(c.id))),
        leading: CircleAvatar(
          backgroundColor: c.aberto ? Cores.oliva : Colors.grey,
          child: Icon(c.aberto ? Icons.fence : Icons.check, color: Colors.white),
        ),
        title: Text('${c.nome}${c.lote == null ? '' : ' · ${txt(c.lote!['nome'])}'}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          '${c.cabecas} cab. · ${r.dias} dias de cocho · ${c.dieta}',
          'GMD ${_q(r.gmd, 2)} kg${c.gmdReal(hoje) ? '' : ' (previsto)'} · peso ${_q(r.peso, 0)} kg · diária ${moeda(c.diaria)}',
          if (c.consumoMS != null) 'Consumo ${_q(c.consumoMS, 2)} kg MS/cab/dia (${_q(c.consumoPV(hoje), 2)}% PV)',
          c.aberto ? 'Saída prevista ${br(saida)}' : 'Encerrado em ${br(saida)}',
        ].join('\n')),
        isThreeLine: true,
      ),
    );
  }
}

/// Ficha do ciclo: indicadores, custo, projeção e leituras.
class CicloPage extends StatelessWidget {
  const CicloPage(this.id, {super.key});
  final int id;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Db.changes,
      builder: (context, _, __) {
        final reg = Db.registro('confinamentos', id);
        if (reg == null) return Scaffold(appBar: AppBar(), body: const Vazio('Ciclo apagado.'));
        final c = Ciclo(reg);
        final hoje = hojeIso();
        final agora = c.resultado(hoje);
        final fim = c.resultado(hoje, naSaida: true);
        return Scaffold(
          appBar: AppBar(
            title: Text(c.nome),
            actions: [
              IconButton(
                tooltip: 'Relatório em PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () {
                  if (!imprimirHtml(htmlRelatorioConfinamento(c, hoje))) avisar(context, 'Não deu para abrir a impressão neste aparelho.');
                },
              ),
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CicloFormPage(ciclo: reg))),
              ),
            ],
          ),
          floatingActionButton: c.aberto
              ? FloatingActionButton.extended(
                  heroTag: null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Leitura de hoje'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeituraCochoPage(so: c.id))),
                )
              : null,
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            Info('Lote', txt(c.lote?['nome'])),
            Info('Dieta', '${c.dieta} · MS ${_q(c.ms * 100, 0)}%'),
            Info('Entrada', '${br(c.entrada)} · ${c.cabecasEntrada} cab. · ${_q(c.pesoEntrada, 0)} kg'),
            Info('Cabeças', '${c.cabecas}${c.mortes > 0 ? ' (${c.mortes} morte(s))' : ''}'),
            if (!c.aberto) Info('Saída', '${br(c.reg['data_saida'])} · ${_q(c.pesoAtual(hoje), 0)} kg'),
            const Secao('Desempenho'),
            Info('Dias de cocho', '${agora.dias}'),
            Info('Peso médio', '${_q(agora.peso, 0)} kg${c.pesagem == null || !c.aberto ? '' : ' (pesado em ${br(c.pesagem!.$2)})'}'),
            Info('GMD', '${_q(agora.gmd, 3)} kg/dia${c.gmdReal(hoje) ? '' : ' (previsto; pese o lote para ter o real)'}'),
            Info('Consumo MN', c.consumoMN == null ? 'Sem trato lançado' : '${_q(c.consumoMN, 2)} kg/cab/dia'),
            Info('Consumo MS', c.consumoMS == null ? '' : '${_q(c.consumoMS, 2)} kg/cab/dia · ${_q(c.consumoPV(hoje), 2)}% do peso'),
            Info('Conversão', c.conversao(hoje) == null ? '' : '${_q(c.conversao(hoje), 2)} kg de MS por kg ganho'),
            const Secao('Custo por cabeça'),
            Info('Diária', '${moeda(c.diaria)} (ração ${moeda(c.diaria - c.custoFixoDia)} + operacional ${moeda(c.custoFixoDia)})'),
            Info('Até hoje', moeda(agora.custoCab)),
            Info('Ração no ciclo', '${moeda(c.custoAlimentar)} · ${_q(c.kgFornecido, 0)} kg fornecidos'),
            Info('@ produzidas', _q(agora.arrobasProduzidas, 2)),
            Info('Custo da @', agora.custoArroba == null ? '' : moeda(agora.custoArroba)),
            Secao(c.aberto ? 'Projeção de saída' : 'Resultado'),
            if (c.aberto) Info('Saída prevista', '${br(c.saidaPrevista(hoje))} · ${fim.dias} dias'),
            Info('Peso de saída', '${_q(fim.peso, 0)} kg · ${_q(fim.arrobasSaida, 1)} @ (${_q(c.rendSaida * 100, 1)}%)'),
            Info('Custo do cocho', '${moeda(fim.custoCab)} por cabeça'),
            Info('Boi magro', c.valorCompra > 0 ? moeda(c.valorCompra) : ''),
            Info('Equilíbrio', fim.equilibrio == null ? '' : '${moeda(fim.equilibrio)}/@'),
            Info('Arroba', fim.arroba == null ? 'Informe em Cotação da arroba' : '${moeda(fim.arroba)}/@'),
            if (fim.margem != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Margem: ${moeda(fim.margem)} por cabeça · ${moeda(fim.margem! * c.cabecas)} no curral',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: fim.margem! < 0 ? Cores.alerta : Cores.sucesso),
                ),
              ),
            if (c.aberto) ...[
              gap,
              OutlinedButton.icon(
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Encerrar o ciclo (saída do curral)'),
                onPressed: () => _encerrar(context, c),
              ),
            ],
            Secao('Leituras de cocho (${c.leituras.length})'),
            if (c.leituras.isEmpty) const Text('Nenhuma leitura ainda.'),
            for (final l in c.leituras)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(radius: 16, child: Text(l['nota'] is num ? '${l['nota']}' : '-')),
                title: Text('${br(l['data'])} · ${_q((l['kg_fornecido'] as num?)?.toDouble(), 0)} kg fornecidos'),
                subtitle: Text('Previsto ${_q((l['kg_previsto'] as num?)?.toDouble(), 0)} kg · ${l['cabecas'] ?? '-'} cab.'
                    '${l['nota'] is num ? ' · ${notasCocho[(l['nota'] as num).toInt()]?.$1 ?? ''}' : ''}'
                    '${txt(l['obs']).isEmpty ? '' : ' · ${l['obs']}'}'),
                trailing: IconButton(
                  tooltip: 'Apagar (o custo sai e o estoque volta)',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (!await confirmar(context, 'Apagar a leitura?', 'O custo do trato sai e o estoque volta.', ok: 'Apagar')) return;
                    await Db.excluir('cocho', l['id'] as int);
                  },
                ),
              ),
          ]),
        );
      },
    );
  }

  Future<void> _encerrar(BuildContext context, Ciclo c) async {
    final hoje = hojeIso();
    var data = hoje;
    final peso = TextEditingController(text: _q(c.pesoAtual(hoje), 0));
    final rend = TextEditingController(text: _q(c.rendSaida * 100, 1));
    final arroba = TextEditingController(text: c.arroba == null ? '' : _q(c.arroba, 2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Encerrar o ciclo'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DateField(label: 'Data de saída', value: data, obrigatorio: true, onChanged: (v) => set(() => data = v!)),
              gap,
              campoTexto(peso, 'Peso médio de saída', numero: true, sufixo: 'kg'),
              gap,
              campoTexto(rend, 'Rendimento de carcaça (do abate)', numero: true, sufixo: '%'),
              gap,
              campoTexto(arroba, 'Preço da arroba na venda', numero: true, sufixo: 'R\$/@'),
              gap,
              const Text('A venda dos animais é lançada em Vendas, como sempre. Aqui fica só o resultado do ciclo.'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Encerrar')),
          ],
        ),
      ),
    );
    final p = lerNumero(peso.text), r = lerNumero(rend.text), a = lerNumero(arroba.text);
    for (final t in [peso, rend, arroba]) {
      t.dispose();
    }
    if (ok != true) return;
    await encerrarCiclo(c, data: data, pesoSaida: p, rendReal: r, arroba: a);
    if (context.mounted) avisar(context, 'Ciclo encerrado. Gere o relatório no botão de PDF.');
  }
}

/// Cadastro do ciclo: curral, lote, entrada, dieta, metas e custos.
class CicloFormPage extends StatefulWidget {
  const CicloFormPage({super.key, this.ciclo});
  final Reg? ciclo;

  @override
  State<CicloFormPage> createState() => _CicloFormPageState();
}

class _CicloFormPageState extends State<CicloFormPage> {
  Reg? get c => widget.ciclo;
  String _v(String k, [int casas = 1]) => c?[k] is num ? numeroBr((c![k] as num).toDouble(), casas: casas) : '';

  late final nome = TextEditingController(text: txt(c?['nome']));
  late int? lote = c?['lote_id'] as int?;
  late String entrada = txt(c?['data_entrada']).isEmpty ? hojeIso() : txt(c?['data_entrada']);
  late final cabecas = TextEditingController(text: txt(c?['cabecas']));
  late final peso = TextEditingController(text: _v('peso_entrada', 0));
  late final compra = TextEditingController(text: _v('valor_compra', 2));
  late String origem = c?['insumo_id'] != null ? 'Insumo' : 'Fórmula';
  late int? formula = c?['formula_id'] as int?;
  late int? insumo = c?['insumo_id'] as int?;
  late final ms = TextEditingController(text: c == null ? '88' : _v('ms', 0));
  late final trato = TextEditingController(text: _v('kg_cab_dia'));
  late final gmd = TextEditingController(text: c == null ? '1,5' : _v('gmd_previsto', 2));
  late final metaPeso = TextEditingController(text: _v('meta_peso', 0));
  late final metaDias = TextEditingController(text: txt(c?['meta_dias']));
  late final rendEntrada = TextEditingController(text: c == null ? '50' : _v('rend_entrada'));
  late final rendSaida = TextEditingController(text: c == null ? numeroBr(ajustesArroba().$1 * 100) : _v('rend_saida'));
  late final fixo = TextEditingController(text: _v('custo_fixo_dia', 2));
  late final mortes = TextEditingController(text: txt(c?['mortes']));
  List<Reg> lotes = [];

  late final _campos = [nome, cabecas, peso, compra, ms, trato, gmd, metaPeso, metaDias, rendEntrada, rendSaida, fixo, mortes];

  @override
  void initState() {
    super.initState();
    Db.lotes().then((l) => mounted ? setState(() => lotes = l) : null);
  }

  @override
  void dispose() {
    for (final t in _campos) {
      t.dispose();
    }
    super.dispose();
  }

  /// Ao escolher o lote, preenche cabeças e peso médio (última pesagem).
  Future<void> _escolherLote(int? v) async {
    setState(() => lote = v);
    if (v == null) return;
    final as = await Db.animais(loteId: v, soAtivos: true);
    if (!mounted) return;
    final pesos = [for (final a in as) if (a['ultimo_peso'] is num) (a['ultimo_peso'] as num).toDouble()];
    setState(() {
      if (cabecas.text.trim().isEmpty || c == null) cabecas.text = '${as.length}';
      if (peso.text.trim().isEmpty && pesos.isNotEmpty) peso.text = numeroBr(pesos.reduce((a, b) => a + b) / pesos.length, casas: 0);
      if (nome.text.trim().isEmpty) nome.text = txt(Db.registro('lotes', v)?['nome']);
    });
  }

  Future<void> _salvar() async {
    final item = origem == 'Fórmula' ? formula : insumo;
    final pe = lerNumero(peso.text);
    if (nome.text.trim().isEmpty || pe == null || pe <= 0 || item == null) {
      return avisar(context, 'Informe o curral, o peso médio de entrada e a dieta.');
    }
    final dados = <String, Object?>{
      'nome': nome.text.trim(),
      'lote_id': lote,
      'data_entrada': entrada,
      'cabecas': lerNumero(cabecas.text)?.round(),
      'peso_entrada': pe,
      'valor_compra': lerNumero(compra.text),
      'formula_id': origem == 'Fórmula' ? formula : null,
      'insumo_id': origem == 'Insumo' ? insumo : null,
      'ms': lerNumero(ms.text) ?? 88,
      'kg_cab_dia': lerNumero(trato.text),
      'gmd_previsto': lerNumero(gmd.text),
      'meta_peso': lerNumero(metaPeso.text),
      'meta_dias': lerNumero(metaDias.text)?.round(),
      'rend_entrada': lerNumero(rendEntrada.text),
      'rend_saida': lerNumero(rendSaida.text),
      'custo_fixo_dia': lerNumero(fixo.text),
      if (lote == null) 'mortes': lerNumero(mortes.text)?.round(),
    };
    if (c == null) {
      await Db.inserir('confinamentos', {...dados, 'propriedade_id': Db.pid});
    } else {
      await Db.atualizar('confinamentos', c!['id'] as int, dados);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    if (!await confirmar(context, 'Excluir o ciclo?',
        'O ciclo e as leituras de cocho somem. Os custos do trato já lançados continuam em Custos.', ok: 'Excluir')) {
      return;
    }
    await Db.excluir('confinamentos', c!['id'] as int);
    if (!mounted) return;
    Navigator.of(context)
      ..pop()
      ..pop();
  }

  Future<void> _reabrir() async {
    await Db.atualizar('confinamentos', c!['id'] as int, {'encerrado': false, 'data_saida': null, 'cabecas_saida': null});
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fs = [for (final f in formulas()) {...f, 'rotulo': '${f['nome']} (${f['tipo'] ?? ''})'}];
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Novo ciclo' : 'Editar ciclo'),
        actions: [
          if (c != null && c!['encerrado'] == true)
            IconButton(tooltip: 'Reabrir o ciclo', icon: const Icon(Icons.lock_open), onPressed: _reabrir),
          if (c != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      bottomNavigationBar: BotaoSalvar(onPressed: _salvar),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        escolhaId('Lote no confinamento', lote, lotes, _escolherLote, vazio: 'Sem lote (só o número de cabeças)'),
        gap,
        campoTexto(nome, 'Curral ou baia *'),
        gap,
        DateField(label: 'Data de entrada', value: entrada, obrigatorio: true, onChanged: (v) => setState(() => entrada = v!)),
        gap,
        Row(children: [
          Expanded(child: campoTexto(cabecas, 'Cabeças na entrada', numero: true)),
          const SizedBox(width: 12),
          Expanded(child: campoTexto(peso, 'Peso médio de entrada *', numero: true, sufixo: 'kg')),
        ]),
        gap,
        campoTexto(compra, 'Valor do boi magro por cabeça (opcional)', numero: true, sufixo: 'R\$'),
        if (lote == null) ...[gap, campoTexto(mortes, 'Mortes no ciclo', numero: true)],
        const Secao('Dieta do cocho'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Fórmula', label: Text('Fórmula/ração')),
            ButtonSegment(value: 'Insumo', label: Text('Insumo do estoque')),
          ],
          selected: {origem},
          onSelectionChanged: (s) => setState(() => origem = s.first),
        ),
        gap,
        if (origem == 'Fórmula')
          escolhaId('Fórmula *', formula, fs, (v) => setState(() => formula = v), vazio: '—', campo: 'rotulo')
        else
          escolhaId('Insumo *', insumo, insumos(), (v) => setState(() => insumo = v), vazio: '—'),
        gap,
        Row(children: [
          Expanded(child: campoTexto(trato, 'Trato inicial', numero: true, sufixo: 'kg/cab/dia')),
          const SizedBox(width: 12),
          Expanded(child: campoTexto(ms, 'Matéria seca', numero: true, sufixo: '%')),
        ]),
        const Secao('Metas e contas'),
        Row(children: [
          Expanded(child: campoTexto(metaPeso, 'Peso de saída', numero: true, sufixo: 'kg')),
          const SizedBox(width: 12),
          Expanded(child: campoTexto(metaDias, 'ou dias de cocho', numero: true)),
        ]),
        gap,
        campoTexto(gmd, 'GMD previsto (até pesar o lote)', numero: true, sufixo: 'kg/dia'),
        gap,
        Row(children: [
          Expanded(child: campoTexto(rendEntrada, 'Rendimento na entrada', numero: true, sufixo: '%')),
          const SizedBox(width: 12),
          Expanded(child: campoTexto(rendSaida, 'Rendimento na saída', numero: true, sufixo: '%')),
        ]),
        gap,
        campoTexto(fixo, 'Custo operacional por cabeça por dia (mão de obra, máquinas)', numero: true, sufixo: 'R\$'),
        const SizedBox(height: 8),
        const Text('Matéria seca: ração e proteinado ~88%; dieta com silagem, uns 45 a 60%. '
            'O custo da ração vem dos tratos lançados; o operacional soma na diária.'),
      ]),
    );
  }
}

/// Leitura de cocho em série, curral por curral: a nota de 0 a 4 ajusta o trato
/// de ontem; confirma os quilos fornecidos e passa para o próximo. No fim,
/// manda o trato do dia para o tratorista pelo WhatsApp.
class LeituraCochoPage extends StatefulWidget {
  const LeituraCochoPage({super.key, this.so});

  /// Só este ciclo (aberto da ficha do ciclo).
  final int? so;

  @override
  State<LeituraCochoPage> createState() => _LeituraCochoPageState();
}

class _LeituraCochoPageState extends State<LeituraCochoPage> {
  String data = hojeIso();
  late final List<int> _ids = [
    for (final c in ciclos(soAbertos: true))
      if (widget.so == null || c.id == widget.so) c.id,
  ];
  int _i = 0;
  int? _nota;
  bool _baixar = true;
  final _kg = TextEditingController();
  final _obs = TextEditingController();
  bool _salvando = false;

  Ciclo? get _c {
    if (_i >= _ids.length) return null;
    final r = Db.registro('confinamentos', _ids[_i]);
    return r == null ? null : Ciclo(r);
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _kg.dispose();
    _obs.dispose();
    super.dispose();
  }

  /// Preenche com o lançamento do dia, se houver, ou com a sugestão.
  void _carregar() {
    final c = _c;
    if (c == null) return;
    final l = c.leituraDoDia(data);
    _nota = (l?['nota'] as num?)?.toInt();
    _obs.text = txt(l?['obs']);
    final kg = l == null ? c.trato(data, _nota) : (l['kg_fornecido'] as num?)?.toDouble() ?? 0;
    _kg.text = numeroBr(kg, casas: 0);
  }

  void _escolherNota(int n) => setState(() {
        _nota = n;
        _kg.text = numeroBr(_c!.trato(data, n), casas: 0);
      });

  Future<void> _salvar() async {
    final c = _c;
    final kg = lerNumero(_kg.text);
    if (c == null || kg == null || kg < 0) return avisar(context, 'Informe os quilos fornecidos.');
    setState(() => _salvando = true);
    try {
      await registrarCocho(c,
          data: data, nota: _nota, kgPrevisto: c.trato(data, _nota), kgFornecido: kg, baixar: _baixar, obs: nulo(_obs.text));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
    if (!mounted) return;
    setState(() {
      _i++;
      _carregar();
    });
  }

  Future<void> _whats() async {
    final tratos = <(Ciclo, double)>[
      for (final id in _ids)
        if (Db.registro('confinamentos', id) case final r?)
          (Ciclo(r), (Ciclo(r).leituraDoDia(data)?['kg_fornecido'] as num?)?.toDouble() ?? Ciclo(r).trato(data, null)),
    ];
    final t = textoTratoWhats(tratos, data, fazenda: txt(Db.registro('propriedades', Db.pid)?['nome']));
    await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(t)}'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leitura de cocho'),
        actions: [
          IconButton(tooltip: 'Mandar o trato pelo WhatsApp', icon: const Icon(Icons.share), onPressed: _ids.isEmpty ? null : _whats),
        ],
      ),
      bottomNavigationBar: c == null ? null : BotaoSalvar(onPressed: _salvando ? null : _salvar, texto: 'Salvar e próximo'),
      body: _ids.isEmpty
          ? const Vazio('Nenhum ciclo aberto.')
          : c == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle, color: Cores.sucesso, size: 64),
                      gap,
                      Text('Leitura feita nos ${_ids.length} curral(is).', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
                      gap,
                      FilledButton.icon(icon: const Icon(Icons.share), label: const Text('Mandar o trato pelo WhatsApp'), onPressed: _whats),
                      TextButton(
                          onPressed: () => setState(() {
                                _i = 0;
                                _carregar();
                              }),
                          child: const Text('Rever os currais')),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  DateField(
                      label: 'Data',
                      value: data,
                      obrigatorio: true,
                      permitirFuturo: false,
                      onChanged: (v) => setState(() {
                            data = v!;
                            _carregar();
                          })),
                  gap,
                  Text('Curral ${_i + 1} de ${_ids.length}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  Text(c.nome, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${c.cabecas} cab. · ${c.dieta} · ${c.diasDeCocho(data)} dias de cocho'),
                  if (c.leituraDoDia(data) != null)
                    const Text('Já lançado hoje: salvar troca o lançamento.', style: TextStyle(color: Cores.alerta)),
                  const Secao('Como está o cocho?'),
                  for (final e in notasCocho.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _nota == e.key
                          ? FilledButton(
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                              onPressed: () => _escolherNota(e.key),
                              child: Text('${e.key} · ${e.value.$1}'),
                            )
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                              onPressed: () => _escolherNota(e.key),
                              child: Text('${e.key} · ${e.value.$1}'),
                            ),
                    ),
                  gap,
                  Text(
                    _nota == null
                        ? 'Trato sugerido: ${_q(c.trato(data, null), 0)} kg (escolha a nota para ajustar).'
                        : 'Nota $_nota: ${textoAjuste(_nota)} → ${_q(c.trato(data, _nota), 0)} kg '
                            '(${_q(c.cabecas > 0 ? c.trato(data, _nota) / c.cabecas : 0, 2)} kg/cab).',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  gap,
                  campoTexto(_kg, 'Quilos fornecidos no curral', numero: true, sufixo: 'kg'),
                  gap,
                  campoTexto(_obs, 'Observação (opcional)'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _baixar,
                    onChanged: (v) => setState(() => _baixar = v),
                    title: const Text('Lançar o custo e tirar do estoque'),
                  ),
                  if (_i > 0 || _i < _ids.length - 1)
                    Row(children: [
                      if (_i > 0)
                        TextButton.icon(
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('Anterior'),
                            onPressed: () => setState(() {
                                  _i--;
                                  _carregar();
                                })),
                      const Spacer(),
                      TextButton.icon(
                          icon: const Icon(Icons.chevron_right),
                          label: const Text('Pular'),
                          onPressed: () => setState(() {
                                _i++;
                                _carregar();
                              })),
                    ]),
                ]),
    );
  }
}
