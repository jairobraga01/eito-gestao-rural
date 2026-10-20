import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/db.dart';
import '../dados/mercado.dart' show siteScotBoi;
import '../dados/proteinado.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';

/// Cotação do boi gordo: abre o Notícias Agrícolas e guarda a arroba do dia.
/// A última lançada vale na Projeção de abate e em Custos e margem.
class CotacaoArrobaPage extends StatelessWidget {
  const CotacaoArrobaPage({super.key});

  Future<void> _lancar(BuildContext context, [Reg? c]) async {
    var data = txt(c?['data']).isEmpty ? hojeIso() : txt(c!['data']);
    final valor = TextEditingController(text: c?['valor'] is num ? numeroBr((c!['valor'] as num).toDouble(), casas: 2) : '');
    final praca = TextEditingController(text: txt(c?['praca']));
    final op = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c == null ? 'Arroba do dia' : 'Editar cotação'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => set(() => data = v!)),
            gap,
            TextField(
              controller: valor,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Arroba do boi gordo', prefixText: r'R$ ', suffixText: '/@'),
            ),
            gap,
            campoTexto(praca, 'Praça (ex.: MS Campo Grande)'),
          ]),
          actions: [
            if (c != null) TextButton(onPressed: () => Navigator.pop(ctx, 'excluir'), child: const Text('Excluir')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'salvar'), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final v = lerNumero(valor.text);
    final p = nulo(praca.text);
    valor.dispose();
    praca.dispose();
    if (op == 'excluir') {
      await excluirCotacao(c!['id'] as int);
    } else if (op == 'salvar' && v != null && v > 0) {
      if (c != null) await excluirCotacao(c['id'] as int);
      await registrarCotacao(data: data, valor: v, praca: p);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Cotação da arroba',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Lançar arroba'),
        onPressed: () => _lancar(context),
      ),
      corpo: AoMudar<List<Reg>>(
        carregar: () async => cotacoes(),
        builder: (context, cs) {
          final ultima = cs.firstOrNull;
          final anterior = cs.length > 1 ? cs[1] : null;
          final variacao = ultima != null && anterior != null
              ? (ultima['valor'] as num) / (anterior['valor'] as num) - 1
              : null;
          final ano = [for (final c in cs) if (txt(c['data']).compareTo(somaDias(hojeIso(), -365)) >= 0) c].reversed.toList();
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Boi gordo', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(ultima == null ? 'Nenhuma cotação lançada' : '${moeda(ultima['valor'] as num)}/@',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  if (ultima != null)
                    Text('${br(ultima['data'])}${txt(ultima['praca']).isEmpty ? '' : ' · ${ultima['praca']}'}'
                        '${variacao == null ? '' : ' · ${variacao >= 0 ? '▲' : '▼'} ${numeroBr(variacao.abs() * 100)}%'}',
                        style: TextStyle(
                            color: variacao == null ? null : (variacao >= 0 ? Cores.sucesso : Cores.alerta))),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Ver cotação no Notícias Agrícolas'),
                    onPressed: () => launchUrl(Uri.parse(siteCotacaoBoi), mode: LaunchMode.externalApplication),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Ver cotação na Scot Consultoria'),
                    onPressed: () => launchUrl(Uri.parse(siteScotBoi), mode: LaunchMode.externalApplication),
                  ),
                  const SizedBox(height: 8),
                  const Text('Confira o preço da sua praça no site e lance aqui. A última arroba lançada passa a valer '
                      'na Projeção de abate e em Custos e margem.'),
                ]),
              ),
            ),
            if (ano.length >= 2)
              Barras({for (final c in ano.length > 12 ? ano.sublist(ano.length - 12) : ano) br(c['data']): (c['valor'] as num).toDouble()},
                  sufixo: ''),
            Secao('Histórico (${cs.length})'),
            for (final c in cs)
              ListTile(
                dense: true,
                leading: const Icon(Icons.trending_up),
                title: Text('${moeda(c['valor'] as num)}/@'),
                subtitle: Text('${br(c['data'])}${txt(c['praca']).isEmpty ? '' : ' · ${c['praca']}'}'),
                onTap: () => _lancar(context, c),
              ),
          ]);
        },
      ),
    );
  }
}
