import 'package:flutter/material.dart';

import '../dados/gestao.dart';
import '../util/util.dart';
import 'animais.dart' show FichaAnimalPage;

/// Vacas ordenadas pela nota: prenhez, intervalo entre partos e peso das crias na desmama.
class RankingMatrizesPage extends StatelessWidget {
  const RankingMatrizesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ranking de matrizes')),
      body: AoMudar<List<NotaMatriz>>(
        carregar: () async => rankingMatrizes(),
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio('Nenhuma vaca com parto ou diagnóstico ainda.', icone: Icons.emoji_events_outlined);
          }
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nota de 0 a 100: taxa de prenhez (40), intervalo entre partos (30, melhor perto de 365 dias) '
                  'e peso das crias na desmama comparado à média do rebanho (30). Sem o dado, a vaca fica com a metade dos pontos.'),
            ),
            for (final (i, m) in lista.indexed)
              ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(rotulo(m.vaca), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  '${m.partos} ${m.partos == 1 ? 'parto' : 'partos'}',
                  if (m.taxaPrenhez != null) 'prenhez ${(m.taxaPrenhez! * 100).round()}%',
                  if (m.iep != null) 'intervalo ${m.iep!.round()} dias',
                  if (m.desmama != null) 'desmama ${kg(m.desmama)}',
                ].join(' · ')),
                trailing: Text(m.nota.round().toString(),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: m.nota >= 70 ? Colors.green.shade700 : (m.nota < 45 ? Colors.red : null))),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => FichaAnimalPage(m.vaca['id'] as int))),
              ),
          ]);
        },
      ),
    );
  }
}
