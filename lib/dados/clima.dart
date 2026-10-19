// Clima da propriedade: tempo agora e previsão de 7 dias (Open-Meteo).
// Usa a localização da fazenda (marcada no app ou o centro dos piquetes
// desenhados no mapa), não a de quem está olhando.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'db.dart';
import 'mapa.dart' show Ponto, centro, contorno;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _num(Object? v) => v is num ? v.toDouble() : null;

const _wmo = <int, String>{
  0: 'Céu limpo', 1: 'Poucas nuvens', 2: 'Parcialmente nublado', 3: 'Nublado', 45: 'Neblina', 48: 'Neblina',
  51: 'Garoa fraca', 53: 'Garoa', 55: 'Garoa forte', 61: 'Chuva fraca', 63: 'Chuva', 65: 'Chuva forte',
  66: 'Chuva congelante', 67: 'Chuva congelante', 71: 'Neve', 73: 'Neve', 75: 'Neve', 80: 'Pancadas de chuva',
  81: 'Pancadas de chuva', 82: 'Pancadas fortes', 95: 'Trovoadas', 96: 'Trovoadas com granizo', 99: 'Trovoadas com granizo',
};

String descricaoTempo(int? codigo) => _wmo[codigo] ?? 'Tempo';

/// Localização salva para a propriedade (config/clima → {"<id>": {lat, lng}}).
Ponto? localSalvo(int propriedadeId) {
  final m = Db.registro('config', 'clima')?['$propriedadeId'];
  if (m is! Map) return null;
  final lat = _num(m['lat']), lng = _num(m['lng']);
  return lat == null || lng == null ? null : (lat: lat, lng: lng);
}

/// Centro dos piquetes desenhados no mapa da propriedade.
Ponto? centroDosPiquetes(int propriedadeId) {
  final pts = <Ponto>[];
  for (final p in Db.registros('piquetes')) {
    if (_int(p['propriedade_id']) != propriedadeId) continue;
    pts.addAll(contorno(p));
  }
  return centro(pts);
}

Ponto? localDaFazenda(int propriedadeId) => localSalvo(propriedadeId) ?? centroDosPiquetes(propriedadeId);

Future<void> salvarLocal(int propriedadeId, Ponto p) async {
  final atual = Map<String, Object?>.from(Db.registro('config', 'clima') ?? {})..remove('id');
  atual['$propriedadeId'] = {'lat': p.lat, 'lng': p.lng};
  await Db.salvarConfig('clima', atual);
}

class DiaPrevisao {
  DiaPrevisao(this.data, this.codigo, this.max, this.min, this.chuvaMm, this.chanceChuva);
  final String data;
  final int? codigo;
  final double? max, min, chuvaMm;
  final int? chanceChuva;
}

class Clima {
  Clima({this.temperatura, this.umidade, this.vento, this.chuvaAgora, this.codigo, required this.dias});
  final double? temperatura, umidade, vento, chuvaAgora;
  final int? codigo;
  final List<DiaPrevisao> dias;

  double get chuva7Dias => dias.fold(0, (s, d) => s + (d.chuvaMm ?? 0));
}

Clima climaDoJson(Map<String, dynamic> d) {
  final c = (d['current'] as Map?) ?? const {};
  final dd = (d['daily'] as Map?) ?? const {};
  List<Object?> col(String k) => (dd[k] as List?) ?? const [];
  final datas = col('time');
  return Clima(
    temperatura: _num(c['temperature_2m']),
    umidade: _num(c['relative_humidity_2m']),
    vento: _num(c['wind_speed_10m']),
    chuvaAgora: _num(c['precipitation']),
    codigo: _int(c['weather_code']),
    dias: [
      for (var i = 0; i < datas.length; i++)
        DiaPrevisao(
          '${datas[i]}',
          i < col('weather_code').length ? _int(col('weather_code')[i]) : null,
          i < col('temperature_2m_max').length ? _num(col('temperature_2m_max')[i]) : null,
          i < col('temperature_2m_min').length ? _num(col('temperature_2m_min')[i]) : null,
          i < col('precipitation_sum').length ? _num(col('precipitation_sum')[i]) : null,
          i < col('precipitation_probability_max').length ? _int(col('precipitation_probability_max')[i]) : null,
        ),
    ],
  );
}

final _cache = <String, (DateTime, Clima)>{};

/// Busca o clima (guarda por 30 minutos).
Future<Clima> buscarClima(Ponto p) async {
  final chave = '${p.lat.toStringAsFixed(3)},${p.lng.toStringAsFixed(3)}';
  final c = _cache[chave];
  if (c != null && DateTime.now().difference(c.$1).inMinutes < 30) return c.$2;
  final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': p.lat.toStringAsFixed(4),
    'longitude': p.lng.toStringAsFixed(4),
    'timezone': 'America/Sao_Paulo',
    'forecast_days': '7',
    'current': 'temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m',
    'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max',
  });
  final r = await http.get(uri).timeout(const Duration(seconds: 10));
  if (r.statusCode != 200) throw 'O serviço de clima não respondeu (${r.statusCode}).';
  final clima = climaDoJson(jsonDecode(r.body) as Map<String, dynamic>);
  _cache[chave] = (DateTime.now(), clima);
  return clima;
}
