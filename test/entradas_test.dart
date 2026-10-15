import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/numeracao.dart';
import 'package:eito_gestao_rural/dados/resumo_periodo.dart';
import 'package:eito_gestao_rural/telas/entradas.dart' show separarBrincos;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    Db.bancoTeste = FakeFirebaseFirestore();
    await Db.iniciar('teste');
  });

  tearDown(Db.encerrar);

  Future<int> compra(List<String> brincos, {num? peso, num? valor}) => Db.registrarEntrada(
        {'tipo': 'Compra', 'data': '2026-09-10', 'peso_total': peso, 'valor_total': valor, 'origem': 'Fazenda Boa Vista'},
        brincos,
        {'sexo': 'M', 'categoria': 'Garrote', 'raca': 'Nelore'},
      );

  test('gado sem brinco: prefixo sugerido e numeração que continua', () async {
    expect(prefixoSugerido(categoria: 'Vaca', sexo: 'F', tipo: 'Rebanho existente', data: '2026-10-25'), 'vaca_fazenda');
    expect(prefixoSugerido(categoria: 'Bezerra', sexo: 'F', tipo: 'Compra', data: '2026-10-25'),
        'bezerra_compra25OUT2026');
    expect(gerarBrincos('vaca_fazenda', 1, 3), ['vaca_fazenda_001', 'vaca_fazenda_002', 'vaca_fazenda_003']);
    expect(gerarBrincos('novilha_fazenda', 999, 2), ['novilha_fazenda_0999', 'novilha_fazenda_1000']);

    expect(proximoNumero('vaca_fazenda'), 1);
    await Db.registrarEntrada({'tipo': 'Rebanho existente', 'data': '2026-10-15'}, gerarBrincos('vaca_fazenda', 1, 400),
        {'sexo': 'F', 'categoria': 'Vaca'});
    expect(Db.registros('animais').length, 400);
    expect(proximoNumero('vaca_fazenda'), 401);
    expect(proximoNumero('novilha_fazenda'), 1);
  });

  test('separa os brincos por linha, vírgula ou espaço', () {
    expect(separarBrincos('101, 102\n103;104  105'), ['101', '102', '103', '104', '105']);
  });

  test('compra cadastra os animais e a pesagem de entrada com o peso médio', () async {
    final id = await compra(['101', '102'], peso: 600, valor: 6000);

    final animais = Db.registros('animais').where((a) => a['entrada_id'] == id).toList();
    expect(animais.map((a) => a['brinco']), unorderedEquals(['101', '102']));
    expect(animais.every((a) => a['origem'] == 'Compra' && a['status'] == 'Ativo' && a['raca'] == 'Nelore'), isTrue);
    expect(Db.registros('pesagens').map((p) => p['peso']), [300, 300]);
    expect(Db.registro('entradas', id)!['quantidade'], 2);
    expect((await Db.entradas()).single['brincos'], isNotNull);

    final set = ResumoPeriodo.mes(2026, 9);
    expect(set.entradas, 2);
    expect(set.cabecasCompradas, 2);
    expect(set.valorCompras, 6000);
  });

  test('não aceita brinco repetido na lista nem já ativo no rebanho', () async {
    expect(() => compra(['200', '200']), throwsA(isA<RegistroDuplicado>()));
    await compra(['201']);
    expect(() => compra(['202', '201']), throwsA(isA<RegistroDuplicado>()));
    expect(Db.registros('animais').where((a) => a['brinco'] == '202'), isEmpty);
  });

  test('excluir entrada mantém ou apaga os animais', () async {
    final a = await compra(['301'], peso: 300);
    final b = await compra(['302'], peso: 300);
    await pumpEventQueue();

    await Db.excluirEntrada(a);
    await pumpEventQueue(); // deixa chegar os avisos do banco
    final mantido = Db.registros('animais').singleWhere((x) => x['brinco'] == '301');
    expect(mantido['entrada_id'], isNull);

    await Db.excluirEntrada(b, apagarAnimais: true);
    await pumpEventQueue();
    expect(Db.registros('animais').where((x) => x['brinco'] == '302'), isEmpty);
    expect(Db.registros('pesagens'), hasLength(1));
    expect(Db.registros('entradas'), isEmpty);
  });
}
