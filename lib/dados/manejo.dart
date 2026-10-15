// Fila do dia, intervalo entre partos e projeção de abate da propriedade aberta.
import 'db.dart';
import 'mapa.dart' show rodizio, SituacaoPasto;
import 'gestao.dart' show pendenciasCalendario;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);

DateTime _data(String iso) => DateTime.parse(iso.substring(0, 10));
int _dias(String de, String ate) {
  final a = _data(de), b = _data(ate);
  return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

String _soma(String iso, int dias) => Db.dataEtapa(iso, dias);

/// Protocolos de IATF prontos: etapas pelo dia contado do D0. A última é a inseminação.
const protocolosIatf = <String, List<(int, String)>>{
  'D0-D8-D10': [(0, 'Implante + benzoato de estradiol'), (8, 'Retirada do implante + eCG + cipionato'), (10, 'IATF')],
  'D0-D7-D9': [(0, 'Implante + benzoato de estradiol'), (7, 'Retirada do implante + eCG + cipionato'), (9, 'IATF')],
  'D0-D9-D11': [(0, 'Implante + benzoato de estradiol'), (9, 'Retirada do implante + eCG + cipionato'), (11, 'IATF')],
};

// ---------- Fila do dia ----------

enum TipoFila { protocolo, sanidade, diagnostico, parto, pasto }

class ItemFila {
  const ItemFila(this.tipo, this.chave, this.titulo, this.detalhe, {this.atrasado = false, this.animalId});
  final TipoFila tipo;

  /// Identifica o item para riscar.
  final String chave;
  final String titulo, detalhe;
  final bool atrasado;
  final int? animalId;
}

/// O que fazer hoje no curral: etapas de protocolo, aplicações vencendo,
/// diagnósticos de gestação e partos dos próximos 7 dias (com os atrasados).
List<ItemFila> filaDoDia(String hoje) {
  final pid = Db.pid;
  final ativos = {
    for (final a in Db.registros('animais'))
      if (_int(a['propriedade_id']) == pid && a['status'] == 'Ativo') _int(a['id']): a,
  };
  String brinco(Object? id) => _t(ativos[_int(id)]?['brinco']);
  final itens = <ItemFila>[];

  // Etapas de protocolo de hoje ou atrasadas até 2 dias.
  for (final p in Db.registros('protocolos')) {
    if (_int(p['propriedade_id']) != pid || p['inicio'] == null) continue;
    final vacas = [for (final f in (p['femeas'] as List?) ?? const []) if (ativos.containsKey(_int(f))) brinco(f)];
    if (vacas.isEmpty) continue;
    for (final e in (p['etapas'] as List?) ?? const []) {
      final etapa = Map<String, Object?>.from(e as Map);
      final data = _soma(_t(p['inicio']), _int(etapa['dia']) ?? 0);
      final atraso = _dias(data, hoje);
      if (atraso < 0 || atraso > 2) continue;
      itens.add(ItemFila(
        TipoFila.protocolo,
        'prot_${p['id']}_${etapa['dia']}',
        'D${etapa['dia']} · ${etapa['nome']}',
        '${p['nome']} · ${vacas.length} ${vacas.length == 1 ? 'vaca' : 'vacas'}: ${vacas.join(', ')}',
        atrasado: atraso > 0,
      ));
    }
  }

  // Aplicações vencidas ou de hoje, ainda não refeitas, por produto.
  final ultima = <String, String>{};
  final sanidade = [
    for (final s in Db.registros('sanidade'))
      if (ativos.containsKey(_int(s['animal_id']))) s,
  ];
  for (final s in sanidade) {
    final k = '${s['animal_id']}|${_t(s['produto']).toLowerCase()}';
    if ((ultima[k] ?? '').compareTo(_dia(s['data'])) < 0) ultima[k] = _dia(s['data']);
  }
  final porProduto = <String, (String, String, Set<String>)>{};
  for (final s in sanidade) {
    final prox = _dia(s['proxima']);
    if (prox.isEmpty || prox.compareTo(hoje) > 0) continue;
    final k = '${s['animal_id']}|${_t(s['produto']).toLowerCase()}';
    if (_dia(s['data']).compareTo(ultima[k] ?? '') < 0) continue; // já refeita
    final atual = porProduto[_t(s['produto'])];
    final desde = atual == null || prox.compareTo(atual.$2) < 0 ? prox : atual.$2;
    porProduto[_t(s['produto'])] = (_t(s['tipo']), desde, {...?atual?.$3, brinco(s['animal_id'])});
  }
  for (final e in porProduto.entries) {
    final (tipo, desde, brincos) = e.value;
    itens.add(ItemFila(
      TipoFila.sanidade,
      'san_${e.key}',
      '${e.key} · ${brincos.length} ${brincos.length == 1 ? 'animal' : 'animais'}',
      '$tipo · ${desde == hoje ? 'vence hoje' : 'vencida desde ${desde.substring(8, 10)}/${desde.substring(5, 7)}'} · ${brincos.join(', ')}',
      atrasado: desde.compareTo(hoje) < 0,
    ));
  }

  // Calendário sanitário pronto (brucelose, raiva, vermífugo...).
  for (final (item, brincos) in pendenciasCalendario(hoje)) {
    itens.add(ItemFila(
      TipoFila.sanidade,
      'cal_${item.id}_${hoje.substring(0, 7)}',
      '${item.nome} · ${brincos.length} ${brincos.length == 1 ? 'animal' : 'animais'}',
      'Calendário: ${item.descricao} · ${brincos.join(', ')}',
    ));
  }

  // Diagnósticos (30 dias ou mais após o serviço) e partos dos próximos 7 dias.
  for (final r in Db.registros('reproducoes')) {
    final f = _int(r['femea_id']);
    if (!ativos.containsKey(f) || r['parto_data'] != null) continue;
    if (r['diagnostico'] == 'Pendente' && _t(r['data']).isNotEmpty) {
      final dias = _dias(_t(r['data']), hoje);
      if (dias >= 30) {
        itens.add(ItemFila(TipoFila.diagnostico, 'diag_${r['id']}', 'Diagnóstico · brinco ${brinco(f)}',
            '${r['tipo']} há $dias dias', atrasado: dias > 45, animalId: f));
      }
    } else if (r['diagnostico'] == 'Prenhe' && _t(r['parto_previsto']).isNotEmpty) {
      final falta = _dias(hoje, _t(r['parto_previsto']));
      if (falta <= 7) {
        itens.add(ItemFila(
          TipoFila.parto,
          'parto_${r['id']}',
          'Parto · brinco ${brinco(f)}',
          falta < 0 ? 'previsto há ${-falta} dias' : (falta == 0 ? 'previsto para hoje' : 'previsto em $falta dias'),
          atrasado: falta < 0,
          animalId: f,
        ));
      }
    }
  }
  // Rodízio: piquetes com o gado além dos dias de ocupação.
  for (final r in rodizio(hoje)) {
    if (r.situacao != SituacaoPasto.trocar) continue;
    itens.add(ItemFila(TipoFila.pasto, 'pasto_${r.piquete['id']}_$hoje', 'Trocar o gado · ${r.piquete['nome']}',
        'Ocupado há ${r.dias} dias (limite ${r.limite})', atrasado: true));
  }
  return itens;
}

// ---------- Intervalo entre partos ----------

/// Datas de parto da vaca: partos lançados na reprodução e nascimento das crias.
List<String> partosDaVaca(int vacaId) {
  final datas = <String>{
    for (final r in Db.registros('reproducoes'))
      if (_int(r['femea_id']) == vacaId && _t(r['parto_data']).isNotEmpty) _dia(r['parto_data']),
    for (final a in Db.registros('animais'))
      if (_int(a['mae_id']) == vacaId && _t(a['nascimento']).isNotEmpty) _dia(a['nascimento']),
  };
  // Gêmeos ou lançamento duplicado: partos com menos de 60 dias contam como um.
  final ordenadas = datas.toList()..sort();
  final r = <String>[];
  for (final d in ordenadas) {
    if (r.isEmpty || _dias(r.last, d) >= 60) r.add(d);
  }
  return r;
}

/// Intervalo médio entre partos (dias) da vaca, ou null com menos de 2 partos.
double? intervaloEntrePartos(int vacaId) {
  final p = partosDaVaca(vacaId);
  if (p.length < 2) return null;
  return _dias(p.first, p.last) / (p.length - 1);
}

/// Média do intervalo entre partos das vacas ativas da propriedade e quantas entram na conta.
(double?, int) intervaloEntrePartosRebanho() {
  final valores = <double>[];
  for (final a in Db.registros('animais')) {
    if (_int(a['propriedade_id']) != Db.pid || a['status'] != 'Ativo' || a['sexo'] != 'F') continue;
    final v = intervaloEntrePartos(_int(a['id'])!);
    if (v != null) valores.add(v);
  }
  return (valores.isEmpty ? null : valores.reduce((a, b) => a + b) / valores.length, valores.length);
}

// ---------- Projeção de abate ----------

class ProjecaoAnimal {
  ProjecaoAnimal(this.animal, this.peso, this.gmd, this.dias);
  final Reg animal;

  /// Último peso (kg) e GMD (kg/dia) da primeira à última pesagem.
  final double peso;
  final double? gmd;

  /// Dias até o peso alvo (0 = pronto; null = sem GMD para calcular).
  final int? dias;
}

class ProjecaoLote {
  ProjecaoLote(this.nome, this.animais);
  final String nome;
  final List<ProjecaoAnimal> animais;

  double get pesoMedio => animais.map((a) => a.peso).reduce((a, b) => a + b) / animais.length;
  double? get gmdMedio {
    final g = [for (final a in animais) if (a.gmd != null) a.gmd!];
    return g.isEmpty ? null : g.reduce((a, b) => a + b) / g.length;
  }

  int get prontos => animais.where((a) => a.dias == 0).length;

  /// Dias até a metade do lote chegar ao peso (mediana), ou null sem GMD.
  int? get diasMediana {
    final d = [for (final a in animais) if (a.dias != null) a.dias!]..sort();
    return d.isEmpty ? null : d[(d.length - 1) ~/ 2];
  }
}

/// Valor em reais de um animal vivo: peso × rendimento ÷ 15 kg por arroba × preço.
double valorArroba(double peso, double rendimento, double precoArroba) => peso * rendimento / 15 * precoArroba;

ProjecaoAnimal? projetarAnimal(Reg animal, List<Reg> pesagens, double alvo) {
  final ps = [for (final p in pesagens) if (p['peso'] is num && _t(p['data']).isNotEmpty) p]
    ..sort((a, b) {
      final c = _dia(a['data']).compareTo(_dia(b['data']));
      return c != 0 ? c : (_int(a['id']) ?? 0).compareTo(_int(b['id']) ?? 0);
    });
  if (ps.isEmpty) return null;
  final peso = (ps.last['peso'] as num).toDouble();
  double? gmd;
  if (ps.length >= 2) {
    final dias = _dias(_t(ps.first['data']), _t(ps.last['data']));
    if (dias > 0) gmd = (peso - (ps.first['peso'] as num)) / dias;
  }
  final int? dias;
  if (peso >= alvo) {
    dias = 0;
  } else if (gmd != null && gmd > 0) {
    dias = ((alvo - peso) / gmd).ceil();
  } else {
    dias = null;
  }
  return ProjecaoAnimal(animal, peso, gmd, dias);
}

/// Animais ativos com pesagem, agrupados por lote.
List<ProjecaoLote> projecaoAbate(double alvo) {
  final pid = Db.pid;
  final pesagens = <int?, List<Reg>>{};
  for (final p in Db.registros('pesagens')) {
    pesagens.putIfAbsent(_int(p['animal_id']), () => []).add(p);
  }
  final porLote = <String, List<ProjecaoAnimal>>{};
  for (final a in Db.registros('animais')) {
    if (_int(a['propriedade_id']) != pid || a['status'] != 'Ativo') continue;
    final pr = projetarAnimal(a, pesagens[_int(a['id'])] ?? const [], alvo);
    if (pr == null) continue;
    final lote = _t(Db.registro('lotes', a['lote_id'])?['nome']);
    porLote.putIfAbsent(lote.isEmpty ? 'Sem lote' : lote, () => []).add(pr);
  }
  return [
    for (final e in porLote.entries)
      ProjecaoLote(e.key, e.value..sort((a, b) => (a.dias ?? 1 << 30).compareTo(b.dias ?? 1 << 30))),
  ]..sort((a, b) => a.nome.compareTo(b.nome));
}
