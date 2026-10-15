import 'package:flutter/material.dart';

import '../dados/gestao.dart';
import '../util/util.dart';

/// Calendário sanitário pronto: o que ficar ligado entra sozinho na fila do dia.
class CalendarioSanitarioPage extends StatelessWidget {
  const CalendarioSanitarioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendário sanitário')),
      body: AoMudar<(Set<String>, Map<String, int>)>(
        carregar: () async => (
          calendarioLigado(),
          {for (final (i, b) in pendenciasCalendario(hojeIso())) i.id: b.length},
        ),
        builder: (context, d) {
          final (ligados, pendentes) = d;
          return ListView(children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Os itens ligados aparecem na Fila do dia quando houver animal na idade ou no mês certo. '
                  'Confira com o seu veterinário e a agência de defesa do seu estado.'),
            ),
            for (final i in calendarioSanitario)
              SwitchListTile(
                value: ligados.contains(i.id),
                onChanged: (v) => ligarCalendario(i.id, v),
                title: Text(i.nome, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  '${i.tipo} · ${i.descricao}',
                  if (ligados.contains(i.id) && (pendentes[i.id] ?? 0) > 0) 'Hoje: ${pendentes[i.id]} animal(is) na fila',
                ].join('\n')),
                isThreeLine: ligados.contains(i.id) && (pendentes[i.id] ?? 0) > 0,
              ),
          ]);
        },
      ),
    );
  }
}
