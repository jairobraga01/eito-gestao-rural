import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/negocio.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compra: subtotal + comissão + nota + frete', () {
    final c = ContaCompra(cabecas: 10, subtotal: 30000, comissaoPct: 2, nota: 150, frete: 850);
    expect(c.comissao, 600);
    expect(c.total, 31600);
    expect(c.media, 3160);
  });

  test('venda por arroba: bruto menos descontos', () {
    final v = ContaVenda(
        cabecas: 2, porArroba: true, preco: 300, pesoTotal: 900, funruralPct: 1.5, fundepec: 10, frete: 40);
    expect(v.arrobas, 60);
    expect(v.bruto, 18000);
    expect(v.funrural, 270);
    expect(v.liquido, 18000 - 270 - 10 - 40);
  });

  test('venda por arroba com rendimento de carcaça', () {
    final v = ContaVenda(cabecas: 1, porArroba: true, preco: 300, pesoTotal: 540, rendimentoPct: 50);
    expect(v.arrobas, 18);
    expect(v.bruto, 5400);
  });

  test('venda por cabeça', () {
    final v = ContaVenda(cabecas: 3, porArroba: false, preco: 4000, outros: 120);
    expect(v.arrobas, isNull);
    expect(v.liquido, 11880);
  });

  group('lucro da venda', () {
    setUp(() async {
      Db.bancoTeste = FakeFirebaseFirestore();
      await Db.iniciar('teste');
    });
    tearDown(Db.encerrar);

    test('lucro: líquido menos compra e despesas do lote', () async {
      final lote = await Db.inserir('lotes', {'propriedade_id': Db.pid, 'nome': 'Recria'});
      await Db.registrarEntrada(
          {'tipo': 'Compra', 'data': '2026-01-10', 'valor_total': 6000.0}, ['A1', 'A2'], {'sexo': 'M', 'lote_id': lote});
      await Db.inserir('custos', {'propriedade_id': Db.pid, 'lote_id': lote, 'valor': 400.0, 'data': '2026-03-01'});
      final ids = [for (final a in Db.registros('animais')) a['id'] as int];
      await Db.registrarSaida({'tipo': 'Venda', 'data': '2026-08-12', 'valor_total': 8000.0}, ids);
      final s = Db.registros('saidas').single;
      final r = lucroDaVenda(s)!;
      expect(r.custo, closeTo(6400, 0.001));
      expect(r.lucro, closeTo(1600, 0.001));
      final g = resumoGado(2026);
      expect(g.cabecasCompradas, 2);
      expect(g.totalCompras, 6000);
      expect(g.cabecasVendidas, 2);
      expect(g.lucroVendas, closeTo(1600, 0.001));
    });

    test('despesas gerais divididas por cabeça-dia', () async {
      await Db.registrarEntrada({'tipo': 'Compra', 'data': '2026-01-01', 'valor_total': 2000.0}, ['B1'], {'sexo': 'M'});
      await Db.registrarEntrada({'tipo': 'Compra', 'data': '2026-03-02', 'valor_total': 2000.0}, ['B2'], {'sexo': 'M'});
      await Db.inserir('custos', {'propriedade_id': Db.pid, 'valor': 900.0, 'data': '2026-02-01'});
      // B1 fica 120 dias (01/01 a 01/05), B2 fica 60 dias (02/03 a 01/05): 2/3 e 1/3 da despesa.
      final c = custoPorAnimal(hoje: '2026-05-01');
      final b1 = Db.registros('animais').firstWhere((a) => a['brinco'] == 'B1')['id'] as int;
      final b2 = Db.registros('animais').firstWhere((a) => a['brinco'] == 'B2')['id'] as int;
      expect(c[b1], closeTo(2600, 0.001));
      expect(c[b2], closeTo(2300, 0.001));
    });

    test('venda a prazo cria parcelas e apaga as abertas', () async {
      await lancarParcelas(
          receita: true, origem: 'saida:9', total: 1000, parcelas: 3, primeiro: '2026-09-10', descricao: 'Venda');
      final cs = Db.registros('contas').where((c) => c['origem'] == 'saida:9').toList();
      expect(cs.length, 3);
      expect(cs.fold<double>(0, (s, c) => s + (c['valor'] as num)), closeTo(1000, 0.001));
      expect(cs.map((c) => c['vencimento']).toSet(), {'2026-09-10', '2026-10-10', '2026-11-10'});
      expect(cs.every((c) => c['pago'] == false && c['tipo'] == 'Receita'), isTrue);
      expect(await apagarParcelasAbertas('saida:9'), 3);
      expect(Db.registros('contas'), isEmpty);
    });
  });
}
