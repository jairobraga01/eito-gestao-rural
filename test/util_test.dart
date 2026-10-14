import 'package:eito_gestao_rural/util/util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parto previsto soma $diasGestacao dias', () {
    expect(somaDias('2026-01-10', diasGestacao), '2026-10-27');
  });

  test('lê números no formato brasileiro', () {
    expect(lerNumero('450'), 450);
    expect(lerNumero('450,5'), 450.5);
    expect(lerNumero('1.250,5'), 1250.5);
    expect(lerNumero(''), isNull);
  });

  test('dias entre datas', () {
    expect(diasEntre('2026-01-01', '2026-03-01'), 59);
  });

  test('categoria sugerida pela idade', () {
    final hoje = DateTime.now();
    final seisMeses = isoDe(DateTime(hoje.year, hoje.month - 6, hoje.day));
    expect(sugerirCategoria('F', seisMeses), 'Bezerra');
    expect(sugerirCategoria('M', null), 'Boi');
  });
}
