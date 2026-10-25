// Leitura de arquivo KML (Google Earth) para trazer os pastos já desenhados.
import 'mapa.dart' show Ponto, areaHa;

class PoligonoKml {
  PoligonoKml(this.nome, this.pontos);
  final String nome;
  final List<Ponto> pontos;

  double get area => areaHa(pontos);
}

String _semTags(String s) => s
    .replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16)))
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&') // por último: "&amp;lt;" fica "&lt;"
    .trim();

/// Pontos de um bloco <coordinates> ("lng,lat[,alt]" separados por espaço).
List<Ponto> _coordenadas(String texto) {
  final pts = <Ponto>[];
  for (final t in texto.trim().split(RegExp(r'\s+'))) {
    final c = t.split(',');
    if (c.length < 2) continue;
    final lng = double.tryParse(c[0]), lat = double.tryParse(c[1]);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) continue;
    pts.add((lat: lat, lng: lng));
  }
  // O KML repete o primeiro ponto no fim para fechar o polígono.
  if (pts.length > 1 && pts.first == pts.last) pts.removeLast();
  return pts;
}

/// Polígonos do arquivo, com o nome do Placemark (só o contorno de fora de cada um).
List<PoligonoKml> lerKml(String kml) {
  final r = <PoligonoKml>[];
  var semNome = 0;
  for (final pm in RegExp(r'<Placemark\b[\s\S]*?</Placemark>', caseSensitive: false).allMatches(kml)) {
    final bloco = pm.group(0)!;
    final nome = RegExp(r'<name>([\s\S]*?)</name>', caseSensitive: false).firstMatch(bloco)?.group(1);
    final poligonos = RegExp(r'<Polygon\b[\s\S]*?</Polygon>', caseSensitive: false).allMatches(bloco).toList();
    for (final (i, pg) in poligonos.indexed) {
      final fora = RegExp(r'<outerBoundaryIs>[\s\S]*?</outerBoundaryIs>', caseSensitive: false)
              .firstMatch(pg.group(0)!)
              ?.group(0) ??
          pg.group(0)!;
      final coords = RegExp(r'<coordinates>([\s\S]*?)</coordinates>', caseSensitive: false).firstMatch(fora)?.group(1);
      final pts = coords == null ? <Ponto>[] : _coordenadas(coords);
      if (pts.length < 3) continue;
      var n = nome == null ? '' : _semTags(nome);
      if (n.isEmpty) n = 'Pasto ${++semNome}';
      if (poligonos.length > 1) n = '$n ${i + 1}';
      r.add(PoligonoKml(n, pts));
    }
  }
  return r;
}
