import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../util/util.dart';
import 'base.dart';

// ---------- Consultas compartilhadas com o Painel ----------

/// Fêmeas ativas prenhes com parto previsto até daqui a [dias] dias (inclui atrasados).
Future<List<Reg>> partosPrevistos(int dias) async {
  final limite = somaDias(hojeIso(), dias);
  return (await Db.reproducoes(filtro: 'Prenhe'))
      .where((r) =>
          r['femea_status'] == 'Ativo' &&
          r['parto_previsto'] != null &&
          txt(r['parto_previsto']).compareTo(limite) <= 0)
      .toList()
    ..sort((a, b) => txt(a['parto_previsto']).compareTo(txt(b['parto_previsto'])));
}

/// Serviços com mais de 30 dias ainda sem diagnóstico.
Future<List<Reg>> diagnosticosAtrasados() async {
  final limite = somaDias(hojeIso(), -30);
  return (await Db.reproducoes(filtro: 'Pendente'))
      .where((r) => r['femea_status'] == 'Ativo' && txt(r['data']).compareTo(limite) <= 0)
      .toList()
    ..sort((a, b) => txt(a['data']).compareTo(txt(b['data'])));
}

/// Manejos sanitários dos animais ativos desta propriedade.
List<(Reg, Reg)> _sanidadeAtivos() {
  final r = <(Reg, Reg)>[];
  for (final s in Db.registros('sanidade')) {
    final a = Db.registro('animais', s['animal_id']);
    if (a == null || a['status'] != 'Ativo' || a['propriedade_id'] != Db.pid) continue;
    r.add((s, a));
  }
  return r;
}

/// Próximas aplicações (inclui atrasadas) ainda não refeitas.
Future<List<Reg>> aplicacoesProximas(int dias) async {
  final limite = somaDias(hojeIso(), dias);
  final todos = _sanidadeAtivos();
  // Última data de cada produto em cada animal.
  final ultima = <String, String>{};
  for (final (s, _) in todos) {
    final k = '${s['animal_id']}|${txt(s['produto']).toLowerCase()}';
    final d = txt(s['data']);
    if ((ultima[k] ?? '').compareTo(d) < 0) ultima[k] = d;
  }
  final grupos = <String, Reg>{};
  for (final (s, _) in todos) {
    final prox = s['proxima'];
    if (prox == null || txt(prox).compareTo(limite) > 0) continue;
    final k = '${s['animal_id']}|${txt(s['produto']).toLowerCase()}';
    if (txt(s['data']).compareTo(ultima[k] ?? '') < 0) continue; // já refeita depois
    final g = '${s['produto']}|${s['tipo']}|$prox';
    final atual = grupos[g];
    grupos[g] = {
      'produto': s['produto'],
      'tipo': s['tipo'],
      'proxima': prox,
      'qtd': ((atual?['qtd'] as int?) ?? 0) + 1,
    };
  }
  return grupos.values.toList()..sort((a, b) => txt(a['proxima']).compareTo(txt(b['proxima'])));
}

/// Animais ainda dentro do período de carência.
Future<List<Reg>> animaisEmCarencia() async {
  final hoje = hojeIso();
  final r = <Reg>[];
  for (final (s, a) in _sanidadeAtivos()) {
    final dias = s['carencia'] is num ? (s['carencia'] as num).toInt() : 0;
    if (dias <= 0 || s['data'] == null) continue;
    final libera = somaDias(txt(s['data']), dias);
    if (libera.compareTo(hoje) < 0) continue;
    r.add({'id': a['id'], 'brinco': a['brinco'], 'nome': a['nome'], 'produto': s['produto'], 'libera': libera});
  }
  return r..sort((a, b) => txt(a['libera']).compareTo(txt(b['libera'])));
}

Map<String, int> _contagem(List<Reg> animais, String Function(Reg) chave) {
  final c = <String, int>{};
  for (final a in animais) {
    final k = chave(a);
    c[k] = (c[k] ?? 0) + 1;
  }
  final ordenado = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in ordenado) e.key: e.value};
}

// ---------- Relatório ----------

class _Rel {
  late int ativos;
  late Map<String, int> porCategoria, porLote, porSexo;
  int servicos = 0, prenhes = 0, vazias = 0, pendentes = 0, paridas = 0;
  late List<Reg> partos;
  late List<Reg> proximas;
  late List<Reg> carencia;
  final gmds = <(Reg, double, int)>[];
  late List<Reg> saidasAno;

  double? get taxaPrenhez {
    final diag = prenhes + vazias;
    return diag == 0 ? null : prenhes / diag;
  }

  double? get gmdMedio =>
      gmds.isEmpty ? null : gmds.map((g) => g.$2).reduce((a, b) => a + b) / gmds.length;
}

Future<_Rel> _carregar() async {
  final r = _Rel();
  final hoje = hojeIso();
  final ativos = await Db.animais(soAtivos: true);
  r.porCategoria = _contagem(ativos, (a) => txt(a['categoria']).trim().isEmpty ? 'Sem categoria' : txt(a['categoria']).trim());
  r.porLote = _contagem(ativos, (a) => txt(a['lote_nome']).isEmpty ? 'Sem lote' : txt(a['lote_nome']));
  r.porSexo = _contagem(ativos, (a) => a['sexo'] == 'F' ? 'Fêmeas' : 'Machos');
  r.ativos = ativos.length;

  // Reprodução: serviços dos últimos 12 meses.
  final desde = somaDias(hoje, -365);
  for (final x in await Db.reproducoes()) {
    if (txt(x['data']).compareTo(desde) < 0) continue;
    r.servicos++;
    if (x['parto_data'] != null) r.paridas++;
    switch (x['diagnostico']) {
      case 'Prenhe':
        r.prenhes++;
      case 'Vazia':
        r.vazias++;
      default:
        r.pendentes++;
    }
  }
  r.partos = await partosPrevistos(90);
  r.proximas = await aplicacoesProximas(30);
  r.carencia = await animaisEmCarencia();

  // GMD: da primeira à última pesagem de cada animal ativo.
  final idsAtivos = {for (final a in ativos) a['id']};
  final porAnimal = <Object?, List<Reg>>{};
  for (final p in await Db.pesagens()) {
    if (!idsAtivos.contains(p['animal_id'])) continue;
    porAnimal.putIfAbsent(p['animal_id'], () => []).add(p);
  }
  for (final l in porAnimal.values) {
    if (l.length < 2) continue;
    l.sort((a, b) {
      final c = txt(a['data']).compareTo(txt(b['data']));
      return c != 0 ? c : ((a['id'] as num?) ?? 0).compareTo((b['id'] as num?) ?? 0);
    });
    final dias = diasEntre(txt(l.first['data']), txt(l.last['data']));
    if (dias <= 0) continue;
    final ganho = (l.last['peso'] as num) - (l.first['peso'] as num);
    r.gmds.add((l.last, ganho / dias, dias));
  }
  r.gmds.sort((a, b) => b.$2.compareTo(a.$2));

  // Saídas do ano, por tipo.
  final inicioAno = '${DateTime.now().year}-01-01';
  final porTipo = <String, Reg>{};
  for (final s in await Db.saidas()) {
    if (txt(s['data']).compareTo(inicioAno) < 0) continue;
    final t = txt(s['tipo']);
    final a = porTipo[t] ?? {'tipo': t, 'qtd': 0, 'valor': null, 'peso': null};
    a['qtd'] = (a['qtd'] as int) + ((s['quantidade'] as num?)?.toInt() ?? 0);
    if (s['valor_total'] is num) a['valor'] = ((a['valor'] as num?) ?? 0) + (s['valor_total'] as num);
    if (s['peso_total'] is num) a['peso'] = ((a['peso'] as num?) ?? 0) + (s['peso_total'] as num);
    porTipo[t] = a;
  }
  r.saidasAno = porTipo.values.toList()..sort((a, b) => (b['qtd'] as int).compareTo(a['qtd'] as int));
  return r;
}

class RelatoriosPage extends StatelessWidget {
  const RelatoriosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Relatórios',
      corpo: AoMudar<_Rel>(
        carregar: _carregar,
        builder: (context, r) {
          final taxa = r.taxaPrenhez;
          final media = r.gmdMedio;
          final venda = r.saidasAno.where((s) => s['tipo'] == 'Venda').firstOrNull;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Secao('Rebanho ativo: ${r.ativos} cabeças'),
              Barras({for (final e in r.porSexo.entries) e.key: e.value}),
              const Secao('Por categoria'),
              Barras({for (final e in r.porCategoria.entries) e.key: e.value}),
              const Secao('Por lote / pasto'),
              Barras({for (final e in r.porLote.entries) e.key: e.value}),

              const Secao('Reprodução (últimos 12 meses)'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.6,
                  children: [
                    Kpi('Serviços', '${r.servicos}', icone: Icons.favorite_border),
                    Kpi('Taxa de prenhez', taxa == null ? '-' : '${(taxa * 100).toStringAsFixed(0)}%',
                        icone: Icons.percent, cor: Colors.green),
                    Kpi('Prenhes / vazias', '${r.prenhes} / ${r.vazias}', icone: Icons.favorite),
                    Kpi('Sem diagnóstico', '${r.pendentes}', icone: Icons.hourglass_empty, cor: Colors.orange),
                  ],
                ),
              ),
              Secao('Partos previstos (próximos 90 dias): ${r.partos.length}'),
              if (r.partos.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nenhum.')),
              for (final p in r.partos)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.event),
                  title: Text(rotulo(p)),
                  trailing: Text(br(p['parto_previsto'])),
                ),

              const Secao('Desenvolvimento (GMD)'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(media == null
                    ? 'São necessárias ao menos duas pesagens por animal.'
                    : 'GMD médio: ${gmd(media)} (${r.gmds.length} animais)'),
              ),
              for (final g in r.gmds.take(15))
                ListTile(
                  dense: true,
                  title: Text(rotulo(g.$1)),
                  subtitle: Text('Último peso ${kg(g.$1['peso'] as num)} · ${g.$3} dias'),
                  trailing: Text(gmd(g.$2)),
                ),

              Secao('Sanidade – próximos 30 dias: ${r.proximas.length}'),
              for (final s in r.proximas)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.vaccines_outlined),
                  title: Text('${s['produto']} (${s['qtd']} animais)'),
                  trailing: Text(br(s['proxima'])),
                ),
              Secao('Em carência: ${r.carencia.length}'),
              for (final c in r.carencia)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.block, color: Colors.red),
                  title: Text('${rotulo(c)} · ${c['produto']}'),
                  trailing: Text('libera ${br(c['libera'])}'),
                ),

              Secao('Saídas em ${DateTime.now().year}'),
              if (r.saidasAno.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nenhuma.')),
              for (final s in r.saidasAno)
                ListTile(
                  dense: true,
                  title: Text('${s['tipo']}: ${s['qtd'] ?? 0} cab.'),
                  trailing: s['valor'] == null ? null : Text(moeda(s['valor'] as num)),
                ),
              if (venda != null && venda['valor'] != null && (venda['qtd'] as int? ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                      'Média por cabeça vendida: ${moeda((venda['valor'] as num) / (venda['qtd'] as int))}'),
                ),
            ],
          );
        },
      ),
    );
  }
}
