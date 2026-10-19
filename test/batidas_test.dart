import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/estoque.dart';
import 'package:eito_gestao_rural/dados/proteinado.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    Db.bancoTeste = FakeFirebaseFirestore();
    await Db.iniciar('teste');
  });

  tearDown(Db.encerrar);

  test('preço lançado vira o preço do insumo e fica no histórico', () async {
    final milho = await Db.inserir('insumos', {'propriedade_id': Db.pid, 'nome': 'Milho', 'preco_saco': 80, 'kg_saco': 50});
    await lancarPrecoInsumo(milho, data: '2026-09-01', precoEmbalagem: 80, kgEmbalagem: 50);
    await lancarPrecoInsumo(milho, data: '2026-10-01', precoEmbalagem: 90, kgEmbalagem: 50);
    await pumpEventQueue();
    // Um preço mais antigo lançado depois não troca o preço atual.
    await lancarPrecoInsumo(milho, data: '2026-08-01', precoEmbalagem: 70, kgEmbalagem: 50);
    await pumpEventQueue();
    final h = historicoPrecos(milho);
    expect(h.map((p) => p['data']), ['2026-10-01', '2026-09-01', '2026-08-01']);
    expect(precoKgInsumo(Db.registro('insumos', milho)), closeTo(1.8, 1e-9));
    expect(variacaoPct(1.6, 1.8), closeTo(12.5, 1e-9));
  });

  test('gerar batida grava o histórico com os preços do dia e apagar devolve o estoque', () async {
    final milho = await Db.inserir('insumos', {'propriedade_id': Db.pid, 'nome': 'Milho', 'preco_saco': 100, 'kg_saco': 50});
    final soja = await Db.inserir('insumos', {'propriedade_id': Db.pid, 'nome': 'Soja', 'preco_saco': 120, 'kg_saco': 60});
    final f = await Db.inserir('formulas', {
      'propriedade_id': Db.pid,
      'nome': 'Teste',
      'tipo': 'Baixo consumo',
      'itens': [
        {'insumo_id': milho, 'kg': 100},
        {'insumo_id': soja, 'kg': 50},
      ],
    });
    await entradaEstoque(milho, 1000, data: '2026-10-01');
    await entradaEstoque(soja, 500, data: '2026-10-01');
    await pumpEventQueue();

    await registrarBatida(Db.registro('formulas', f)!, data: '2026-10-05', batidas: 2);
    await pumpEventQueue();
    await Db.atualizar('insumos', milho, {'preco_saco': 150});
    await registrarBatida(Db.registro('formulas', f)!, data: '2026-10-20');
    await pumpEventQueue();

    final h = batidasFeitas(formulaId: f);
    expect(h.length, 2);
    // Mais recente primeiro: milho a 3,00/kg e soja a 2,00/kg em 150 kg = 400.
    expect(h.first['custo_total'], 400);
    expect(h.last['custo_total'], 2 * (100 * 2 + 50 * 2));
    expect(h.last['custo_kg'], closeTo(2.0, 1e-9));
    expect(variacaoPct((h.last['custo_kg'] as num).toDouble(), (h.first['custo_kg'] as num).toDouble()), closeTo(33.33, 0.01));
    expect(saldo(milho), 1000 - 200 - 100);

    // Trato do cocho não entra no histórico de batidas.
    await registrarBatida(Db.registro('formulas', f)!, data: '2026-10-21', descricao: 'Trato');
    await pumpEventQueue();
    expect(batidasFeitas(formulaId: f).length, 2);

    await excluirBatida(h.first);
    await pumpEventQueue();
    expect(batidasFeitas(formulaId: f).length, 1);
    expect(saldo(milho), 1000 - 200 - 100); // a do trato continua baixando 100
  });
}
