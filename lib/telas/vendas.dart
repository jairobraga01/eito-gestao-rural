import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/indicadores.dart';
import '../dados/negocio.dart';
import '../util/util.dart';
import '../widgets/prazo.dart';
import 'base.dart';

/// Saídas separadas em Vendas, Mortes e Outras Causas (consumo, transferência, doação).
enum TipoSaidas { vendas, mortes, outras }

class SaidasPage extends StatelessWidget {
  const SaidasPage({super.key, this.tipo = TipoSaidas.vendas});
  final TipoSaidas tipo;

  bool _entra(Reg s) => switch (tipo) {
        TipoSaidas.vendas => s['tipo'] == 'Venda',
        TipoSaidas.mortes => s['tipo'] == 'Morte',
        TipoSaidas.outras => s['tipo'] != 'Venda' && s['tipo'] != 'Morte',
      };

  @override
  Widget build(BuildContext context) {
    final (titulo, novo, vazio, tipoInicial) = switch (tipo) {
      TipoSaidas.vendas => ('Vendas', 'Nova venda', 'Nenhuma venda registrada.', 'Venda'),
      TipoSaidas.mortes => ('Mortes', 'Registrar morte', 'Nenhuma morte registrada.', 'Morte'),
      TipoSaidas.outras => ('Outras Causas', 'Nova saída', 'Nenhuma saída por outras causas.', 'Consumo'),
    };
    return Pagina(
      titulo: titulo,
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: Text(novo),
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => SaidaFormPage(tipoInicial: tipoInicial))),
      ),
      corpo: AoMudar<List<Reg>>(
        carregar: () async => (await Db.saidas()).where(_entra).toList(),
        builder: (context, lista) {
          if (lista.isEmpty) {
            return Vazio(vazio, icone: Icons.arrow_circle_up_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final s = lista[i];
              final venda = s['tipo'] == 'Venda';
              return ListTile(
                leading: const Icon(Icons.arrow_circle_up_outlined, color: Colors.red, size: 30),
                title: Text('${s['tipo']} · ${s['quantidade'] ?? 0} cab.'
                    '${venda && s['valor_total'] != null ? ' · ${moeda(s['valor_total'] as num)}${s['bruto'] is num ? ' líquido' : ''}' : ''}'),
                subtitle: Text([
                  br(s['data']),
                  if (txt(s['destino']).isNotEmpty) txt(s['destino']),
                  if (txt(s['brincos']).isNotEmpty) 'Brincos: ${s['brincos']}',
                ].join(' · ')),
                onTap: () => _detalhe(context, s),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _detalhe(BuildContext context, Reg s) async {
    final qtd = (s['quantidade'] as int?) ?? 0;
    final peso = s['peso_total'] as num?;
    final valor = s['valor_total'] as num?;
    final lucro = lucroDaVenda(s);
    num z(String k) => s[k] as num? ?? 0;
    final excluir = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${s['tipo']} de ${br(s['data'])}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Info('Cabeças', '$qtd'),
              Info('Peso total', kg(peso)),
              if (peso != null && qtd > 0) Info('Peso médio', kg(peso / qtd)),
              if (s['bruto'] is num) ...[
                if (s['por_arroba'] == true) ...[
                  Info('Arrobas', '${num1(z('arrobas'))} @ (rend. ${num1(z('rendimento_pct'))}%)'),
                  Info('Preço da arroba', moeda(z('preco'))),
                ] else
                  Info('Preço por cabeça', moeda(z('preco'))),
                Info('Valor bruto', moeda(z('bruto'))),
                if (z('funrural') > 0) Info('Funrural (${num1(z('funrural_pct'))}%)', '− ${moeda(z('funrural'))}'),
                for (final (k, r) in [('fundepec', 'Fundepec'), ('nota', 'Nota'), ('frete', 'Frete'), ('outros', 'Outros')])
                  if (z(k) > 0) Info(r, '− ${moeda(z(k))}'),
              ],
              Info(s['bruto'] is num ? 'Valor líquido' : 'Valor total', moeda(valor)),
              if (valor != null && qtd > 0) Info('Líquido por cabeça', moeda(valor / qtd)),
              if (lucro != null) ...[
                Info('Custo dos animais', moeda(lucro.custo)),
                Info(lucro.lucro >= 0 ? 'Lucro' : 'Prejuízo', moeda(lucro.lucro)),
              ],
              if (valor != null && peso != null && peso > 0) Info('Por kg vivo', moeda(valor / peso)),
              Info('Comprador / destino', txt(s['destino'])),
              Info('Brincos', txt(s['brincos'])),
              Info('Observações', txt(s['obs'])),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fechar')),
        ],
      ),
    );
    if (excluir != true || !context.mounted) return;
    if (await confirmar(context, 'Excluir saída?',
        'O registro será apagado e os animais voltarão a ficar ativos no rebanho.',
        ok: 'Excluir')) {
      await Db.excluirSaida(s['id'] as int);
      await apagarParcelasAbertas('saida:${s['id']}');
    }
  }
}

class SaidaFormPage extends StatefulWidget {
  const SaidaFormPage({super.key, this.animais = const [], this.tipoInicial = 'Venda'});

  /// Animais já escolhidos (ex.: saída lançada da ficha ou do Modo Curral).
  final List<Reg> animais;

  /// Tipo já marcado ao abrir (Venda, Morte...).
  final String tipoInicial;

  @override
  State<SaidaFormPage> createState() => _SaidaFormPageState();
}

class _SaidaFormPageState extends State<SaidaFormPage> {
  late String? tipo = widget.tipoInicial;
  String data = hojeIso();
  late List<Reg> animais = [...widget.animais];
  final peso = TextEditingController();
  final valor = TextEditingController();
  bool porArroba = true;
  late final rendimento = TextEditingController(text: num1(rendimentoVendaPadrao()));
  late final funrural = TextEditingController(text: num1(funruralPadrao()));
  final fundepec = TextEditingController();
  final nota = TextEditingController();
  final frete = TextEditingController();
  final outros = TextEditingController();
  bool aPrazo = false;
  final parcelas = TextEditingController(text: '1');
  late String primeiro = vencimentoSugerido(data);
  final destino = TextEditingController();
  final obs = TextEditingController();
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    peso.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [peso, valor, parcelas, rendimento, funrural, fundepec, nota, frete, outros, destino, obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolher() async {
    final r = await pickAnimais(context, iniciais: [for (final a in animais) a['id'] as int]);
    if (r != null) setState(() => animais = r);
  }

  void _somarUltimosPesos() {
    final pesos = animais.map((a) => a['ultimo_peso'] as num?).whereType<num>().toList();
    if (pesos.isEmpty) {
      avisar(context, 'Os animais escolhidos não têm pesagem.');
      return;
    }
    peso.text = num1(pesos.fold<num>(0, (a, b) => a + b));
    setState(() {});
    if (pesos.length < animais.length) {
      avisar(context, 'Somados ${pesos.length} de ${animais.length} (alguns sem pesagem).');
    }
  }

  double _v(TextEditingController c) => (lerNumero(c.text) ?? 0).toDouble();

  ContaVenda? _conta() {
    final v = lerNumero(valor.text);
    if (tipo != 'Venda' || v == null) return null;
    return ContaVenda(
      cabecas: animais.length,
      porArroba: porArroba,
      preco: v.toDouble(),
      pesoTotal: lerNumero(peso.text)?.toDouble(),
      rendimentoPct: _v(rendimento),
      funruralPct: _v(funrural),
      fundepec: _v(fundepec),
      nota: _v(nota),
      frete: _v(frete),
      outros: _v(outros),
    );
  }

  Widget _numero(TextEditingController c, String label, {String? sufixo, String? prefixo}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: sufixo, prefixText: prefixo),
        onChanged: (_) => setState(() {}),
      );

  /// Venda e consumo de animal em carência de medicamento (abate antes da hora).
  List<Carencia> get _carencia => tipo == 'Venda' || tipo == 'Consumo'
      ? emCarencia([for (final a in animais) a['id'] as int], data)
      : const [];

  Future<void> salvar() async {
    if (animais.isEmpty) {
      avisar(context, 'Selecione os animais.');
      return;
    }
    final carencia = _carencia;
    if (carencia.isNotEmpty) {
      final seguir = await confirmar(
        context,
        'Animais em carência',
        '${carencia.length} animal(is) ainda em carência de medicamento:\n\n'
            '${carencia.map((c) => '${c.animal['brinco']}: ${c.produto}, liberado em ${br(c.libera)}').join('\n')}\n\n'
            'Vender para abate antes disso é proibido. Registrar mesmo assim?',
        ok: 'Registrar mesmo assim',
      );
      if (!seguir || !mounted) return;
    }
    final conta = _conta();
    if (conta != null && conta.porArroba && conta.arrobas == null) {
      avisar(context, 'Informe o peso total para vender por arroba.');
      return;
    }
    final ok = await confirmar(
      context,
      'Confirmar ${tipo!.toLowerCase()}',
      '${animais.length} animal(is) sairão do rebanho ativo.',
    );
    if (!ok) return;
    setState(() => salvando = true);
    if (conta != null) {
      await lembrarAjustesNegocio({
        'funrural_pct': conta.funruralPct,
        if (conta.porArroba) 'rendimento_pct': conta.rendimentoPct,
      });
    }
    final id = await Db.registrarSaida({
      'tipo': tipo,
      'data': data,
      'peso_total': lerNumero(peso.text),
      'valor_total': conta?.liquido,
      if (conta != null) ...{
        'por_arroba': conta.porArroba,
        'preco': conta.preco,
        if (conta.porArroba) ...{'arrobas': conta.arrobas, 'rendimento_pct': conta.rendimentoPct},
        'bruto': conta.bruto,
        'funrural_pct': conta.funruralPct,
        'funrural': conta.funrural,
        'fundepec': conta.fundepec,
        'nota': conta.nota,
        'frete': conta.frete,
        'outros': conta.outros,
      },
      'destino': nulo(destino.text),
      'obs': nulo(obs.text),
    }, [for (final a in animais) a['id'] as int]);
    if (conta != null && aPrazo) {
      await lancarParcelas(
        receita: true,
        origem: 'saida:$id',
        total: conta.liquido,
        parcelas: (int.tryParse(parcelas.text.trim()) ?? 1).clamp(1, 120),
        primeiro: primeiro,
        descricao: 'Venda de ${animais.length} cab.${destino.text.trim().isEmpty ? '' : ' para ${destino.text.trim()}'}',
        participante: nulo(destino.text),
      );
    }
    if (!mounted) return;
    avisar(context, 'Saída registrada.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final venda = tipo == 'Venda';
    final p = lerNumero(peso.text);
    final conta = _conta();
    final v = conta?.liquido;
    final n = animais.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Nova saída')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          escolha('Tipo', tipo, statusPorSaida.keys.toList(), (x) => setState(() => tipo = x)),
          gap,
          DateField(
              label: 'Data',
              value: data,
              obrigatorio: true,
              onChanged: (x) => setState(() {
                    data = x!;
                    primeiro = vencimentoSugerido(data);
                  })),
          gap,
          OutlinedButton.icon(
            icon: const Icon(Icons.checklist),
            label: Text(n == 0 ? 'Selecionar animais' : '$n animal(is) selecionado(s) – alterar'),
            onPressed: _escolher,
          ),
          if (n > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in animais)
                    InputChip(
                      label: Text(txt(a['brinco'])),
                      onDeleted: () => setState(() => animais = [...animais]..remove(a)),
                    ),
                ],
              ),
            ),
          if (_carencia.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 12),
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.block),
                title: Text('${_carencia.length} animal(is) em carência nesta data'),
                subtitle: Text(_carencia.map((c) => '${c.animal['brinco']} até ${br(c.libera)}').join(' · ')),
              ),
            ),
          gap,
          Row(
            children: [
              Expanded(child: campoTexto(peso, 'Peso total vivo', numero: true, sufixo: 'kg')),
              IconButton(
                tooltip: 'Somar últimas pesagens',
                icon: const Icon(Icons.functions),
                onPressed: n == 0 ? null : _somarUltimosPesos,
              ),
            ],
          ),
          if (venda) ...[
            gap,
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Por arroba')),
                ButtonSegment(value: false, label: Text('Por cabeça')),
              ],
              selected: {porArroba},
              onSelectionChanged: (s) => setState(() => porArroba = s.first),
            ),
            gap,
            Row(children: [
              Expanded(
                  flex: 2,
                  child: _numero(valor, porArroba ? 'Preço da arroba' : 'Preço por cabeça', prefixo: r'R$ ')),
              if (porArroba) ...[
                const SizedBox(width: 8),
                Expanded(child: _numero(rendimento, 'Rendimento', sufixo: '%')),
              ],
            ]),
            if (porArroba)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Arrobas = peso × rendimento ÷ 15. Use 100% se o peso já é de carcaça.',
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
              ),
            gap,
            const Text('Descontos', style: TextStyle(fontWeight: FontWeight.w700)),
            Row(children: [
              Expanded(child: _numero(funrural, 'Funrural', sufixo: '%')),
              const SizedBox(width: 8),
              Expanded(child: _numero(fundepec, 'Fundepec', prefixo: r'R$ ')),
              const SizedBox(width: 8),
              Expanded(child: _numero(nota, 'Nota', prefixo: r'R$ ')),
            ]),
            gap,
            Row(children: [
              Expanded(child: _numero(frete, 'Frete', prefixo: r'R$ ')),
              const SizedBox(width: 8),
              Expanded(child: _numero(outros, 'Outros', prefixo: r'R$ ')),
            ]),
            CamposPrazo(
              receita: true,
              aPrazo: aPrazo,
              parcelas: parcelas,
              primeiro: primeiro,
              onAPrazo: (x) => setState(() => aPrazo = x),
              onPrimeiro: (x) => setState(() => primeiro = x),
              onMudou: () => setState(() {}),
            ),
          ],
          gap,
          campoTexto(destino, venda ? 'Comprador' : 'Destino / causa'),
          gap,
          campoTexto(obs, 'Observações', linhas: 3),
          if (venda && v != null && n > 0)
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (conta!.arrobas != null) Info('Arrobas', '${num1(conta.arrobas!)} @'),
                    Info('Valor bruto', moeda(conta.bruto)),
                    Info('Descontos', '− ${moeda(conta.descontos)}'),
                    Info('Valor líquido', moeda(conta.liquido)),
                    Info('Líquido por cabeça', moeda(v / n)),
                    if (p != null && p > 0) Info('Por kg vivo', moeda(v / p)),
                    if (p != null && p > 0) Info('Peso médio', kg(p / n)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: salvando ? null : salvar,
            icon: const Icon(Icons.save),
            label: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
