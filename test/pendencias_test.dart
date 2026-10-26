import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/estoque.dart';
import 'package:eito_gestao_rural/dados/nota_compra.dart';
import 'package:eito_gestao_rural/dados/planos.dart';
import 'package:eito_gestao_rural/dados/proteinado.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    Db.bancoTeste = FakeFirebaseFirestore();
    await Db.iniciar('teste');
  });

  tearDown(Db.encerrar);

  test('nota: "FARELO DE MILHO" não soma no "MILHO" e a unidade precisa bater', () async {
    await Db.inserir('insumos', {'propriedade_id': Db.pid, 'nome': 'MILHO', 'unidade': 'kg', 'kg_saco': 50});
    await Db.inserir('insumos', {'propriedade_id': Db.pid, 'nome': 'Vacina aftosa', 'unidade': 'dose', 'kg_saco': 1});
    await pumpEventQueue();
    expect(insumoParecido('FARELO DE MILHO', unidade: 'kg'), isNull);
    expect(insumoParecido('MILHO MOIDO', unidade: 'kg')?['nome'], 'MILHO');
    expect(insumoParecido('VACINA AFTOSA 50ML', unidade: 'ml'), isNull);
    expect(insumoParecido('Vacina aftosa', unidade: 'dose')?['nome'], 'Vacina aftosa');
  });

  test('nota: saco sem o peso no nome pede o tamanho antes de lançar', () async {
    final n = lerNotaTexto('SAL MINERAL FOSBOVI 10 SC 150,00 1.500,00');
    expect(n.itens.single.embalagem, 0);
    expect(() => lancarNota(n, data: '2026-10-20'), throwsA(isA<String>()));
  });

  test('batida usa o preço do insumo na data escolhida', () async {
    final milho = await Db.inserir('insumos', {'propriedade_id': Db.pid, 'nome': 'Milho', 'preco_saco': 100, 'kg_saco': 50});
    await lancarPrecoInsumo(milho, data: '2026-09-01', precoEmbalagem: 50, kgEmbalagem: 50);
    await lancarPrecoInsumo(milho, data: '2026-10-01', precoEmbalagem: 100, kgEmbalagem: 50);
    await pumpEventQueue();
    final ins = Db.registro('insumos', milho);
    expect(precoKgInsumoNaData(ins, '2026-09-15'), 1);
    expect(precoKgInsumoNaData(ins, '2026-10-20'), 2);
    expect(precoKgInsumoNaData(ins, '2026-01-01'), 1); // antes de tudo: o mais antigo
    final f = {
      'id': 1,
      'nome': 'F',
      'itens': [
        {'insumo_id': milho, 'kg': 100},
      ],
    };
    expect(CalculoFormula(f, data: '2026-09-15').custoBatida, 100);
    expect(CalculoFormula(f).custoBatida, 200);
    await entradaEstoque(milho, 1000, data: '2026-09-01');
    await registrarBatida(f, data: '2026-09-15');
    await pumpEventQueue();
    expect(batidasFeitas().first['custo_total'], 100);
  });

  test('teste grátis vence 30 dias depois do cadastro e passa a valer como Simples', () {
    final agora = DateTime(2026, 10, 26);
    final novo = {'plano': 'Teste', 'criado_em': DateTime(2026, 10, 10), 'teste_ate': DateTime(2026, 10, 24)};
    expect(testeVencido(novo, agora), isFalse); // 14 dias do painel, mas o teste agora tem 30
    expect(planoEfetivo(novo, agora), 'Teste');
    final velho = {'plano': 'Teste', 'criado_em': DateTime(2026, 8, 1), 'teste_ate': DateTime(2026, 8, 15)};
    expect(planoEfetivo(velho, agora), 'Simples');
    expect(planoEfetivo({'plano': 'Plus'}, agora), 'Plus');
    expect(PlanoEito.de('media'), PlanoEito.simples); // nome errado não libera tudo
    expect(PlanoEito.de(null), PlanoEito.livre);
    expect(PlanoEito.de('Cortesia'), PlanoEito.livre);
  });

  test('cada papel só grava o que as regras deixam e o app avisa', () async {
    expect(Db.podeGravar('saidas'), isTrue); // dono
    Db.papel.value = 'peao';
    expect(Db.podeGravar('saidas'), isFalse);
    expect(Db.podeGravar('protocolos'), isTrue);
    Db.papel.value = 'zootecnista';
    expect(Db.podeGravar('animais'), isTrue);
    expect(Db.podeGravar('custos'), isTrue);
    expect(Db.podeGravar('propriedades'), isFalse);
    Db.papel.value = 'peao';
    await Db.inserir('saidas', {'tipo': 'Venda', 'data': '2026-10-20'});
    expect(Db.registros('saidas'), isEmpty);
    expect(Db.recusado.value, contains('vendas'));
  });
}
