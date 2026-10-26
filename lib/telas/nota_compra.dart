// Lançar insumos e medicamentos lendo a nota de compra (XML, PDF ou foto).
import 'package:flutter/material.dart';

import '../dados/estoque.dart';
import '../dados/nota_compra.dart';
import '../dispositivos/arquivo_stub.dart' if (dart.library.js_interop) '../dispositivos/arquivo_web.dart';
import '../tema.dart';
import '../util/util.dart';

String _q(double v) => numeroBr(v, casas: v % 1 == 0 ? 0 : 2);

/// Conferência dos itens lidos: a pessoa corrige e confirma antes de entrar no estoque.
class NotaCompraPage extends StatefulWidget {
  const NotaCompraPage({super.key, this.categorias, this.inicial});

  /// Nota já lida em outra tela (Lançar por foto ou PDF).
  final NotaCompra? inicial;

  /// Categorias que a tela oferece (medicamentos ou insumos em geral); null = todas.
  final List<String>? categorias;

  @override
  State<NotaCompraPage> createState() => _NotaCompraPageState();
}

class _NotaCompraPageState extends State<NotaCompraPage> {
  late NotaCompra? nota = widget.inicial;
  late String data = widget.inicial?.data ?? hojeIso();
  String status = '';
  bool lendo = false;
  bool salvando = false;

  List<String> get categorias => widget.categorias ?? categoriasInsumo;

  Future<void> _ler() async {
    setState(() {
      lendo = true;
      status = 'Escolha o arquivo da nota…';
    });
    try {
      final texto = await lerNotaDeArquivo(aviso: (s) {
        if (mounted) setState(() => status = s);
      });
      if (texto == null || !mounted) return;
      final lida = lerNotaXml(texto) ?? lerNotaTexto(texto);
      for (final i in lida.itens) {
        if (!categorias.contains(i.categoria)) i.categoria = categorias.first;
      }
      setState(() {
        nota = lida;
        if (lida.data != null) data = lida.data!;
      });
      if (lida.itens.isEmpty && mounted) {
        avisar(context, 'Não achei itens nessa nota. Tente o XML, um PDF da nota ou uma foto mais nítida.');
      }
    } catch (e) {
      if (mounted) avisar(context, '$e');
    } finally {
      if (mounted) setState(() => lendo = false);
    }
  }

  Future<void> _editar(ItemNota i) async {
    final nome = TextEditingController(text: i.descricao);
    // Guarda o texto mostrado: só grava o número que a pessoa mudou (o mostrado é arredondado).
    final qtdTxt = _q(i.qtd), precoTxt = _q(i.valorUnit), embTxt = _q(i.embalagem);
    final qtd = TextEditingController(text: qtdTxt);
    final preco = TextEditingController(text: precoTxt);
    final emb = TextEditingController(text: embTxt);
    var categoria = i.categoria, unidade = i.unidade;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Corrigir item'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              campoTexto(nome, 'Produto'),
              gap,
              Row(children: [
                Expanded(child: campoTexto(qtd, 'Quantidade comprada', numero: true, sufixo: i.unidadeNota)),
                const SizedBox(width: 12),
                Expanded(child: campoTexto(preco, 'Preço de cada', numero: true)),
              ]),
              gap,
              escolha('Categoria', categoria, categorias, (v) => set(() => categoria = v ?? categoria)),
              gap,
              Row(children: [
                Expanded(child: escolha('Controle em', unidade, unidadesInsumo, (v) => set(() => unidade = v ?? unidade))),
                const SizedBox(width: 12),
                Expanded(child: campoTexto(emb, 'Cada um tem', numero: true, sufixo: unidade)),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final v = (
      nome.text.trim(),
      qtd.text == qtdTxt ? null : lerNumero(qtd.text),
      preco.text == precoTxt ? null : lerNumero(preco.text),
      emb.text == embTxt ? null : lerNumero(emb.text),
    );
    for (final c in [nome, qtd, preco, emb]) {
      c.dispose();
    }
    if (ok != true) return;
    setState(() {
      if (v.$1.isNotEmpty) i.descricao = v.$1;
      if (v.$2 != null && v.$2! > 0) i.qtd = v.$2!;
      if (v.$3 != null && v.$3! >= 0) i.valorUnit = v.$3!;
      if (v.$4 != null && v.$4! > 0) i.embalagem = v.$4!;
      i.categoria = categoria;
      i.unidade = unidade;
    });
  }

  Future<void> _lancar() async {
    final n = nota;
    if (n == null) return;
    setState(() => salvando = true);
    try {
      final qtd = await lancarNota(n, data: data);
      if (!mounted) return;
      avisar(context, qtd == 1 ? '1 item lançado no estoque.' : '$qtd itens lançados no estoque.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => salvando = false);
        avisar(context, 'Não foi possível lançar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = nota;
    final marcados = n?.itens.where((i) => i.usar).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Lançar pela nota de compra')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        const Text(
            'Escolha o XML da nota, o PDF (DANFE) ou uma foto da nota ou do recibo. O Eito lê os produtos e '
            'os preços no seu aparelho; você confere tudo antes de entrar no estoque.'),
        gap,
        FilledButton.icon(
          icon: const Icon(Icons.document_scanner_outlined),
          label: Text(n == null ? 'Escolher nota (XML, PDF ou foto)' : 'Ler outra nota'),
          onPressed: lendo || salvando ? null : _ler,
        ),
        if (lendo) ...[
          gap,
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(status, style: const TextStyle(color: Colors.black54)),
        ],
        if (n != null && n.itens.isNotEmpty) ...[
          gap,
          DateField(label: 'Data da compra', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v ?? data)),
          if (n.fornecedor.isNotEmpty)
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.storefront_outlined), title: Text(n.fornecedor)),
          Secao('Itens lidos (${n.itens.length})'),
          for (final i in n.itens)
            Card(
              child: CheckboxListTile(
                value: i.usar,
                onChanged: (v) => setState(() => i.usar = v ?? true),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(i.descricao),
                subtitle: Text([
                  '${_q(i.qtd)} ${i.unidadeNota} × ${moeda(i.valorUnit)} = ${moeda(i.total)}',
                  if (i.embalagem <= 0)
                    'Toque em Corrigir e informe quanto tem cada ${i.unidadeNota.isEmpty ? 'embalagem' : i.unidadeNota}'
                  else
                    '${i.categoria} · entra ${_q(i.qtdEstoque)} ${i.unidade}',
                  switch (insumoParecido(i.descricao, unidade: i.unidade)) {
                    null => 'Insumo novo, será cadastrado',
                    final x => 'Soma no insumo "${x['nome']}"',
                  },
                ].join('\n')),
                isThreeLine: true,
                secondary: IconButton(
                  tooltip: 'Corrigir',
                  icon: const Icon(Icons.edit_outlined, color: Cores.oliva),
                  onPressed: () => _editar(i),
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: salvando || marcados == 0 ? null : _lancar,
            child: salvando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                : Text('Lançar $marcados item(ns) no estoque'),
          ),
        ],
      ]),
    );
  }
}
