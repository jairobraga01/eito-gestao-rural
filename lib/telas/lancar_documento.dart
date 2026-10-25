import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/gestao.dart' show categoriasCusto;
import '../dados/nota_compra.dart';
import '../dados/voz.dart';
import '../dispositivos/arquivo_stub.dart' if (dart.library.js_interop) '../dispositivos/arquivo_web.dart';
import '../tema.dart';
import '../util/util.dart';
import 'nota_compra.dart';

/// Lê uma foto ou PDF (nota de compra, recibo, anotação do caderno) e oferece
/// o lançamento que cabe: produtos no estoque, despesa no financeiro ou as
/// linhas que o app entende ("brinco 45 peso 450").
class LancarDocumentoPage extends StatefulWidget {
  const LancarDocumentoPage({super.key});

  @override
  State<LancarDocumentoPage> createState() => _LancarDocumentoPageState();
}

class _LancarDocumentoPageState extends State<LancarDocumentoPage> {
  String? texto;
  NotaCompra? nota;
  String data = hojeIso();
  String status = '';
  bool lendo = false;
  bool lancando = false;

  final descricao = TextEditingController();
  final valor = TextEditingController();
  String categoria = 'Outros';
  bool despesaLancada = false;

  List<MensagemWhatsApp> linhas = [];
  final marcadas = <int>{};
  final resultado = <int, String>{};

  @override
  void dispose() {
    descricao.dispose();
    valor.dispose();
    super.dispose();
  }

  Future<void> _ler() async {
    setState(() {
      lendo = true;
      status = 'Escolha a foto ou o PDF…';
    });
    try {
      final t = await lerNotaDeArquivo(aviso: (s) {
        if (mounted) setState(() => status = s);
      });
      if (t == null || !mounted) return;
      final n = lerNotaXml(t) ?? lerNotaTexto(t);
      final nomes = [for (final i in Db.registros('insumos')) if (i['propriedade_id'] == Db.pid) '${i['nome'] ?? ''}'];
      final ls = lerConversaWhatsApp(t, insumos: nomes).where((m) => m.comando != null).toList();
      final total = totalDoDocumento(t, nota: n);
      final itens = n.itens.map((i) => i.descricao).join(' ');
      setState(() {
        texto = t;
        nota = n;
        if (n.data != null) data = n.data!;
        descricao.text = n.fornecedor.isNotEmpty ? n.fornecedor : (n.itens.firstOrNull?.descricao ?? '');
        valor.text = total == null ? '' : numeroBr(total, casas: 2);
        categoria = categoriaDespesa('${n.fornecedor} $itens ${itens.isEmpty ? t : ''}');
        despesaLancada = false;
        linhas = ls;
        resultado.clear();
        marcadas
          ..clear()
          // Numa nota fiscal, linha "entendida" pode ser engano: a pessoa marca.
          ..addAll(n.itens.isEmpty ? List.generate(ls.length, (i) => i) : const <int>[]);
      });
      if (n.itens.isEmpty && total == null && ls.isEmpty && mounted) {
        avisar(context, 'Não entendi este arquivo. Tente uma foto mais nítida, de frente e com boa luz.');
      }
    } catch (e) {
      if (mounted) avisar(context, '$e');
    } finally {
      if (mounted) setState(() => lendo = false);
    }
  }

  Future<void> _lancarDespesa() async {
    final v = lerNumero(valor.text);
    if (v == null || v <= 0) return avisar(context, 'Informe o valor.');
    final d = nulo(descricao.text) ?? 'Nota de compra';
    setState(() => lancando = true);
    try {
      await executarVoz(ComandoVoz(TipoVoz.despesa, valor: v, produto: d, categoria: categoria), data: data);
      if (!mounted) return;
      setState(() => despesaLancada = true);
      avisar(context, 'Despesa de ${moeda(v)} lançada em $categoria.');
    } on StateError catch (e) {
      if (mounted) avisar(context, e.message);
    } finally {
      if (mounted) setState(() => lancando = false);
    }
  }

  Future<void> _lancarLinhas() async {
    setState(() => lancando = true);
    var ok = 0;
    for (final i in marcadas.toList()..sort()) {
      try {
        resultado[i] = 'ok: ${await executarVoz(linhas[i].comando!, data: linhas[i].data ?? data)}';
        ok++;
      } on StateError catch (e) {
        resultado[i] = e.message;
      } catch (e) {
        resultado[i] = 'Não deu para lançar: $e';
      }
    }
    if (!mounted) return;
    setState(() {
      lancando = false;
      marcadas.removeWhere((i) => resultado[i]?.startsWith('ok') ?? false);
    });
    avisar(context, '$ok lançamento(s) feito(s).');
  }

  @override
  Widget build(BuildContext context) {
    final n = nota;
    final tema = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Lançar por foto ou PDF')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        const Text('Tire uma foto ou escolha o PDF da nota de compra, do recibo ou da anotação do caderno. '
            'O Eito lê no seu aparelho e mostra o que dá para lançar. Você confere antes.'),
        gap,
        FilledButton.icon(
          icon: const Icon(Icons.document_scanner_outlined),
          label: Text(texto == null ? 'Escolher foto ou PDF' : 'Ler outro arquivo'),
          onPressed: lendo || lancando ? null : _ler,
        ),
        if (lendo) ...[
          gap,
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(status, style: const TextStyle(color: Colors.black54)),
        ],
        if (texto != null) ...[
          gap,
          DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v ?? data)),
        ],
        if (n != null && n.itens.isNotEmpty) ...[
          Secao('Produtos para o estoque (${n.itens.length})'),
          Text(n.itens.take(4).map((i) => '• ${i.descricao}').join('\n') + (n.itens.length > 4 ? '\n…' : '')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Conferir e lançar no estoque'),
            onPressed: lancando
                ? null
                : () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => NotaCompraPage(inicial: NotaCompra(itens: n.itens, fornecedor: n.fornecedor, data: data)))),
          ),
        ],
        if (texto != null && !Db.ehCampo) ...[
          Secao('Despesa no financeiro'),
          if (n != null && n.itens.isNotEmpty)
            const Text('Ração, sal e remédios que entram no estoque já viram custo quando forem usados. '
                'Lance como despesa só o que não vai para o estoque (diesel, peças, serviços).',
                style: TextStyle(color: Colors.black54)),
          gap,
          campoTexto(descricao, 'Descrição'),
          gap,
          Row(children: [
            Expanded(child: campoTexto(valor, 'Valor (R\$)', numero: true)),
            const SizedBox(width: 12),
            Expanded(child: escolha('Categoria', categoria, categoriasCusto, (v) => setState(() => categoria = v ?? categoria))),
          ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: Icon(despesaLancada ? Icons.check : Icons.payments_outlined),
            label: Text(despesaLancada ? 'Despesa lançada' : 'Lançar como despesa'),
            onPressed: lancando || despesaLancada ? null : _lancarDespesa,
          ),
        ],
        if (linhas.isNotEmpty) ...[
          Secao('Anotações entendidas (${linhas.length})'),
          for (final (i, m) in linhas.indexed) _linha(i, m),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: lancando || marcadas.isEmpty ? null : _lancarLinhas,
            child: Text('Lançar ${marcadas.length} anotação(ões)'),
          ),
        ],
        if (texto != null) ...[
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Texto lido', style: tema.titleSmall),
            children: [SelectableText(texto!, style: const TextStyle(fontSize: 12))],
          ),
        ],
      ]),
    );
  }

  Widget _linha(int i, MensagemWhatsApp m) {
    final r = resultado[i];
    final feito = r != null && r.startsWith('ok');
    return CheckboxListTile(
      value: feito || marcadas.contains(i),
      onChanged: feito || lancando ? null : (v) => setState(() => v! ? marcadas.add(i) : marcadas.remove(i)),
      title: Text(m.comando!.descricao),
      subtitle: Text(r == null ? m.texto : (feito ? 'Lançado' : r),
          style: TextStyle(color: r == null ? null : (feito ? Cores.sucesso : Cores.alerta))),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
