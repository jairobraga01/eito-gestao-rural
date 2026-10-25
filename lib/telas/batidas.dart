import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/contatos.dart' show fornecedoresDe;
import '../dados/cotacao_compra.dart' show telefoneWhats;
import '../dados/db.dart';
import '../dados/estoque.dart';
import '../dados/proteinado.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';

/// Abre o WhatsApp com a batida para o fornecedor (no número do cadastro, se houver).
Future<void> enviarBatidaWhats(Reg formula, {required double batidas, required String data, Reg? fornecedor, Set<int> fora = const {}}) async {
  final texto = textoBatidaWhats(formula,
      batidas: batidas,
      data: data,
      fornecedor: txt(fornecedor?['nome']),
      fazenda: txt(Db.registro('propriedades', Db.pid)?['nome']),
      foraDoEstoque: fora);
  final n = telefoneWhats(txt(fornecedor?['telefone']));
  final t = Uri.encodeComponent(texto);
  await launchUrl(Uri.parse(n == null ? 'https://wa.me/?text=$t' : 'https://wa.me/$n?text=$t'), mode: LaunchMode.externalApplication);
}

/// Caixas "Todos os insumos de fora do estoque" e uma por insumo da fórmula.
List<Widget> marcarInsumosDeFora(CalculoFormula c, Set<int> fora, void Function(void Function()) set) {
  final ids = [for (final l in c.linhas) if (l.insumo?['id'] is int) l.insumo!['id'] as int];
  if (ids.isEmpty) return const [];
  final todos = ids.every(fora.contains);
  return [
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      tristate: true,
      value: todos ? true : (ids.any(fora.contains) ? null : false),
      title: const Text('Todos os insumos de fora do estoque', style: TextStyle(fontWeight: FontWeight.w700)),
      onChanged: (_) => set(() => todos ? fora.removeAll(ids) : fora.addAll(ids)),
    ),
    for (final l in c.linhas)
      if (l.insumo?['id'] is int)
        CheckboxListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 24),
          controlAffinity: ListTileControlAffinity.leading,
          value: fora.contains(l.insumo!['id']),
          title: Text(l.nome),
          onChanged: (v) => set(() => v! ? fora.add(l.insumo!['id'] as int) : fora.remove(l.insumo!['id'])),
        ),
  ];
}

String _pct(double? v) => v == null ? '' : '${v >= 0 ? '+' : ''}${numeroBr(v, casas: 1)}%';

/// Gera a batida de uma fórmula: mostra o custo com os preços de hoje, tira os
/// ingredientes do estoque, lança o custo e guarda a batida no histórico.
class GerarBatidaPage extends StatefulWidget {
  const GerarBatidaPage({super.key, this.formulaFixa});

  /// Fórmula já escolhida (vindo da tela da fórmula); null = a pessoa escolhe.
  final Reg? formulaFixa;

  @override
  State<GerarBatidaPage> createState() => _GerarBatidaPageState();
}

class _GerarBatidaPageState extends State<GerarBatidaPage> {
  final formulasLista = formulas();
  int? formulaId;
  int? loteId;
  List<Reg> lotes = [];
  String data = hojeIso();
  final qtd = TextEditingController(text: '1');
  bool salvando = false;

  /// Insumos que vêm de fora do estoque: entram no custo, mas não baixam o estoque.
  final fora = <int>{};
  int? fornecedorId;
  final fornecedores = fornecedoresDe('Insumos');

  @override
  void initState() {
    super.initState();
    qtd.addListener(() => setState(() {}));
    Db.lotes(soAtivos: true).then((v) {
      if (mounted) setState(() => lotes = v);
    });
  }

  @override
  void dispose() {
    qtd.dispose();
    super.dispose();
  }

  Reg? get formula => widget.formulaFixa ?? formulasLista.where((f) => f['id'] == formulaId).firstOrNull;
  double get batidas => lerNumero(qtd.text) ?? 0;

  Future<void> _gerar() async {
    final f = formula;
    if (f == null) return avisar(context, 'Escolha a fórmula.');
    if (batidas <= 0) return avisar(context, 'Informe quantas batidas.');
    setState(() => salvando = true);
    await registrarBatida(f, data: data, batidas: batidas, loteId: loteId, foraDoEstoque: _foraDaFormula(f), fornecedor: txt(fornecedor?['nome']));
    if (!mounted) return;
    avisar(context, fora.isEmpty
        ? 'Batida gerada: custo lançado, estoque baixado e histórico guardado.'
        : 'Batida gerada: custo lançado e histórico guardado. Os insumos de fora não saíram do estoque.');
    Navigator.pop(context, true);
  }

  Reg? get fornecedor => fornecedores.where((c) => c['id'] == fornecedorId).firstOrNull;

  List<int> _idsDa(CalculoFormula c) => [for (final l in c.linhas) if (l.insumo?['id'] is int) l.insumo!['id'] as int];

  /// Só os marcados que estão nesta fórmula (a pessoa pode ter trocado de fórmula).
  Set<int> _foraDaFormula(Reg f) => fora.intersection(_idsDa(CalculoFormula(f)).toSet());

  Future<void> _enviarWhats() async {
    final f = formula;
    if (f == null) return avisar(context, 'Escolha a fórmula.');
    if (batidas <= 0) return avisar(context, 'Informe quantas batidas.');
    await enviarBatidaWhats(f, batidas: batidas, data: data, fornecedor: fornecedor, fora: _foraDaFormula(f));
  }

  @override
  Widget build(BuildContext context) {
    final f = formula;
    final c = f == null ? null : CalculoFormula(f);
    final ids = c == null ? <int>[] : _idsDa(c);
    return Scaffold(
      appBar: AppBar(title: const Text('Gerar batida')),
      bottomNavigationBar: BotaoSalvar(onPressed: salvando ? null : _gerar, texto: 'Gerar batida'),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        if (widget.formulaFixa != null)
          Text('Fórmula: ${txt(widget.formulaFixa!['nome'])}', style: Theme.of(context).textTheme.titleMedium)
        else if (formulasLista.isEmpty)
          const Text('Nenhuma fórmula. Cadastre em Fórmulas: Proteínados/Rações.')
        else
          escolhaId('Fórmula *', formulaId, formulasLista, (v) => setState(() => formulaId = v), vazio: 'Escolha'),
        if (f == null && formulasLista.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Escolha a fórmula para marcar os insumos de fora do estoque e enviar ao fornecedor.',
                style: TextStyle(color: Colors.black54)),
          ),
        gap,
        Row(children: [
          Expanded(child: campoTexto(qtd, 'Batidas', numero: true)),
          const SizedBox(width: 12),
          Expanded(child: DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v!))),
        ]),
        gap,
        escolhaId('Lote que leva o custo (opcional)', loteId, lotes, (v) => setState(() => loteId = v), vazio: 'Geral'),
        if (c != null && ids.isNotEmpty) ...[
          const Secao('Insumos de fora do estoque'),
          const Text('Marque o que veio de fora (comprado para esta batida ou entregue pelo fornecedor). '
              'Entra no custo, mas não sai do estoque.', style: TextStyle(color: Colors.black54)),
          ...marcarInsumosDeFora(c, fora, setState),
        ],
        if (c != null) ...[
          const Secao('Fornecedor'),
          if (fornecedores.isEmpty)
            const Text('Nenhum fornecedor cadastrado. Cadastre em Cadastro de Fornecedores.')
          else
            escolhaId('Fornecedor (opcional)', fornecedorId, fornecedores, (v) => setState(() => fornecedorId = v), vazio: 'Nenhum'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Enviar a batida pelo WhatsApp'),
            onPressed: _enviarWhats,
          ),
        ],
        if (c != null) ...[
          const Secao('Conta com os preços de hoje'),
          for (final l in c.linhas)
            Builder(builder: (_) {
              final precisa = l.kg * batidas;
              final id = l.insumo?['id'] as int?;
              final tem = id == null ? null : saldo(id);
              final deFora = id != null && fora.contains(id);
              final falta = !deFora && tem != null && movimentos(id!).isNotEmpty && tem < precisa;
              return ListTile(
                dense: true,
                title: Text(l.nome),
                subtitle: Text([
                  '${numeroBr(precisa, casas: 1)} kg',
                  l.custo == null ? 'sem preço' : '${moeda(l.custo! / l.kg)}/kg',
                  if (deFora) 'de fora do estoque',
                  if (falta) 'estoque ${numeroBr(tem, casas: 1)} kg: falta',
                ].join(' · ')),
                trailing: Text(l.custo == null ? '—' : moeda(l.custo! * batidas)),
                textColor: falta ? Cores.alerta : null,
              );
            }),
          if (c.sacaria > 0 || c.maoDeObra > 0)
            ListTile(
              dense: true,
              title: const Text('Sacaria e mão de obra'),
              trailing: Text(moeda((c.sacaria + c.maoDeObra) * batidas)),
            ),
          const Divider(),
          ListTile(
            title: Text('${numeroBr(c.kgBatida * batidas, casas: 1)} kg de ${txt(f!['nome'])}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(c.precoKg == null ? '' : '${moeda(c.precoKg)} por quilo'),
            trailing: Text(moeda(c.custoBatida * batidas), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          if (c.semPreco.isNotEmpty)
            Text('Sem preço: ${c.semPreco.join(', ')}. Lance o preço no estoque de insumos para o custo ficar certo.',
                style: const TextStyle(color: Cores.alerta)),
        ],
      ]),
    );
  }
}

/// Histórico das batidas, com a evolução do custo do quilo.
class BatidasPage extends StatefulWidget {
  const BatidasPage({super.key});

  @override
  State<BatidasPage> createState() => _BatidasPageState();
}

class _BatidasPageState extends State<BatidasPage> {
  int? formulaId;

  Future<void> _detalhe(Reg b) async {
    final itens = [for (final i in (b['itens'] as List?) ?? const []) Map<String, Object?>.from(i as Map)];
    final apagar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${txt(b['formula_nome'])} · ${br(b['data'])}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${numeroBr((b['batidas'] as num).toDouble(), casas: 1)} batida(s) · ${numeroBr((b['kg'] as num).toDouble(), casas: 1)} kg'),
            if (txt(b['fornecedor']).isNotEmpty) Text('Fornecedor: ${txt(b['fornecedor'])}'),
            Text('Custo ${moeda(b['custo_total'] as num?)}${b['custo_kg'] == null ? '' : ' · ${moeda(b['custo_kg'] as num)}/kg'}'),
            const SizedBox(height: 8),
            for (final i in itens)
              Text('${txt(i['nome'])}: ${numeroBr((i['kg'] as num).toDouble(), casas: 1)} kg'
                  '${i['preco_kg'] == null ? '' : ' a ${moeda(i['preco_kg'] as num)}/kg = ${moeda(i['custo'] as num?)}'}'
                  '${i['fora_estoque'] == true ? ' (de fora do estoque)' : ''}'),
            if ((b['sacaria'] as num? ?? 0) > 0 || (b['mao_obra'] as num? ?? 0) > 0)
              Text('Sacaria ${moeda(b['sacaria'] as num?)} · mão de obra ${moeda(b['mao_obra'] as num?)}'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar', style: TextStyle(color: Cores.alerta))),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
    if (apagar == true && mounted) {
      if (await confirmar(context, 'Apagar a batida?', 'O custo some e o que saiu do estoque volta.', ok: 'Apagar')) {
        try {
          await excluirBatida(b);
        } on StateError catch (e) {
          if (mounted) avisar(context, e.message);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Histórico de batidas',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Gerar batida'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GerarBatidaPage())),
      ),
      corpo: AoMudar<List<Reg>>(
        carregar: () async => batidasFeitas(),
        builder: (context, todas) {
          if (todas.isEmpty) {
            return const Vazio('Nenhuma batida ainda. Gere a primeira pelo botão abaixo.', icone: Icons.science_outlined);
          }
          final nomes = <int, String>{};
          for (final b in todas) {
            final id = (b['formula_id'] as num?)?.toInt();
            if (id != null) nomes[id] = txt(b['formula_nome']);
          }
          final lista = formulaId == null ? todas : [for (final b in todas) if (b['formula_id'] == formulaId) b];
          final comCusto = [for (final b in lista) if (b['custo_kg'] is num) b];
          final primeira = comCusto.isEmpty ? null : (comCusto.last['custo_kg'] as num).toDouble();
          final ultima = comCusto.isEmpty ? null : (comCusto.first['custo_kg'] as num).toDouble();
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<int?>(
                initialValue: formulaId,
                decoration: const InputDecoration(labelText: 'Fórmula'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Todas')),
                  for (final e in nomes.entries) DropdownMenuItem<int?>(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => formulaId = v),
              ),
            ),
            if (formulaId != null && primeira != null && ultima != null && comCusto.length > 1)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Custo do quilo: ${moeda(primeira)} na primeira batida, ${moeda(ultima)} na última '
                      '(${_pct(variacaoPct(primeira, ultima))}). '
                      'Menor ${moeda(comCusto.map((b) => (b['custo_kg'] as num).toDouble()).reduce((a, b) => a < b ? a : b))}, '
                      'maior ${moeda(comCusto.map((b) => (b['custo_kg'] as num).toDouble()).reduce((a, b) => a > b ? a : b))}.'),
                ),
              ),
            for (var i = 0; i < lista.length; i++)
              Builder(builder: (_) {
                final b = lista[i];
                // Batida anterior da mesma fórmula, para ver a evolução.
                final anterior = lista.skip(i + 1).where((x) => x['formula_id'] == b['formula_id'] && x['custo_kg'] is num).firstOrNull;
                final v = variacaoPct((anterior?['custo_kg'] as num?)?.toDouble(), (b['custo_kg'] as num?)?.toDouble());
                return ListTile(
                  title: Text('${txt(b['formula_nome'])} · ${br(b['data'])}'),
                  subtitle: Text([
                    '${numeroBr((b['batidas'] as num).toDouble(), casas: 1)} batida(s) · ${numeroBr((b['kg'] as num).toDouble(), casas: 1)} kg',
                    if (b['custo_kg'] != null) '${moeda(b['custo_kg'] as num)}/kg',
                    if (v != null) 'vs. anterior ${_pct(v)}',
                  ].join(' · ')),
                  trailing: Text(moeda(b['custo_total'] as num?), style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => _detalhe(b),
                );
              }),
          ]);
        },
      ),
    );
  }
}
