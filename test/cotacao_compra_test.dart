import 'package:eito_gestao_rural/dados/cotacao_compra.dart';
import 'package:flutter_test/flutter_test.dart';

PedidoCotacao _p(String forn, List<double?> precos, {double frete = 0}) => PedidoCotacao('c$forn', {
      'tipo': tipoMedicamentos,
      'grupo': 'g1',
      'fornecedor': {'nome': forn},
      'status': 'respondida',
      'itens': [
        {'nome': 'Aftosa', 'unidade': 'dose', 'qtd': 100},
        {'nome': 'Ivermectina', 'unidade': 'ml', 'qtd': 500},
      ],
      'precos': precos,
      'frete': frete,
    });

void main() {
  test('preço final soma preço × quantidade e o frete', () {
    expect(_p('A', [2, 0.5], frete: 30).total, 100 * 2 + 500 * 0.5 + 30);
    expect(_p('B', [1.8, null]).cotados, 1);
  });

  test('melhor fornecedor: quem cotou mais itens, pelo menor preço final', () {
    final g = GrupoCotacao([_p('A', [2, 0.5], frete: 30), _p('B', [1.5, null]), _p('C', [2, 0.4])]);
    expect(g.melhor!.fornecedor, 'C');
    expect(g.menores, [1.5, 0.4]);
  });

  test('telefone vira número do WhatsApp com 55', () {
    expect(telefoneWhats('(62) 99999-1234'), '5562999991234');
    expect(telefoneWhats('+55 62 99999-1234'), '5562999991234');
    expect(telefoneWhats(''), isNull);
  });

  test('código do link é longo e sorteado', () {
    final a = CotacoesCompra.novoCodigo(), b = CotacoesCompra.novoCodigo();
    expect(a.length, 24);
    expect(a, isNot(b));
  });
}
