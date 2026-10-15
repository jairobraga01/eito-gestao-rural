import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../util/util.dart';
import 'base.dart';

const tiposEntrada = ['Compra', 'Transferência', 'Doação', 'Outro'];

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
              Info('Valor total', moeda(valor)),
              if (valor != null && qtd > 0) Info('Por cabeça', moeda(valor / qtd)),
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
  final origem = TextEditingController();
  final gta = TextEditingController();
  final obs = TextEditingController();
  bool salvando = false;

  @override
  void dispose() {
    for (final c in [brincos, raca, peso, valor, origem, gta, obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> salvar() async {
    final lista = separarBrincos(brincos.text);
    if (lista.isEmpty) {
      avisar(context, 'Digite os brincos dos animais que chegaram.');
      return;
    }
    if (!await confirmar(context, 'Confirmar ${tipo!.toLowerCase()}', '${lista.length} animal(is) entrarão no rebanho.')) {
      return;
    }
    setState(() => salvando = true);
    try {
      await Db.registrarEntrada({
        'tipo': tipo,
        'data': data,
        'peso_total': lerNumero(peso.text),
        'valor_total': tipo == 'Compra' ? lerNumero(valor.text) : null,
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
    } on RegistroDuplicado catch (e) {
      setState(() => salvando = false);
      if (mounted) avisar(context, e.mensagem);
      return;
    }
    if (!mounted) return;
    avisar(context, 'Entrada registrada.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final compra = tipo == 'Compra';
    final n = separarBrincos(brincos.text).length;
    final p = lerNumero(peso.text);
    final v = lerNumero(valor.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Nova entrada')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          escolha('Tipo', tipo, tiposEntrada, (x) => setState(() => tipo = x)),
          gap,
          DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (x) => setState(() => data = x!)),
          gap,
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
            }),
          ),
          gap,
          escolha('Categoria', categoria, sexo == 'F' ? categoriasF : categoriasM, (x) => setState(() => categoria = x)),
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
            TextField(
              controller: valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor total', prefixText: r'R$ '),
              onChanged: (_) => setState(() {}),
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
                    if (compra && v != null) Info('Por cabeça', moeda(v / n)),
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
