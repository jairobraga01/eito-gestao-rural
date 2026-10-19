import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/indicacoes.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore banco;

  setUp(() async {
    banco = FakeFirebaseFirestore();
    Db.bancoTeste = banco;
    await banco.doc('indicacoes/carolnutroeste').set({'nome': 'Carol', 'tipo': 'zootecnista', 'ativo': true});
    await banco.doc('indicacoes/antigo').set({'nome': 'Zé', 'tipo': 'vendedor', 'ativo': false});
  });

  test('código de indicação sem espaços e em minúsculas', () {
    expect(codigoIndicacao(' Carol Nutroeste '), 'carolnutroeste');
    expect(codigoIndicacao('PEQUENO'), 'pequeno');
    expect(codigoIndicacao('   '), '');
  });

  test('só aceita código cadastrado e ativo', () async {
    final i = await Indicacoes.buscar('Carol Nutroeste');
    expect(i?.tipoNome, 'Zootecnista');
    expect(await Indicacoes.buscar('naoexiste'), isNull);
    expect(await Indicacoes.buscar('antigo'), isNull);
    expect(await Indicacoes.buscar('a/b'), isNull);
  });

  test('adesão guarda o código e o desconto, e conta por código', () async {
    final i = (await Indicacoes.buscar('carolnutroeste'))!;
    await Indicacoes.registrarAdesao('u1', 'a@b.com', i);
    await Indicacoes.registrarAdesao('u2', 'c@d.com', i);
    final d = (await banco.doc('usuarios/u1').get()).data()!;
    expect(d['indicacao'], 'carolnutroeste');
    expect(d['desconto'], descontoIndicacao);
    expect(await Indicacoes.adesoes('carolnutroeste'), 2);
    expect(await Indicacoes.adesoes('antigo'), 0);
  });

  test('não cria código repetido', () async {
    const novo = Indicacao(codigo: 'carolnutroeste', nome: 'Outra', tipo: 'lojista');
    expect(await Indicacoes.salvar(novo, novo: true), isFalse);
    expect(await Indicacoes.salvar(const Indicacao(codigo: 'pequeno', nome: 'Pequeno', tipo: 'lojista'), novo: true),
        isTrue);
    expect((await Indicacoes.todas()).map((i) => i.codigo), ['antigo', 'carolnutroeste', 'pequeno']);
  });
}
