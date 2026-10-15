import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/manejo.dart';
import '../tema.dart';
import '../util/util.dart';
import 'calendario_sanitario.dart';
import 'modo_inseminacao.dart';
import 'manejo_em_serie.dart';
import 'mapa.dart' show RodizioPage;
import 'protocolos.dart';

const _titulos = {
  TipoFila.protocolo: ('Protocolos de IATF', Icons.event_note),
  TipoFila.sanidade: ('Vacinas e remédios', Icons.vaccines_outlined),
  TipoFila.diagnostico: ('Diagnóstico de gestação', Icons.search),
  TipoFila.parto: ('Partos', Icons.child_friendly_outlined),
  TipoFila.pasto: ('Rodízio de pastejo', Icons.autorenew),
};

/// Lista do que fazer hoje no curral, para ir riscando.
class FilaDoDiaPage extends StatelessWidget {
  const FilaDoDiaPage({super.key});

  void _abrir(BuildContext context, TipoFila t) {
    final tela = switch (t) {
      TipoFila.protocolo => const ProtocolosPage(),
      TipoFila.sanidade => const ManejoEmSerie(modo: ModoSerie.sanidade),
      TipoFila.diagnostico => const ModoInseminacao(etapa: EtapaIa.diagnostico),
      TipoFila.parto => null,
      TipoFila.pasto => const RodizioPage(),
    };
    if (tela != null) Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Fila do dia · ${br(hojeIso())}'), actions: [
        IconButton(
          tooltip: 'Calendário sanitário',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarioSanitarioPage())),
        ),
      ]),
      body: AoMudar<(List<ItemFila>, Set<String>)>(
        carregar: () async => (filaDoDia(hojeIso()), Db.filaFeitos()),
        builder: (context, d) {
          final (itens, feitos) = d;
          if (itens.isEmpty) {
            return const Vazio('Nada para hoje.\nVacinas vencendo, diagnósticos, partos e etapas de IATF aparecem aqui.',
                icone: Icons.task_alt);
          }
          final pendentes = itens.where((i) => !feitos.contains(i.chave)).length;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(pendentes == 0 ? 'Tudo feito hoje.' : '$pendentes de ${itens.length} para fazer',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            for (final t in TipoFila.values)
              if (itens.any((i) => i.tipo == t)) ...[
                Secao(_titulos[t]!.$1,
                    acao: t == TipoFila.parto
                        ? null
                        : TextButton(onPressed: () => _abrir(context, t), child: const Text('ABRIR'))),
                for (final i in itens.where((i) => i.tipo == t))
                  CheckboxListTile(
                    value: feitos.contains(i.chave),
                    onChanged: (v) => Db.marcarFila(i.chave, v ?? false),
                    secondary: Icon(_titulos[t]!.$2, color: i.atrasado ? Cores.alerta : Cores.oliva),
                    title: Text(i.titulo,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          decoration: feitos.contains(i.chave) ? TextDecoration.lineThrough : null,
                        )),
                    subtitle: Text(i.detalhe,
                        style: TextStyle(color: i.atrasado ? Cores.alerta : null, fontSize: 15)),
                  ),
              ],
          ]);
        },
      ),
    );
  }
}
