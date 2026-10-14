import 'package:eito_gestao_rural/util/formato.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lê pesos nos formatos das balanças', () {
    expect(lerNumero('452,5'), 452.5);
    expect(lerNumero('452.5 kg'), 452.5);
    expect(lerNumero('ST,GS,+0452.5kg'), 452.5);
    expect(lerNumero('sem número'), isNull);
  });

  test('separa peso de brinco eletrônico', () {
    expect(parecePeso('452,5'), isTrue);
    expect(parecePeso('982000123456789'), isFalse); // RFID de 15 dígitos
  });

  test('formata em padrão brasileiro', () {
    expect(pesoKg(380), '380 kg');
    expect(pesoKg(380.5), '380,5 kg');
    expect(dataBr(DateTime(2026, 3, 7)), '07/03/2026');
  });
}
