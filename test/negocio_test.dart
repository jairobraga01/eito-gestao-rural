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

    test('líquido menos o custo médio do lote', () async {
      final lote = await Db.inserir('lotes', {'propriedade_id': Db.pid, 'nome': 'Recria'});
      await Db.registrarEntrada(
          {'tipo': 'Compra', 'data': '2026-01-10', 'valor_total': 6000.0}, ['A1', 'A2'], {'sexo': 'M', 'lote_id': lote});
      await Db.inserir('custos', {'propriedade_id': Db.pid, 'lote_id': lote, 'valor': 400.0, 'data': '2026-03-01'});
      final a1 = Db.registros('animais').firstWhere((a) => a['brinco'] == 'A1');
      await Db.registrarSaida({'tipo': 'Venda', 'data': '2026-08-12', 'valor_total': 5000.0}, [a1['id'] as int]);
      final s = Db.registros('saidas').single;
      final r = lucroDaVenda(s)!;
      expect(r.custo, 3200); // (6000 + 400) ÷ 2
      expect(r.lucro, 1800);
      final g = resumoGado(2026);
      expect(g.cabecasCompradas, 2);
      expect(g.totalCompras, 6000);
      expect(g.cabecasVendidas, 1);
      expect(g.lucroVendas, 1800);
    });
  });
}
