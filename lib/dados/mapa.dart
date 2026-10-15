// Mapa da fazenda: contorno dos piquetes, lotação em UA/ha, rodízio de pastejo,
// pontos (aguadas, cochos, cercas...), ocorrências com foto e GPS e contagem
// de campo por piquete.
import 'dart:math';

import 'db.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _num(Object? v) => v is num ? v.toDouble() : null;
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);

int _dias(String de, String ate) {
  final a = DateTime.parse(de), b = DateTime.parse(ate);
  return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

typedef Ponto = ({double lat, double lng});

// ---------- Geometria ----------

/// Contorno salvo no piquete: lista de {lat, lng}.
List<Ponto> contorno(Reg piquete) => [
      for (final p in (piquete['contorno'] as List?) ?? const [])
        if (p is Map && _num(p['lat']) != null && _num(p['lng']) != null) (lat: _num(p['lat'])!, lng: _num(p['lng'])!),
    ];

List<Map<String, double>> contornoParaSalvar(List<Ponto> pontos) => [
      for (final p in pontos) {'lat': p.lat, 'lng': p.lng},
    ];

/// Área do polígono em hectares (projeção local; boa para áreas de fazenda).
double areaHa(List<Ponto> pts) {
  if (pts.length < 3) return 0;
  const r = 6371008.8; // raio médio da Terra (m)
  final lat0 = pts.map((p) => p.lat).reduce((a, b) => a + b) / pts.length * pi / 180;
  double x(Ponto p) => p.lng * pi / 180 * r * cos(lat0);
  double y(Ponto p) => p.lat * pi / 180 * r;
  var s = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    s += x(a) * y(b) - x(b) * y(a);
  }
  return s.abs() / 2 / 10000;
}

Ponto? centro(List<Ponto> pts) => pts.isEmpty
    ? null
    : (
        lat: pts.map((p) => p.lat).reduce((a, b) => a + b) / pts.length,
        lng: pts.map((p) => p.lng).reduce((a, b) => a + b) / pts.length,
      );

/// O ponto está dentro do polígono? (ray casting)
bool dentro(Ponto p, List<Ponto> pol) {
  if (pol.length < 3) return false;
  var d = false;
  for (var i = 0, j = pol.length - 1; i < pol.length; j = i++) {
    final a = pol[i], b = pol[j];
    if ((a.lat > p.lat) != (b.lat > p.lat) && p.lng < (b.lng - a.lng) * (p.lat - a.lat) / (b.lat - a.lat) + a.lng) {
      d = !d;
    }
  }
  return d;
}

/// Piquete da propriedade aberta que contém o ponto, se algum.
Reg? piqueteNoPonto(Ponto p) {
  for (final q in Db.registros('piquetes')) {
    if (_int(q['propriedade_id']) == Db.pid && dentro(p, contorno(q))) return q;
  }
  return null;
}

// ---------- Lotação (UA/ha) ----------

/// 1 UA = 450 kg de peso vivo.
const kgPorUa = 450.0;

/// Peso usado quando o animal não tem pesagem.
const pesoPorCategoria = {
  'Bezerro': 150.0,
  'Bezerra': 150.0,
  'Garrote': 300.0,
  'Novilha': 300.0,
  'Boi': 450.0,
  'Vaca': 450.0,
  'Touro': 650.0,
};

Map<int?, double> _ultimosPesos() {
  final ultima = <int?, (String, double)>{};
  for (final p in Db.registros('pesagens')) {
    final id = _int(p['animal_id']);
    final peso = _num(p['peso']);
    if (peso == null) continue;
    final d = _dia(p['data']);
    if (ultima[id] == null || d.compareTo(ultima[id]!.$1) >= 0) ultima[id] = (d, peso);
  }
  return {for (final e in ultima.entries) e.key: e.value.$2};
}

class Lotacao {
  Lotacao(this.piquete);
  final Reg piquete;
  int cabecas = 0;
  double kg = 0;

  /// Animais sem pesagem, contados pelo peso típico da categoria.
  int estimados = 0;

  double get ua => kg / kgPorUa;

  /// Área do cadastro, ou a do contorno desenhado.
  double? get area {
    final a = _num(piquete['area']);
    if (a != null && a > 0) return a;
    final c = areaHa(contorno(piquete));
    return c > 0 ? c : null;
  }

  double? get uaHa => area == null ? null : ua / area!;

  /// Capacidade de suporte cadastrada (UA/ha).
  double? get capacidade => _num(piquete['capacidade']);

  /// Acima da capacidade cadastrada.
  bool get acima => capacidade != null && uaHa != null && uaHa! > capacidade!;
}

/// Lotação de cada piquete da propriedade aberta (pelos animais ativos que estão nele).
Map<int, Lotacao> lotacaoPiquetes() {
  final r = {
    for (final q in Db.registros('piquetes'))
      if (_int(q['propriedade_id']) == Db.pid) _int(q['id'])!: Lotacao(q),
  };
  final pesos = _ultimosPesos();
  for (final a in Db.registros('animais')) {
    if (a['status'] != 'Ativo') continue;
    final l = r[_int(a['piquete_id'])];
    if (l == null) continue;
    l.cabecas++;
    final p = pesos[_int(a['id'])];
    if (p == null) l.estimados++;
    l.kg += p ?? pesoPorCategoria[a['categoria']] ?? 350;
  }
  return r;
}

// ---------- Rodízio de pastejo ----------

/// Dias de ocupação e de descanso usados quando o piquete não tem os seus.
const ocupacaoPadrao = 7, descansoPadrao = 30;

enum SituacaoPasto { ocupado, trocar, descansando, pronto, semHistorico }

class Rodizio {
  Rodizio(this.piquete, this.situacao, this.dias, this.limite);
  final Reg piquete;
  final SituacaoPasto situacao;

  /// Dias de ocupação (com gado) ou de descanso (vazio).
  final int? dias;

  /// Limite de dias de ocupação ou de descanso deste piquete.
  final int limite;

  String get texto => switch (situacao) {
        SituacaoPasto.ocupado => 'Ocupado há $dias de $limite dias',
        SituacaoPasto.trocar => 'Trocar o gado: ocupado há $dias dias (limite $limite)',
        SituacaoPasto.descansando => 'Descansando há $dias de $limite dias',
        SituacaoPasto.pronto => 'Pronto para receber: descansou $dias dias',
        SituacaoPasto.semHistorico => 'Sem entrada ou saída registrada',
      };
}

/// Situação de rodízio de cada piquete, pelas entradas e saídas de animais.
List<Rodizio> rodizio(String hoje) {
  final lot = lotacaoPiquetes();
  final entrada = <int?, String>{}, saida = <int?, String>{};
  for (final p in Db.registros('pastagens')) {
    final q = _int(p['piquete_id']);
    final d = _dia(p['data']);
    if (d.length < 10) continue;
    final mapa = switch (p['tipo']) {
      'Entrada de animais' => entrada,
      'Saída de animais' || 'Vedação (descanso)' => saida,
      _ => null,
    };
    if (mapa != null && (mapa[q] ?? '').compareTo(d) < 0) mapa[q] = d;
  }
  final r = <Rodizio>[];
  for (final l in lot.values) {
    final q = _int(l.piquete['id']);
    final ocupacao = _int(l.piquete['dias_ocupacao']) ?? ocupacaoPadrao;
    final descanso = _int(l.piquete['dias_descanso']) ?? descansoPadrao;
    if (l.cabecas > 0) {
      final e = entrada[q];
      if (e == null) {
        r.add(Rodizio(l.piquete, SituacaoPasto.semHistorico, null, ocupacao));
      } else {
        final d = _dias(e, hoje);
        r.add(Rodizio(l.piquete, d > ocupacao ? SituacaoPasto.trocar : SituacaoPasto.ocupado, d, ocupacao));
      }
    } else {
      final s = saida[q];
      if (s == null) {
        r.add(Rodizio(l.piquete, SituacaoPasto.semHistorico, null, descanso));
      } else {
        final d = _dias(s, hoje);
        r.add(Rodizio(l.piquete, d >= descanso ? SituacaoPasto.pronto : SituacaoPasto.descansando, d, descanso));
      }
    }
  }
  return r..sort((a, b) => _t(a.piquete['nome']).toLowerCase().compareTo(_t(b.piquete['nome']).toLowerCase()));
}

// ---------- Pontos do mapa ----------

const tiposPonto = ['Aguada', 'Cocho', 'Saleiro', 'Cerca / porteira', 'Curral', 'Sede', 'Outro'];

List<Reg> pontos() => [
      for (final p in Db.registros('pontos'))
        if (_int(p['propriedade_id']) == Db.pid) p,
    ]..sort((a, b) => _t(a['nome']).toLowerCase().compareTo(_t(b['nome']).toLowerCase()));

Future<int> salvarPonto(Reg v, {int? id}) async {
  if (id != null) {
    await Db.atualizar('pontos', id, v);
    return id;
  }
  return Db.inserir('pontos', {...v, 'propriedade_id': Db.pid});
}

// ---------- Ocorrências ----------

const tiposOcorrencia = [
  'Cerca quebrada',
  'Aguada / bebedouro',
  'Cocho',
  'Animal doente ou machucado',
  'Animal morto',
  'Animal fora do lugar',
  'Praga / planta invasora',
  'Erosão / estrada',
  'Manutenção feita',
  'Outro',
];

List<Reg> ocorrencias({bool soAbertas = false, int? pontoId}) => [
      for (final o in Db.registros('ocorrencias'))
        if (_int(o['propriedade_id']) == Db.pid &&
            (!soAbertas || o['resolvida'] != true) &&
            (pontoId == null || _int(o['ponto_id']) == pontoId))
          o,
    ]..sort((a, b) => _t(b['data']).compareTo(_t(a['data'])));

Future<int> salvarOcorrencia(Reg v, {int? id}) async {
  if (id != null) {
    await Db.atualizar('ocorrencias', id, v);
    return id;
  }
  return Db.inserir('ocorrencias', {'resolvida': false, ...v, 'propriedade_id': Db.pid});
}

Future<void> resolverOcorrencia(int id, bool resolvida, String data) =>
    Db.atualizar('ocorrencias', id, {'resolvida': resolvida, 'resolvida_em': resolvida ? data : null});

// ---------- Contagem de campo ----------

/// Animais ativos que deveriam estar no piquete.
List<Reg> animaisNoPiquete(int piqueteId) => [
      for (final a in Db.registros('animais'))
        if (a['status'] == 'Ativo' && _int(a['piquete_id']) == piqueteId) a,
    ]..sort((a, b) => _t(a['brinco']).compareTo(_t(b['brinco'])));

Future<int> registrarContagem(int piqueteId, String data, int contado, {String? obs}) => Db.inserir('contagens', {
      'propriedade_id': Db.pid,
      'piquete_id': piqueteId,
      'data': data,
      'esperado': animaisNoPiquete(piqueteId).length,
      'contado': contado,
      'obs': obs,
    });

List<Reg> contagens({int? piqueteId}) => [
      for (final c in Db.registros('contagens'))
        if (_int(c['propriedade_id']) == Db.pid && (piqueteId == null || _int(c['piquete_id']) == piqueteId)) c,
    ]..sort((a, b) => _t(b['data']).compareTo(_t(a['data'])));
