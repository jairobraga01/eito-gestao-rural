import 'package:eito_gestao_rural/dados/db.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int pid;

  setUp(() async {
    Db.bancoTeste = FakeFirebaseFirestore();
    await Db.iniciar('teste');
    pid = Db.pid;
  });

  tearDown(Db.encerrar);

  Future<int> animal(String brinco, {String sexo = 'F', int? mae, String? rfid}) => Db.inserir('animais', {
        'propriedade_id': pid,
        'brinco': brinco,
        'sexo': sexo,
        'status': 'Ativo',
        'mae_id': mae,
        'rfid': rfid,
      });

  test('cria uma propriedade ao entrar numa conta nova', () {
    expect(pid, isNot(-1));
    expect(Db.registros('propriedades'), hasLength(1));
  });

  test('não deixa repetir brinco ativo na mesma propriedade', () async {
    await animal('100');
    expect(() => animal('100'), throwsA(isA<RegistroDuplicado>()));
    expect(() => animal(' 100 '), throwsA(isA<RegistroDuplicado>()));
  });

  test('não deixa repetir brinco eletrônico', () async {
    await animal('1', rfid: '982000123456789');
    expect(() => animal('2', rfid: '982000123456789'), throwsA(isA<RegistroDuplicado>()));
  });

  test('libera o brinco de animal que já saiu', () async {
    final id = await animal('200');
    await Db.atualizar('animais', id, {'status': 'Vendido'});
    expect(await animal('200'), isNonZero);
  });

  test('excluir animal apaga pesagens, sanidade e reprodução e solta as crias', () async {
    final vaca = await animal('300');
    final cria = await animal('301', mae: vaca);
    await Db.inserir('pesagens', {'animal_id': vaca, 'data': '2026-01-01', 'peso': 400});
    await Db.inserir('sanidade', {'animal_id': vaca, 'data': '2026-01-01'});
    await Db.inserir('reproducoes', {'femea_id': vaca, 'data': '2026-01-01'});

    await Db.excluir('animais', vaca);
    await pumpEventQueue(); // deixa chegar os avisos do banco

    expect(Db.registro('animais', vaca), isNull);
    expect(Db.registros('pesagens'), isEmpty);
    expect(Db.registros('sanidade'), isEmpty);
    expect(Db.registros('reproducoes'), isEmpty);
    expect(Db.registro('animais', cria)?['mae_id'], isNull);
  });

  test('excluir lote mantém os animais, só tira do lote', () async {
    final lote = await Db.inserir('lotes', {'propriedade_id': pid, 'nome': 'Novilhas'});
    final a = await animal('400');
    await Db.atualizar('animais', a, {'lote_id': lote});

    await Db.excluir('lotes', lote);
    await pumpEventQueue();

    expect(Db.registro('animais', a), isNotNull);
    expect(Db.registro('animais', a)?['lote_id'], isNull);
  });

  test('GMD da pesagem rápida usa os dias desde a pesagem anterior', () async {
    final a = await animal('500');
    expect(await Db.registrarPesagem(a, 300, data: '2026-01-01'), isNull);
    expect(await Db.registrarPesagem(a, 330, data: '2026-01-31'), closeTo(1.0, 1e-9));
    // Mesmo dia: não calcula
    expect(await Db.registrarPesagem(a, 331, data: '2026-01-31'), isNull);
  });

  test('brinco: a fazenda aberta vem antes; transferência não duplica brinco', () async {
    final b = await Db.inserir('propriedades', {'nome': 'Fazenda B'});
    final vendido = await animal('15');
    await Db.atualizar('animais', vendido, {'status': 'Vendido'});
    await Db.inserir('animais', {'propriedade_id': b, 'brinco': '15', 'sexo': 'F', 'status': 'Ativo'});
    await pumpEventQueue();
    expect((await Db.buscarPorCodigo('15'))!['id'], vendido);
    await Db.atualizar('animais', vendido, {'propriedade_id': b});
    await pumpEventQueue();
    expect(await Db.buscarPorCodigo('15', soDestaFazenda: true), isNull);

    final a = await animal('20');
    await Db.inserir('animais', {'propriedade_id': b, 'brinco': '20', 'sexo': 'F', 'status': 'Ativo'});
    await pumpEventQueue();
    expect(() => Db.moverAnimais([Db.registro('animais', a)!], {'propriedade_id': b}, '2026-10-20'),
        throwsA(isA<RegistroDuplicado>()));
  });
}
