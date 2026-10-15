import 'package:eito_gestao_rural/telas/login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('código de indicação sem espaços e em minúsculas', () {
    expect(codigoIndicacao(' Carol Nutroeste '), 'carolnutroeste');
    expect(codigoIndicacao('PEQUENO'), 'pequeno');
    expect(codigoIndicacao('   '), '');
  });
}
