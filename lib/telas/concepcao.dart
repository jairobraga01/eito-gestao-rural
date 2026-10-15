import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/iatf.dart';
import '../tema.dart';
import '../util/util.dart';

/// Taxa de concepção (prenhes ÷ diagnosticadas) separada por um fator:
/// inseminador, touro, ECC, categoria, bezerro ao pé... Mostra onde está a falha.
class ConcepcaoPage extends StatefulWidget {
  const ConcepcaoPage({super.key, this.protocoloId});

  /// Só as vacas deste protocolo (null = todos os serviços da propriedade).
  final int? protocoloId;

  @override
  State<ConcepcaoPage> createState() => _ConcepcaoPageState();
}

class _ConcepcaoPageState extends State<ConcepcaoPage> {
  String fator = fatoresConcepcao.keys.first;
  int? ano;

  @override
  Widget build(BuildContext context) {
    final p = widget.protocoloId == null ? null : Db.registro('protocolos', widget.protocoloId);
    final anos = <int>{
      for (final r in Db.registros('reproducoes'))
        if (int.tryParse(txt(r['data']).split('-').first) case final a?) a,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: AppBar(title: Text(p == null ? 'Concepção por fator' : 'Concepção · ${p['nome']}')),
      body: AoMudar<List<LinhaConcepcao>>(
        carregar: () async => concepcaoPorFator(fator, protocoloId: widget.protocoloId, ano: ano),
        builder: (context, linhas) {
          final total = linhas.fold(0, (s, l) => s + l.total);
          final prenhes = linhas.fold(0, (s, l) => s + l.prenhes);
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Wrap(spacing: 8, children: [
                for (final f in fatoresConcepcao.keys)
                  ChoiceChip(label: Text(f), selected: fator == f, onSelected: (_) => setState(() => fator = f)),
              ]),
            ),
            if (p == null && anos.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(spacing: 8, children: [
                  ChoiceChip(label: const Text('Todos os anos'), selected: ano == null, onSelected: (_) => setState(() => ano = null)),
                  for (final a in anos)
                    ChoiceChip(label: Text('$a'), selected: ano == a, onSelected: (_) => setState(() => ano = a)),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                total == 0
                    ? 'Nenhuma inseminação com diagnóstico ainda.'
                    : 'Geral: $prenhes prenhes em $total diagnosticadas (${(prenhes * 100 / total).round()}%). '
                        'A perda embrionária conta como vazia.',
              ),
            ),
            for (final l in linhas)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(l.valor, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('${l.prenhes}/${l.total} · ${(l.taxa * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: l.taxa,
                      minHeight: 10,
                      color: total > 0 && l.taxa < prenhes / total - 0.1 ? Cores.alerta : Cores.oliva,
                      backgroundColor: Cores.oliva.withValues(alpha: 0.12),
                    ),
                  ),
                ]),
              ),
            if (linhas.length > 1)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Em vermelho: mais de 10 pontos abaixo da média. Grupos com poucas vacas variam muito.',
                    style: TextStyle(color: Colors.black54)),
              ),
          ]);
        },
      ),
    );
  }
}
