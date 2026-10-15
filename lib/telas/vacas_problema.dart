import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/estacao.dart';
import '../tema.dart';
import '../util/util.dart';
import 'animais.dart' show FichaAnimalPage;

/// Vacas que pedem atenção ou descarte, com o motivo de cada uma.
class VacasProblemaPage extends StatelessWidget {
  const VacasProblemaPage({super.key});

  Future<void> _marcar(BuildContext context, Reg a) async {
    final marcada = a['descarte'] == true;
    if (await confirmar(context, marcada ? 'Tirar a marca de descarte?' : 'Marcar para descarte?',
        'Brinco ${a['brinco']}.', ok: marcada ? 'Tirar' : 'Marcar')) {
      await Db.atualizar('animais', a['id'] as int, {'descarte': !marcada});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vacas problema')),
      body: AoMudar<List<VacaProblema>>(
        carregar: () async => vacasProblema(hojeIso()),
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio('Nenhuma vaca com problema reprodutivo.', icone: Icons.check_circle_outline);
          }
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Dois ou mais serviços vazios, mais de um ano sem parir, novilha com 30 meses sem emprenhar, '
                  'ECC 2 ou menos e perda embrionária. Sugestão de descarte, não decisão.'),
            ),
            for (final v in lista)
              ListTile(
                leading: Icon(v.vaca['descarte'] == true ? Icons.block : Icons.warning_amber,
                    color: v.vaca['descarte'] == true ? Cores.alerta : Colors.orange),
                title: Text('Brinco ${v.vaca['brinco']}${txt(v.vaca['nome']).isEmpty ? '' : ' – ${v.vaca['nome']}'}'),
                subtitle: Text(v.motivos.join('\n')),
                isThreeLine: v.motivos.length > 1,
                trailing: IconButton(
                  tooltip: v.vaca['descarte'] == true ? 'Tirar marca de descarte' : 'Marcar para descarte',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _marcar(context, v.vaca),
                ),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => FichaAnimalPage(v.vaca['id'] as int))),
              ),
          ]);
        },
      ),
    );
  }
}
