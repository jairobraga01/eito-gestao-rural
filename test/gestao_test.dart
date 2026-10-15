import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/gestao.dart';
import 'package:eito_gestao_rural/dados/manejo.dart';
import 'package:eito_gestao_rural/dados/resumo_periodo.dart';
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

  Future<int> animal(String brinco,
          {String sexo = 'F', int? mae, String? nascimento, int? lote, String? pai}) =>
      Db.inserir('animais', {
        'propriedade_id': pid,
        'brinco': brinco,
        'sexo': sexo,
        'status': 'Ativo',
        'mae_id': mae,
        'nascimento': nascimento,
        'lote_id': lote,
        'pai': pai,
      });

  test('conta do lote: compra, custos, sêmen, venda, estoque e custo por arroba', () async {
    final lote = await Db.inserir('lotes', {'propriedade_id': pid, 'nome': 'Recria'});
    await Db.salvarConfig('abate', {'alvo': 540, 'rendimento': 50, 'arroba': 300});
    final e = await Db.registrarEntrada(
        {'tipo': 'Compra', 'data': '2026-01-01', 'valor_total': 6000, 'peso_total': 600}, ['1', '2'], {'sexo': 'M', 'lote_id': lote});
    await pumpEventQueue();
    final ids = [for (final a in Db.registros('animais')) if (a['entrada_id'] == e) a['id'] as int]..sort();
    await Db.registrarPesagem(ids[0], 450, data: '2026-07-01'); // ganhou 150 kg = 5 @
    await Db.registrarPesagem(ids[1], 390, data: '2026-07-01'); // ganhou 90 kg = 3 @
    await Db.inserir('custos', {'propriedade_id': pid, 'lote_id': lote, 'categoria': 'Ração e sal', 'valor': 800, 'data': '2026-03-01'});
    await Db.inserir('custos', {'propriedade_id': pid, 'categoria': 'Outros', 'valor': 100, 'data': '2026-03-01'});
    await Db.registrarSaida({'tipo': 'Venda', 'data': '2026-07-02', 'valor_total': 4500}, [ids[1]]);

    final contas = contasPorLote();
    final c = contas.firstWhere((x) => x.nome == 'Recria');
    expect(c.cabecas, 2);
    expect(c.aquisicao, 6000);
    expect(c.custos, 800);
    expect(c.vendas, 4500);
    expect(c.vendidos, 1);
    expect(c.estoque, 450 * 0.5 / 15 * 300); // 4500
    expect(c.arrobasProduzidas, closeTo(8, 1e-9));
    expect(c.custoPorArroba, 100);
    expect(c.margem, 4500 + 4500 - 6800);
    expect(contas.last.loteId, isNull);
    expect(contas.last.custos, 100);
  });

  group('Calendário sanitário', () {
    test('brucelose pede só fêmeas de 3 a 8 meses ainda sem vacina', () async {
      await animal('1', nascimento: '2026-05-01'); // 5 meses
      await animal('2', nascimento: '2025-01-01'); // velha
      await animal('3', sexo: 'M', nascimento: '2026-05-01');
      final v = await animal('4', nascimento: '2026-04-01');
      await Db.lancarSanidade([v], {'data': '2026-09-01', 'tipo': 'Vacinação', 'produto': 'Brucelose'});

      final p = pendenciasCalendario('2026-10-15').firstWhere((x) => x.$1.id == 'brucelose');
      expect(p.$2, ['1']);
    });

    test('clostridiose pede o reforço 30 dias depois da primeira dose', () async {
      final a = await animal('5', sexo: 'M', nascimento: '2026-04-01');
      await Db.lancarSanidade([a], {'data': '2026-09-01', 'tipo': 'Vacinação', 'produto': 'Clostridiose'});
      String? item(String hoje) =>
          pendenciasCalendario(hoje).where((x) => x.$1.id == 'clostridiose').firstOrNull?.$2.single;
      expect(item('2026-09-20'), isNull);
      expect(item('2026-10-15'), '5');
    });

    test('vermífugo só em maio, julho e setembro; itens desligados não aparecem', () async {
      await animal('6', sexo: 'M');
      expect(pendenciasCalendario('2026-07-10').map((x) => x.$1.id), contains('vermifugo'));
      expect(pendenciasCalendario('2026-08-10').map((x) => x.$1.id), isNot(contains('vermifugo')));
      expect(pendenciasCalendario('2026-05-10').map((x) => x.$1.id), isNot(contains('aftosa')));
      await ligarCalendario('vermifugo', false);
      expect(pendenciasCalendario('2026-07-10').map((x) => x.$1.id), isNot(contains('vermifugo')));
      await ligarCalendario('aftosa', true);
      expect(pendenciasCalendario('2026-05-10').map((x) => x.$1.id), contains('aftosa'));
    });

    test('entra na fila do dia', () async {
      await animal('7', sexo: 'M');
      expect(filaDoDia('2026-07-10').map((i) => i.chave), contains('cal_vermifugo_2026-07'));
    });
  });

  test('ranking põe na frente a vaca que emprenha mais e pare mais seguido', () async {
    final boa = await animal('10');
    final ruim = await animal('11');
    for (final (vaca, partos) in [
      (boa, ['2024-01-01', '2024-12-27']),
      (ruim, ['2024-01-01', '2025-06-25']),
    ]) {
      for (final p in partos) {
        await Db.inserir('reproducoes', {'femea_id': vaca, 'data': '2023-03-01', 'diagnostico': 'Prenhe', 'parto_data': p});
      }
    }
    await Db.inserir('reproducoes', {'femea_id': ruim, 'data': '2025-08-01', 'diagnostico': 'Vazia'});

    final r = rankingMatrizes();
    expect(r.map((m) => m.vaca['brinco']), ['10', '11']);
    expect(r.first.iep, 361);
    expect(r.first.taxaPrenhez, 1);
    expect(r.last.taxaPrenhez, closeTo(2 / 3, 1e-9));
  });

  test('avisa consanguinidade com pai, avô e bisavô maternos', () async {
    final bisavo = await animal('20', pai: 'Faraó');
    final avo = await animal('21', mae: bisavo, pai: 'Bandido');
    final mae = await animal('22', mae: avo, pai: 'Rei');
    final vaca = await animal('23', mae: mae, pai: 'Imperador');

    expect(alertaConsanguinidade(vaca, 'imperador '), contains('pai'));
    expect(alertaConsanguinidade(vaca, 'Rei'), contains('avô materno'));
    expect(alertaConsanguinidade(vaca, 'Bandido'), contains('bisavô materno'));
    expect(alertaConsanguinidade(vaca, 'Faraó'), isNull); // 4 gerações: fora
    expect(alertaConsanguinidade(vaca, 'Outro'), isNull);
  });

  test('chuva por mês, no período e no resumo da semana', () async {
    await Db.inserir('chuvas', {'propriedade_id': pid, 'data': '2026-10-10', 'mm': 12.5});
    await Db.inserir('chuvas', {'propriedade_id': pid, 'data': '2026-10-14', 'mm': 20});
    await Db.inserir('chuvas', {'propriedade_id': pid, 'data': '2026-09-30', 'mm': 5});

    expect(chuvaPorMes(2026)[9], 32.5);
    expect(chuvaPorMes(2026)[8], 5);
    expect(ResumoPeriodo.mes(2026, 10).chuvaMm, 32.5);

    final texto = resumoSemanal('2026-10-15');
    expect(texto, contains('Resumo de 09/10 a 15/10'));
    expect(texto, contains('Chuva: 32,5 mm'));
    expect(texto, contains('Rebanho: 0 cabeças'));
  });
}
