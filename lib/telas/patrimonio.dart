import 'package:flutter/material.dart';

import '../dados/patrimonio.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';

/// Patrimônio: rebanho, terra e bens, menos as dívidas em aberto.
class PatrimonioPage extends StatelessWidget {
  const PatrimonioPage({super.key});

  Future<double?> _pedirValor(BuildContext context, String titulo, double? atual, {String sufixo = ''}) async {
    final c = TextEditingController(text: atual == null ? '' : numeroBr(atual, casas: 2));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(prefixText: r'R$ ', suffixText: sufixo, helperText: 'Deixe vazio para tirar o valor'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salvar')),
        ],
      ),
    );
    c.dispose();
    if (r == null) return atual;
    if (r.trim().isEmpty) return -1; // marcador: apagar
    return lerNumero(r) ?? atual;
  }

  Future<void> _precoCategoria(BuildContext context, LinhaRebanho l) async {
    final v = await _pedirValor(context, 'Valor de uma cabeça · ${l.categoria}', l.preco, sufixo: '/cab.');
    if (v == l.preco) return;
    final p = precosCategoria();
    if (v == null || v < 0) {
      p.remove(l.categoria);
    } else {
      p[l.categoria] = v;
    }
    await salvarPatrimonio(precos: p);
  }

  Future<void> _precoTerra(BuildContext context, LinhaTerra t) async {
    final v = await _pedirValor(context, 'Valor do hectare · ${txt(t.propriedade['nome'])}', t.precoHa, sufixo: '/ha');
    if (v == t.precoHa) return;
    final h = valorHectare();
    final k = '${t.propriedade['id']}';
    if (v == null || v < 0) {
      h.remove(k);
    } else {
      h[k] = v;
    }
    await salvarPatrimonio(terra: h);
  }

  Future<void> _bem(BuildContext context, [int? indice]) async {
    final lista = bens();
    final b = indice == null ? null : lista[indice];
    final nome = TextEditingController(text: txt(b?['nome']));
    final valor = TextEditingController(text: b?['valor'] is num ? numeroBr((b!['valor'] as num).toDouble(), casas: 2) : '');
    var tipo = txt(b?['tipo']).isEmpty ? tiposBem.first : txt(b?['tipo']);
    final op = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(b == null ? 'Novo bem' : 'Editar bem'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            campoTexto(nome, 'Descrição (ex.: Trator MF 275)', foco: true),
            gap,
            escolha('Tipo', tipo, tiposBem, (v) => set(() => tipo = v ?? tipo)),
            gap,
            TextField(
              controller: valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor atual', prefixText: r'R$ '),
            ),
          ]),
          actions: [
            if (b != null) TextButton(onPressed: () => Navigator.pop(ctx, 'excluir'), child: const Text('Excluir')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'salvar'), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final n = nome.text.trim(), v = lerNumero(valor.text);
    nome.dispose();
    valor.dispose();
    if (op == 'excluir' && indice != null) {
      lista.removeAt(indice);
    } else if (op == 'salvar' && n.isNotEmpty && v != null && v >= 0) {
      final novo = {'nome': n, 'tipo': tipo, 'valor': v};
      if (indice == null) {
        lista.add(novo);
      } else {
        lista[indice] = novo;
      }
    } else {
      if (op == 'salvar' && context.mounted) avisar(context, 'Preencha a descrição e o valor.');
      return;
    }
    await salvarPatrimonio(listaBens: lista);
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Patrimônio',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Bem'),
        onPressed: () => _bem(context),
      ),
      corpo: AoMudar<Patrimonio>(
        carregar: () async => calcularPatrimonio(),
        builder: (context, p) {
          final cs = Theme.of(context).colorScheme;
          Widget total(String t, double v, {Color? cor, bool grande = false}) => ListTile(
                dense: !grande,
                title: Text(t, style: TextStyle(fontWeight: grande ? FontWeight.w800 : FontWeight.w500)),
                trailing: Text(moeda(v),
                    style: TextStyle(
                        fontSize: grande ? 20 : 15, fontWeight: grande ? FontWeight.w800 : FontWeight.w600, color: cor)),
              );
          final bensLista = p.bens;
          return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: Column(children: [
                total('Rebanho (${p.cabecas} cab.)', p.totalRebanho),
                total('Terra', p.totalTerra),
                total('Bens', p.totalBens),
                const Divider(height: 1),
                total('Patrimônio bruto', p.bruto),
                total('Dívidas em aberto', -p.dividas, cor: p.dividas > 0 ? Cores.alerta : null),
                const Divider(height: 1),
                total('Patrimônio líquido', p.liquido, grande: true, cor: p.liquido < 0 ? Cores.alerta : Cores.sucesso),
              ]),
            ),
            if (p.semPreco.isNotEmpty || p.semValorTerra.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Faltam valores: ${[
                    if (p.semPreco.isNotEmpty) p.semPreco.join(', '),
                    if (p.semValorTerra.isNotEmpty) 'terra de ${p.semValorTerra.join(', ')}',
                  ].join('; ')}. Toque nas linhas abaixo para informar.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            const Secao('Rebanho por categoria'),
            if (p.rebanho.isEmpty) const ListTile(title: Text('Nenhum animal ativo.')),
            for (final l in p.rebanho)
              ListTile(
                leading: const Icon(Icons.pets_outlined, color: Cores.oliva),
                title: Text('${l.categoria} · ${l.cabecas} cab.'),
                subtitle: Text(l.preco == null ? 'Toque para informar o valor por cabeça' : '${moeda(l.preco)} por cabeça'),
                trailing: Text(l.preco == null ? '—' : moeda(l.valor)),
                onTap: () => _precoCategoria(context, l),
              ),
            const Secao('Terra'),
            for (final t in p.terra)
              ListTile(
                leading: const Icon(Icons.landscape_outlined, color: Cores.oliva),
                title: Text(txt(t.propriedade['nome'])),
                subtitle: Text(t.area <= 0
                    ? 'Sem área cadastrada (preencha em Propriedades)'
                    : '${num1(t.area)} ha${t.precoHa == null ? ' · toque para informar o valor do hectare' : ' × ${moeda(t.precoHa)}/ha'}'),
                trailing: Text(t.precoHa == null ? '—' : moeda(t.valor)),
                onTap: () => _precoTerra(context, t),
              ),
            Secao('Bens (${bensLista.length})'),
            if (bensLista.isEmpty)
              const ListTile(title: Text('Máquinas, veículos, benfeitorias… Toque em + Bem para cadastrar.')),
            for (final (i, b) in bensLista.indexed)
              ListTile(
                leading: const Icon(Icons.agriculture_outlined, color: Cores.oliva),
                title: Text(txt(b['nome'])),
                subtitle: Text(txt(b['tipo'])),
                trailing: Text(moeda(b['valor'] as num?)),
                onTap: () => _bem(context, i),
              ),
          ]);
        },
      ),
    );
  }
}
