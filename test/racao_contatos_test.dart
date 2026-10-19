import 'package:eito_gestao_rural/dados/contatos.dart';
import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/estoque.dart';
import 'package:eito_gestao_rural/dados/proteinado.dart';
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

  test('bater ração tira os ingredientes e cria a ração pronta; o trato usa a pronta', () async {
    await carregarPlanilhaProteinado();
    await pumpEventQueue();
    final milho = insumos().firstWhere((i) => i['nome'] == 'Milho')['id'] as int;
    await entradaEstoque(milho, 500, data: '2026-10-01');
    final f = formulas().firstWhere((f) => f['nome'] == 'Fortaleza');
    final c = CalculoFormula(f);

    final preco = await baterRacao(f, data: '2026-10-10', kgBatidos: c.kgBatida);
    await pumpEventQueue();
    expect(saldo(milho), 360); // uma batida inteira, como em registrarBatida
    expect(preco, closeTo(c.precoKg!, 1e-9));
    final pronta = racaoPronta(f['id'])!;
    expect(saldo(pronta['id'] as int), closeTo(c.kgBatida, 1e-6));
    expect(precoKgInsumo(pronta)!, closeTo(c.precoKg!, 1e-3));

    // Segunda batida a outro preço: o quilo da pronta vira a média ponderada.
    await Db.atualizar('insumos', milho, {'preco_saco': 200});
    final f2 = Db.registro('formulas', f['id'])!;
    final preco2 = await baterRacao(f2, data: '2026-10-11', kgBatidos: c.kgBatida);
    await pumpEventQueue();
    expect(preco2! > preco!, isTrue);
    expect(precoKgInsumo(racaoPronta(f['id'])!)!, closeTo((preco + preco2) / 2, 1e-3));
    expect(saldo(racaoPronta(f['id'])!['id'] as int), closeTo(2 * c.kgBatida, 1e-6));
  });

  test('histórico do contato junta compras e vendas pelo nome', () async {
    final id = await Db.inserir('contatos', {'propriedade_id': pid, 'nome': 'João da Silva', 'tipo': 'Os dois'});
    await Db.inserir('entradas', {
      'propriedade_id': pid, 'tipo': 'Compra', 'origem': 'joão da silva ', 'quantidade': 10, 'valor_total': 20000, 'data': '2026-09-01',
    });
    await Db.inserir('saidas', {
      'propriedade_id': pid, 'tipo': 'Venda', 'destino': 'João da Silva', 'quantidade': 5, 'valor_total': 15000, 'data': '2026-10-05',
    });
    await Db.inserir('saidas', {
      'propriedade_id': pid, 'tipo': 'Venda', 'destino': 'Outro', 'quantidade': 3, 'valor_total': 9000, 'data': '2026-10-06',
    });
    await pumpEventQueue();
    final h = historicoDoContato(Db.registro('contatos', id)!);
    expect(h.cabecasCompradas, 10);
    expect(h.precoMedioCompra, 2000);
    expect(h.cabecasVendidas, 5);
    expect(h.precoMedioVenda, 3000);
    expect(h.ultimo, '2026-10-05');
    expect(contatosPara('Comprador').length, 1);
  });
}
