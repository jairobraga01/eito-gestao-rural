import 'dart:convert';

import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/guarai.dart';
import 'package:eito_gestao_rural/dados/painel_gado.dart';
import 'package:eito_gestao_rural/dados/relatorio_html.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

final _backup = jsonEncode({
  'app': 'gado-guarai',
  'versao': 1,
  'config': {'exercicio': '2026-07', 'comVend': 2, 'comComp': 2, 'saldoAnterior': 3},
  'compras': [
    {
      'id': 'c01', 'data': '2026-03-27', 'comComp': 2, 'comVend': 2, 'nota': 150, 'frete': 910, //
      'lotes': [
        {'qtd': 4, 'valor': 3000, 'data': ''},
        {'qtd': 1, 'valor': 2420, 'data': ''},
      ],
    },
  ],
  'vendas': [
    {'id': 'v01', 'data': '2026-08-12', 'qtd': 2, 'modo': 'cabeca', 'valorCabeca': 3350, 'outros': 154, 'destino': 'Leilão'},
  ],
  'saidas': [],
  'despesas': [
    {'id': 'd01', 'mes': '2026-07', 'qtd': 228, 'unitario': 60, 'valor': 13680, 'tipo': 'Aluguel', 'descricao': 'Pasto'},
  ],
  'pesagens': [],
});

void main() {
  setUp(() async {
    Db.bancoTeste = FakeFirebaseFirestore();
    await Db.iniciar('teste');
  });
  tearDown(Db.encerrar);

  test('recusa arquivo que não é do Gado Guaraí', () {
    expect(() => lerBackupGuarai('{"app":"outro"}'), throwsFormatException);
  });

  test('importa compras, saldo, vendas e despesas sem duplicar', () async {
    final r = await importarGuarai(lerBackupGuarai(_backup));
    expect(r.compras, 1);
    expect(r.animais, 8); // 5 comprados + 3 do saldo anterior
    expect(r.vendas, 1);
    expect(r.despesas, 1);

    final e = Db.registros('entradas').firstWhere((x) => x['tipo'] == 'Compra');
    // subtotal 14.420 + 2% (288,40) + nota 150 + frete 910
    expect(e['valor_total'], closeTo(15768.4, 0.001));
    final v = Db.registros('saidas').single;
    expect(v['valor_total'], closeTo(6546, 0.001));
    expect(Db.registros('animais').where((a) => a['status'] == 'Vendido').length, 2);
    final c = Db.registros('custos').single;
    expect(c['categoria'], 'Pastagem e arrendamento');
    expect(c['data'], '2026-07-15');

    final deNovo = await importarGuarai(lerBackupGuarai(_backup));
    expect(deNovo.compras + deNovo.vendas + deNovo.despesas, 0);
    expect(deNovo.jaExistiam, 4);
    expect(Db.registros('animais').length, 8);

    final p = PainelGado(hoje: '2026-10-15');
    expect(p.noPasto, 6);
    expect(p.comprado, 5);
    expect(p.outrasEntradas, 3);
    expect(p.caixa, closeTo(6546 - 15768.4 - 13680, 0.001));
    expect(p.vendas.single.custo, greaterThan(0));
    expect(mesInicioExercicio(), 7);
    expect(exercicioAtual('2026-10-15'), '2026-07');
    expect(p.despesasExercicio('2026-07')['Pastagem e arrendamento']![0], 13680);

    final html = htmlRelatorioFinanceiro(2026, '2026-10-15');
    expect(html, contains('Relatório financeiro 2026'));
    expect(html, contains('Compra e venda de gado'));
  });
}
