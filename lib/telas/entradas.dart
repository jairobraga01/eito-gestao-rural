import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/negocio.dart';
import '../dados/numeracao.dart';
import '../util/util.dart';
import '../widgets/prazo.dart';
import 'base.dart';

const tiposEntrada = ['Compra', 'Rebanho existente', 'Transferência', 'Doação', 'Outro'];

/// Seta de entrada (verde, para baixo) e de saída (vermelha, para cima).
const iconeEntrada = Icons.arrow_circle_down_outlined;
const iconeSaida = Icons.arrow_circle_up_outlined;

class EntradasPage extends StatelessWidget {
  const EntradasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Compras e entradas',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Nova entrada'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EntradaFormPage())),
      ),
      corpo: AoMudar<List<Reg>>(
        carregar: Db.entradas,
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio('Nenhuma compra ou entrada registrada.', icone: iconeEntrada);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final e = lista[i];
              final compra = e['tipo'] == 'Compra';
              return ListTile(
                leading: const Icon(iconeEntrada, color: Colors.green, size: 30),
                title: Text('${e['tipo']} · ${e['quantidade'] ?? 0} cab.'
                    '${compra && e['valor_total'] != null ? ' · ${moeda(e['valor_total'] as num)}' : ''}'),
                subtitle: Text([
                  br(e['data']),
                  if (txt(e['origem']).isNotEmpty) txt(e['origem']),
                  if (txt(e['brincos']).isNotEmpty) 'Brincos: ${e['brincos']}',
                ].join(' · ')),
                onTap: () => _detalhe(context, e),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _detalhe(BuildContext context, Reg e) async {
    final qtd = (e['quantidade'] as int?) ?? 0;
    final peso = e['peso_total'] as num?;
    final valor = e['valor_total'] as num?;
    final excluir = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${e['tipo']} de ${br(e['data'])}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Info('Cabeças', '$qtd'),
              Info('Peso total', kg(peso)),
              if (peso != null && qtd > 0) Info('Peso médio', kg(peso / qtd)),
              if (e['subtotal'] is num) ...[
                Info('Subtotal', moeda(e['subtotal'] as num)),
                Info('Comissão (${num1(e['comissao_pct'] as num? ?? 0)}%)', moeda(e['comissao'] as num?)),
                if ((e['nota'] as num? ?? 0) > 0) Info('Nota', moeda(e['nota'] as num)),
                if ((e['frete'] as num? ?? 0) > 0) Info('Frete', moeda(e['frete'] as num)),
              ],
              Info(e['subtotal'] is num ? 'Total pago' : 'Valor total', moeda(valor)),
              if (valor != null && qtd > 0) Info('Média por cabeça', moeda(valor / qtd)),
              if (valor != null && peso != null && peso > 0) Info('Por kg vivo', moeda(valor / peso)),
              Info('Vendedor / origem', txt(e['origem'])),
              Info('GTA', txt(e['gta'])),
              Info('Brincos', txt(e['brincos'])),
              Info('Observações', txt(e['obs'])),
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
    final op = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir entrada?'),
        content: Text('E os $qtd animais que chegaram nela?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, 'manter'), child: const Text('Manter no rebanho')),
          FilledButton(onPressed: () => Navigator.pop(c, 'apagar'), child: const Text('Apagar os animais')),
        ],
      ),
    );
    if (op == null) return;
    await Db.excluirEntrada(e['id'] as int, apagarAnimais: op == 'apagar');
    await apagarParcelasAbertas('entrada:${e['id']}');
  }
}

/// Separa os brincos digitados (um por linha, ou por vírgula, ponto e vírgula ou espaço).
List<String> separarBrincos(String texto) =>
    texto.split(RegExp(r'[\s,;]+')).map((b) => b.trim()).where((b) => b.isNotEmpty).toList();

class EntradaFormPage extends StatefulWidget {
  const EntradaFormPage({super.key});

  @override
  State<EntradaFormPage> createState() => _EntradaFormPageState();
}

class _EntradaFormPageState extends State<EntradaFormPage> {
  String? tipo = 'Compra';
  String data = hojeIso();
  String sexo = 'M';
  String? categoria;
  int? loteId;
  String? nascimento;
  final brincos = TextEditingController();
  final raca = TextEditingController();
  final peso = TextEditingController();
  final valor = TextEditingController();
  bool porCabeca = true;
  late final comissao = TextEditingController(text: num1(comissaoPadrao()));
  final nota = TextEditingController();
  final frete = TextEditingController();
  bool aPrazo = false;
  final parcelas = TextEditingController(text: '1');
  late String primeiro = vencimentoSugerido(data);
  final origem = TextEditingController();
  final gta = TextEditingController();
  final obs = TextEditingController();
  bool salvando = false;

  // Gado sem brinco: o Eito gera a numeração (prefixo_001, prefixo_002...).
  bool gerar = false;
  final quantidade = TextEditingController();
  final prefixo = TextEditingController();
  final inicio = TextEditingController();
  bool prefixoEditado = false;

  @override
  void initState() {
    super.initState();
    _sugerir();
  }

  /// Atualiza o prefixo sugerido (enquanto a pessoa não o mudou) e o próximo número.
  void _sugerir() {
    if (!prefixoEditado) {
      prefixo.text = prefixoSugerido(categoria: categoria, sexo: sexo, tipo: tipo ?? '', data: data);
    }
    inicio.text = '${proximoNumero(prefixo.text)}';
  }

  List<String> _lista() {
    if (!gerar) return separarBrincos(brincos.text);
    final qtd = int.tryParse(quantidade.text.trim()) ?? 0;
    final ini = int.tryParse(inicio.text.trim()) ?? 1;
    if (qtd <= 0 || qtd > 5000 || prefixo.text.trim().isEmpty) return const [];
    return gerarBrincos(prefixo.text, ini < 1 ? 1 : ini, qtd);
  }

  @override
  void dispose() {
    for (final c in [brincos, raca, peso, valor, parcelas, comissao, nota, frete, origem, gta, obs, quantidade, prefixo, inicio]) {
      c.dispose();
    }
    super.dispose();
  }

  ContaCompra? _conta(int n) {
    final v = lerNumero(valor.text);
    if (tipo != 'Compra' || v == null) return null;
    return ContaCompra(
      cabecas: n,
      subtotal: (porCabeca ? v * n : v).toDouble(),
      comissaoPct: (lerNumero(comissao.text) ?? 0).toDouble(),
      nota: (lerNumero(nota.text) ?? 0).toDouble(),
      frete: (lerNumero(frete.text) ?? 0).toDouble(),
    );
  }

  Future<void> salvar() async {
    final lista = _lista();
    if (lista.isEmpty) {
      avisar(context,
          gerar ? 'Diga quantos animais (até 5.000 por vez) e o prefixo.' : 'Digite os brincos dos animais que chegaram.');
      return;
    }
    if (!await confirmar(
        context,
        'Confirmar ${tipo!.toLowerCase()}',
        '${lista.length} animal(is) entrarão no rebanho'
            '${gerar ? ', de ${lista.first} até ${lista.last}' : ''}.')) {
      return;
    }
    setState(() => salvando = true);
    final conta = _conta(lista.length);
    if (conta != null) await lembrarAjustesNegocio({'comissao_pct': conta.comissaoPct});
    try {
      final id = await Db.registrarEntrada({
        'tipo': tipo,
        'data': data,
        'peso_total': lerNumero(peso.text),
        'valor_total': conta?.total,
        if (conta != null) ...{
          'subtotal': conta.subtotal,
          'comissao_pct': conta.comissaoPct,
          'comissao': conta.comissao,
          'nota': conta.nota,
          'frete': conta.frete,
        },
        'origem': nulo(origem.text),
        'gta': nulo(gta.text),
        'obs': nulo(obs.text),
      }, lista, {
        'sexo': sexo,
        'categoria': categoria,
        'raca': nulo(raca.text),
        'lote_id': loteId,
        'nascimento': nascimento,
      });
      if (conta != null && aPrazo) {
        await lancarParcelas(
          receita: false,
          origem: 'entrada:$id',
          total: conta.total,
          parcelas: (int.tryParse(parcelas.text.trim()) ?? 1).clamp(1, 120),
          primeiro: primeiro,
          descricao: 'Compra de ${lista.length} cab.${origem.text.trim().isEmpty ? '' : ' de ${origem.text.trim()}'}',
          participante: nulo(origem.text),
        );
      }
    } on RegistroDuplicado catch (e) {
      setState(() => salvando = false);
      if (mounted) avisar(context, e.mensagem);
      return;
    }
    if (!mounted) return;
    avisar(context, 'Entrada registrada.');
    Navigator.pop(context, true);
  }

  Widget _numero(TextEditingController c, String label, {String? sufixo, String? prefixo}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: sufixo, prefixText: prefixo),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final compra = tipo == 'Compra';
    final gerados = _lista();
    final n = gerados.length;
    final p = lerNumero(peso.text);
    final conta = _conta(n);
    final v = conta?.total;
    return Scaffold(
      appBar: AppBar(title: const Text('Nova entrada')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          escolha('Tipo', tipo, tiposEntrada, (x) => setState(() {
                tipo = x;
                if (x == 'Rebanho existente') gerar = true;
                _sugerir();
              })),
          if (tipo == 'Rebanho existente')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Para cadastrar o gado que já está na fazenda, de uma vez.',
                  style: TextStyle(color: Colors.black54)),
            ),
          gap,
          DateField(
              label: 'Data',
              value: data,
              obrigatorio: true,
              onChanged: (x) => setState(() {
                    data = x!;
                    primeiro = vencimentoSugerido(data);
                    _sugerir();
                  })),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: gerar,
            title: const Text('Sem brinco: gerar a numeração'),
            subtitle: const Text('Ex.: vaca_fazenda_001, vaca_fazenda_002...'),
            onChanged: (v) => setState(() => gerar = v),
          ),
          if (gerar) ...[
            TextField(
              controller: quantidade,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Quantos animais *', suffixText: 'cab.'),
            ),
            gap,
            TextField(
              controller: prefixo,
              onChanged: (_) => setState(() {
                prefixoEditado = true;
                inicio.text = '${proximoNumero(prefixo.text)}';
              }),
              decoration: const InputDecoration(labelText: 'Prefixo', helperText: 'Muda sozinho com a categoria e a data.'),
            ),
            gap,
            TextField(
              controller: inicio,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Começar do número', helperText: 'Já vem o próximo livre, para continuar a contagem.'),
            ),
            if (n > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(n == 1 ? gerados.first : '${gerados.first} até ${gerados.last}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ] else
          TextField(
            controller: brincos,
            maxLines: 4,
            minLines: 2,
            keyboardType: TextInputType.multiline,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Brincos *',
              helperText: 'Um por linha, ou separados por vírgula. $n animal(is).',
            ),
          ),
          gap,
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'M', label: Text('Machos')),
              ButtonSegment(value: 'F', label: Text('Fêmeas')),
            ],
            selected: {sexo},
            onSelectionChanged: (s) => setState(() {
              sexo = s.first;
              categoria = null;
              _sugerir();
            }),
          ),
          gap,
          escolha('Categoria', categoria, sexo == 'F' ? categoriasF : categoriasM, (x) => setState(() {
                categoria = x;
                _sugerir();
              })),
          gap,
          campoTexto(raca, 'Raça'),
          gap,
          AoMudar<List<Reg>>(
            carregar: () => Db.lotes(soAtivos: true),
            builder: (context, lotes) =>
                escolhaId('Lote', loteId, lotes, (x) => setState(() => loteId = x), vazio: 'Sem lote'),
          ),
          gap,
          DateField(label: 'Nascimento (aproximado)', value: nascimento, onChanged: (x) => setState(() => nascimento = x)),
          gap,
          TextField(
            controller: peso,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Peso total vivo', suffixText: 'kg', helperText: 'Cada animal recebe o peso médio como pesagem de entrada.'),
          ),
          if (compra) ...[
            gap,
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Valor por cabeça')),
                ButtonSegment(value: false, label: Text('Valor do lote')),
              ],
              selected: {porCabeca},
              onSelectionChanged: (s) => setState(() => porCabeca = s.first),
            ),
            gap,
            TextField(
              controller: valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: porCabeca ? 'Valor por cabeça' : 'Valor do lote', prefixText: r'R$ '),
              onChanged: (_) => setState(() {}),
            ),
            gap,
            Row(children: [
              Expanded(child: _numero(comissao, 'Comissão do comprador', sufixo: '%')),
              const SizedBox(width: 8),
              Expanded(child: _numero(nota, 'Nota', prefixo: r'R$ ')),
              const SizedBox(width: 8),
              Expanded(child: _numero(frete, 'Frete', prefixo: r'R$ ')),
            ]),
            CamposPrazo(
              receita: false,
              aPrazo: aPrazo,
              parcelas: parcelas,
              primeiro: primeiro,
              onAPrazo: (x) => setState(() => aPrazo = x),
              onPrimeiro: (x) => setState(() => primeiro = x),
              onMudou: () => setState(() {}),
            ),
          ],
          gap,
          campoTexto(origem, compra ? 'Vendedor' : 'Origem'),
          gap,
          campoTexto(gta, 'Nº da GTA'),
          gap,
          campoTexto(obs, 'Observações', linhas: 3),
          if (n > 0 && ((compra && v != null) || (p != null && p > 0)))
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (conta != null) ...[
                      Info('Subtotal', moeda(conta.subtotal)),
                      Info('Comissão (${num1(conta.comissaoPct)}%)', moeda(conta.comissao)),
                      if (conta.nota > 0) Info('Nota', moeda(conta.nota)),
                      if (conta.frete > 0) Info('Frete', moeda(conta.frete)),
                      Info('Total pago', moeda(conta.total)),
                    ],
                    if (compra && v != null) Info('Média por cabeça', moeda(v / n)),
                    if (compra && v != null && p != null && p > 0) Info('Por kg vivo', moeda(v / p)),
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
