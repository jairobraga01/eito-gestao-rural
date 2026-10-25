// Importa o backup (.json) do app Gado Guaraí para a propriedade aberta:
// compras viram entradas com os animais numerados, vendas e saídas baixam
// esses animais, despesas viram custos e pesagens viram pesagens.
// Cada registro guarda o "guarai_id" para não importar duas vezes.
import 'dart:convert';

import 'db.dart';
import 'negocio.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String _t(Object? v) => v == null ? '' : '$v';

class ResultadoGuarai {
  int compras = 0, animais = 0, vendas = 0, saidas = 0, despesas = 0, pesagens = 0, jaExistiam = 0;
  final avisos = <String>[];

  String get resumo => [
        '$compras compra(s) com $animais animal(is)',
        '$vendas venda(s)',
        if (saidas > 0) '$saidas saída(s)',
        '$despesas despesa(s)',
        if (pesagens > 0) '$pesagens pesagem(ns)',
        if (jaExistiam > 0) '$jaExistiam já estavam no Eito',
      ].join(', ');
}

/// Lê o texto do backup e confere se é do Gado Guaraí.
Map<String, Object?> lerBackupGuarai(String texto) {
  final d = jsonDecode(texto);
  if (d is! Map || d['app'] != 'gado-guarai') {
    throw const FormatException('Este arquivo não é um backup do Gado Guaraí.');
  }
  return Map<String, Object?>.from(d);
}

List<Map<String, Object?>> _lista(Object? v) => [
      for (final x in (v as List?) ?? const [])
        if (x is Map) Map<String, Object?>.from(x),
    ];

String _tipoSaida(String motivo) {
  final m = motivo.toLowerCase();
  if (m.contains('mort')) return 'Morte';
  if (m.contains('consum')) return 'Consumo';
  if (m.contains('doa')) return 'Doação';
  return 'Transferência';
}

String _categoriaCusto(String tipo) {
  final t = tipo.toLowerCase();
  if (t.contains('aluguel') || t.contains('pasto') || t.contains('arrend')) return 'Pastagem e arrendamento';
  if (t.contains('protein') || t.contains('sal') || t.contains('raç') || t.contains('rac')) return 'Ração e sal';
  if (t.contains('vacin') || t.contains('remé') || t.contains('reme') || t.contains('verm') || t.contains('medic')) {
    return 'Sanidade';
  }
  if (t.contains('mão') || t.contains('mao') || t.contains('salár') || t.contains('diar')) return 'Mão de obra';
  if (t.contains('combust') || t.contains('diesel') || t.contains('máquin')) return 'Combustível e máquinas';
  return 'Outros';
}

Future<ResultadoGuarai> importarGuarai(Map<String, Object?> b) async {
  final r = ResultadoGuarai();
  final pid = Db.pid;
  Set<String> ja(String tabela) => {
        for (final x in Db.registros(tabela))
          if (_int(x['propriedade_id']) == pid && x['guarai_id'] != null) _t(x['guarai_id']),
      };
  final cfg = Map<String, Object?>.from((b['config'] as Map?) ?? const {});
  final exercicio = _t(cfg['exercicio']);
  await lembrarAjustesNegocio({
    if (cfg['comComp'] is num) 'comissao_pct': _n(cfg['comComp']),
    if (exercicio.length == 7) 'exercicio_mes': int.tryParse(exercicio.substring(5)) ?? 1,
  });

  // Compras: uma entrada por compra, com os animais numerados gg_c01_001...
  final compras = _lista(b['compras'])..sort((x, y) => _t(x['data']).compareTo(_t(y['data'])));
  final entradaDe = <String, int>{};
  final jaEntradas = ja('entradas');
  for (final e in Db.registros('entradas')) {
    if (_int(e['propriedade_id']) == pid && e['guarai_id'] != null) entradaDe[_t(e['guarai_id'])] = _int(e['id'])!;
  }
  // Números de compra já usados nesta propriedade: uma compra nova com data
  // antiga não pode repetir a numeração dos animais de outra.
  final numerosUsados = <int>{
    for (final a in Db.registros('animais'))
      if (_int(a['propriedade_id']) == pid)
        if (RegExp(r'^gg_c(\d+)_').firstMatch(_t(a['brinco'])) case final m?) int.parse(m[1]!),
  };
  for (final (i, c) in compras.indexed) {
    final gid = 'compra:${c['id']}';
    if (jaEntradas.contains(gid)) {
      r.jaExistiam++;
      continue;
    }
    final lotes = _lista(c['lotes']);
    final qtd = lotes.fold<int>(0, (s, l) => s + (_int(l['qtd']) ?? 0));
    if (qtd <= 0) continue;
    final conta = ContaCompra(
      cabecas: qtd,
      subtotal: lotes.fold(0.0, (s, l) => s + _n(l['qtd']) * _n(l['valor'])),
      comissaoPct: c['comComp'] is num ? _n(c['comComp']) : _n(cfg['comComp']),
      nota: _n(c['nota']),
      frete: _n(c['frete']),
    );
    var numero = i + 1;
    if (numerosUsados.contains(numero)) numero = numerosUsados.reduce((a, b) => a > b ? a : b) + 1;
    numerosUsados.add(numero);
    final n = '$numero'.padLeft(2, '0');
    final id = await Db.registrarEntrada({
      'tipo': 'Compra',
      'data': _t(c['data']),
      'peso_total': _n(c['pesoTotal']) > 0 ? _n(c['pesoTotal']) : null,
      'valor_total': conta.total,
      'subtotal': conta.subtotal,
      'comissao_pct': conta.comissaoPct,
      'comissao': conta.comissao,
      'comissao_vend_pct': c['comVend'] is num ? _n(c['comVend']) : _n(cfg['comVend']),
      'nota': conta.nota,
      'frete': conta.frete,
      'lotes': [
        for (final l in lotes) {'qtd': _int(l['qtd']) ?? 0, 'valor': _n(l['valor']), 'data': _t(l['data'])},
      ],
      'origem': _t(c['local']).isEmpty ? null : _t(c['local']),
      'obs': _t(c['obs']).isEmpty ? 'Importado do Gado Guaraí' : '${c['obs']} (Gado Guaraí)',
      'guarai_id': gid,
    }, [for (var k = 1; k <= qtd; k++) 'gg_c${n}_${'$k'.padLeft(3, '0')}'], {'sexo': 'M'});
    entradaDe[gid] = id;
    r.compras++;
    r.animais += qtd;
  }

  // Saldo anterior: o gado que já estava antes da 1ª compra.
  final saldo = _int(cfg['saldoAnterior']) ?? 0;
  if (saldo > 0) {
    if (jaEntradas.contains('saldo')) {
      r.jaExistiam++;
    } else {
      final primeira = compras.isEmpty ? '' : _t(compras.first['data']);
      final dia = DateTime.tryParse(primeira)?.subtract(const Duration(days: 1));
      entradaDe['saldo'] = await Db.registrarEntrada({
        'tipo': 'Rebanho existente',
        'data': dia?.toIso8601String().substring(0, 10),
        'obs': 'Saldo anterior do Gado Guaraí',
        'guarai_id': 'saldo',
      }, [for (var k = 1; k <= saldo; k++) 'gg_existente_${'$k'.padLeft(3, '0')}'], {'sexo': 'M'});
      r.animais += saldo;
    }
  }

  // Animais ainda ativos de uma compra (ou de todas, os mais antigos primeiro).
  // [usados] guarda os já baixados aqui, sem esperar o status gravar.
  final usados = <int>{};
  List<int> ativos(String? compraId, int qtd, {bool baixar = true}) {
    final ent = compraId == null ? null : entradaDe['compra:$compraId'];
    final ordem = {for (final (i, e) in entradaDe.values.indexed) e: i};
    final l = [
      for (final a in Db.registros('animais'))
        if (_int(a['propriedade_id']) == pid &&
            a['status'] == 'Ativo' &&
            !usados.contains(_int(a['id'])) &&
            (ent == null ? ordem.containsKey(_int(a['entrada_id'])) : _int(a['entrada_id']) == ent))
          a,
    ]..sort((x, y) {
        final o = (ordem[_int(x['entrada_id'])] ?? 0).compareTo(ordem[_int(y['entrada_id'])] ?? 0);
        return o != 0 ? o : _t(x['brinco']).compareTo(_t(y['brinco']));
      });
    final ids = [for (final a in l.take(qtd)) _int(a['id'])!];
    if (baixar) usados.addAll(ids);
    return ids;
  }

  final jaSaidas = ja('saidas');
  final vendas = _lista(b['vendas'])..sort((x, y) => _t(x['data']).compareTo(_t(y['data'])));
  for (final v in vendas) {
    final gid = 'venda:${v['id']}';
    if (jaSaidas.contains(gid)) {
      r.jaExistiam++;
      continue;
    }
    final qtd = _int(v['qtd']) ?? 0;
    final ids = ativos(_t(v['compraId']).isEmpty ? null : _t(v['compraId']), qtd);
    if (ids.length < qtd) r.avisos.add('Venda de ${v['data']}: só havia ${ids.length} de $qtd animais ativos.');
    if (ids.isEmpty) continue;
    final porArroba = v['modo'] == 'arroba';
    final peso = _n(v['pesoTotal']);
    final bruto = porArroba ? peso / 15 * _n(v['valorArroba']) : qtd * _n(v['valorCabeca']);
    final funrural = _n(v['funrural']);
    final descontos = _n(v['fundepec']) + funrural + _n(v['nota']) + _n(v['frete']) + _n(v['outros']);
    await Db.registrarSaida({
      'tipo': 'Venda',
      'data': _t(v['data']),
      'peso_total': peso > 0 ? peso : null,
      'valor_total': bruto - descontos,
      'por_arroba': porArroba,
      'preco': porArroba ? _n(v['valorArroba']) : _n(v['valorCabeca']),
      if (porArroba) ...{'arrobas': peso / 15, 'rendimento_pct': 100.0},
      'bruto': bruto,
      'funrural_pct': bruto > 0 ? funrural / bruto * 100 : 0.0,
      'funrural': funrural,
      'fundepec': _n(v['fundepec']),
      'nota': _n(v['nota']),
      'frete': _n(v['frete']),
      'outros': _n(v['outros']),
      'destino': _t(v['destino']).isEmpty ? null : _t(v['destino']),
      'obs': _t(v['obs']).isEmpty ? null : _t(v['obs']),
      'guarai_id': gid,
    }, ids);
    r.vendas++;
  }

  for (final s in _lista(b['saidas'])) {
    final gid = 'saida:${s['id']}';
    if (jaSaidas.contains(gid)) {
      r.jaExistiam++;
      continue;
    }
    final ids = ativos(null, _int(s['qtd']) ?? 0);
    if (ids.isEmpty) continue;
    await Db.registrarSaida({
      'tipo': _tipoSaida(_t(s['motivo'])),
      'data': _t(s['data']),
      'obs': [_t(s['motivo']), _t(s['obs'])].where((x) => x.isNotEmpty).join(' · '),
      'guarai_id': gid,
    }, ids);
    r.saidas++;
  }

  final jaCustos = ja('custos');
  for (final d in _lista(b['despesas'])) {
    final gid = 'despesa:${d['id']}';
    if (jaCustos.contains(gid)) {
      r.jaExistiam++;
      continue;
    }
    final mes = _t(d['mes']);
    final detalhe = _n(d['qtd']) > 0 && _n(d['unitario']) > 0 ? ' (${_t(d['qtd'])} × ${_t(d['unitario'])})' : '';
    await Db.inserir('custos', {
      'propriedade_id': pid,
      'data': _t(d['data']).length >= 10 ? _t(d['data']) : (mes.length == 7 ? '$mes-15' : null),
      'categoria': _categoriaCusto(_t(d['tipo'])),
      'descricao': [_t(d['tipo']), _t(d['descricao'])].where((x) => x.isNotEmpty).join(' · ') + detalhe,
      'valor': _n(d['valor']),
      'guarai_id': gid,
    });
    r.despesas++;
  }

  final jaPesagens = ja('pesagens');
  for (final p in _lista(b['pesagens'])) {
    final gid = 'pesagem:${p['id']}';
    if (jaPesagens.contains(gid)) {
      r.jaExistiam++;
      continue;
    }
    final q = _int(p['qtd']) ?? 0;
    if (q <= 0 || _n(p['pesoTotal']) <= 0) continue;
    final medio = _n(p['pesoTotal']) / q;
    for (final id in ativos(_t(p['compraId']).isEmpty ? null : _t(p['compraId']), q, baixar: false)) {
      await Db.inserir('pesagens', {
        'propriedade_id': pid,
        'animal_id': id,
        'data': _t(p['data']),
        'peso': medio,
        'evento': 'Pesagem do lote (Gado Guaraí)',
        'guarai_id': gid,
      });
    }
    r.pesagens++;
  }
  return r;
}
