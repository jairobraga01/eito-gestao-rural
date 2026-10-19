import 'package:eito_gestao_rural/dados/kml.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
<Placemark><name><![CDATA[Pasto da Grota]]></name>
<Polygon><outerBoundaryIs><LinearRing><coordinates>
-49.1000,-15.3000,0 -49.0907,-15.3000,0 -49.0907,-15.2910,0 -49.1000,-15.2910,0 -49.1000,-15.3000,0
</coordinates></LinearRing></outerBoundaryIs>
<innerBoundaryIs><LinearRing><coordinates>-49.09,-15.29 -49.08,-15.29 -49.08,-15.28</coordinates></LinearRing></innerBoundaryIs>
</Polygon></Placemark>
<Placemark><name>Sede</name><Point><coordinates>-49.1,-15.3,0</coordinates></Point></Placemark>
<Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>-49.2,-15.4 -49.19,-15.4 -49.19,-15.39</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>
</Document></kml>''';

  test('lê os polígonos com nome, ignora pontos e furos', () {
    final p = lerKml(kml);
    expect(p.map((x) => x.nome), ['Pasto da Grota', 'Pasto 1']);
    expect(p.first.pontos.length, 4);
    expect(p.first.pontos.first, (lat: -15.3, lng: -49.1));
    expect(p.first.area, closeTo(100, 5));
  });

  test('arquivo sem polígono', () {
    expect(lerKml('<kml></kml>'), isEmpty);
  });
}
