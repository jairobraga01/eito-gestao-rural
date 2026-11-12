import 'package:eito_gestao_rural/dados/confinamento.dart';
import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/estoque.dart';
import 'package:eito_gestao_rural/dados/relatorio_confinamento.dart';
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

  Future<(int, int, int)> montar({int animais = 10}) async {
    final lote = await Db.inserir('lotes', {'propriedade_id': pid, 'nome': 'Bois 1'});
    for (var i = 0; i < animais; i++) {
      await Db.inserir('animais', {'propriedade_id': pid, 'brinco': '$i', 'sexo': 'M', 'status': 'Ativo', 'lote_id': lote});
    }
    // Ração a R$ 1,00/kg com 88% de MS.
    final racao = await Db.inserir('insumos', {'propriedade_id': pid, 'nome': 'Ração', 'kg_saco': 1, 'preco_saco': 1.0});
    await entradaEstoque(racao, 10000, data: '2026-10-01');
    final ciclo = await Db.inserir('confinamentos', {
      'propriedade_id': pid,
      'nome': 'Curral 1',
      'lote_id': lote,
      'data_entrada': '2026-10-01',
      'cabecas': animais,
      'peso_entrada': 400.0,
      'valor_compra': 3000.0,
      'insumo_id': racao,
      'ms': 88,
      'kg_cab_dia': 10.0,
      'gmd_previsto': 1.5,
      'meta_peso': 550.0,
      'rend_entrada': 50,
      'rend_saida': 54,
      'custo_fixo_dia': 2.0,
      'arroba_venda': 300.0,
    });
    await pumpEventQueue();
    return (lote, racao, ciclo);
  }

  Ciclo ciclo(int id) => Ciclo(Db.registro('confinamentos', id)!);

  test('nota da leitura ajusta o trato do último dia', () async {
    final (_, _, id) = await montar();
    expect(ciclo(id).trato('2026-10-01', null), 100);
    await registrarCocho(ciclo(id), data: '2026-10-01', nota: null, kgPrevisto: 100, kgFornecido: 110);
    await pumpEventQueue();
    // 11 kg/cab ontem; nota 0 (lambido) = +10%; nota 4 = -10%; nota 2 mantém.
    expect(ciclo(id).trato('2026-10-02', 0), closeTo(121, 1e-9));
    expect(ciclo(id).trato('2026-10-02', 4), closeTo(99, 1e-9));
    expect(ciclo(id).trato('2026-10-02', 2), closeTo(110, 1e-9));
  });

  test('trato dá baixa no estoque e lança o custo; apagar a leitura devolve', () async {
    final (lote, racao, id) = await montar();
    final l = await registrarCocho(ciclo(id), data: '2026-10-02', nota: 1, kgPrevisto: 105, kgFornecido: 100);
    await pumpEventQueue();
    expect(saldo(racao), 9900);
    final custo = Db.registros('custos').single;
    expect(custo['valor'], 100);
    expect(custo['lote_id'], lote);

    // Lançar de novo no mesmo dia troca o lançamento.
    await registrarCocho(ciclo(id), data: '2026-10-02', nota: 2, kgPrevisto: 100, kgFornecido: 80);
    await pumpEventQueue();
    expect(ciclo(id).leituras.length, 1);
    expect(saldo(racao), 9920);
    expect(Db.registros('custos').length, 1);
    expect(Db.registro('cocho', l), isNull);

    await Db.excluir('cocho', ciclo(id).leituras.single['id'] as int);
    await pumpEventQueue();
    expect(saldo(racao), 10000);
    expect(Db.registros('custos'), isEmpty);
  });

  test('indicadores, custo da arroba, equilíbrio e projeção de saída', () async {
    final (_, _, id) = await montar();
    for (var d = 1; d <= 10; d++) {
      await registrarCocho(ciclo(id), data: '2026-10-${d.toString().padLeft(2, '0')}', kgPrevisto: 100, kgFornecido: 100);
    }
    await pumpEventQueue();
    final c = ciclo(id);
    const hoje = '2026-10-11';
    expect(c.diasDeCocho(hoje), 10);
    expect(c.consumoMN, closeTo(10, 1e-9));
    expect(c.consumoMS, closeTo(8.8, 1e-9));
    // Sem pesagem: GMD previsto de 1,5 → 415 kg hoje.
    expect(c.gmdReal(hoje), isFalse);
    expect(c.pesoAtual(hoje), closeTo(415, 1e-9));
    expect(c.consumoPV(hoje), closeTo(8.8 / 407.5 * 100, 1e-9));
    expect(c.conversao(hoje), closeTo(8.8 / 1.5, 1e-9));
    // Diária: R$ 10 de ração + R$ 2 operacional.
    expect(c.diaria, closeTo(12, 1e-9));

    final r = c.resultado(hoje);
    expect(r.custoCab, closeTo(120, 1e-9));
    expect(r.arrobasProduzidas, closeTo((415 * 0.54 - 400 * 0.5) / 15, 1e-9));

    // Meta de 550 kg: faltam 135 kg a 1,5 kg/dia = 90 dias → 100 dias de cocho.
    expect(c.diasPrevistos(hoje), 100);
    expect(c.saidaPrevista(hoje), '2027-01-09');
    final s = c.resultado(hoje, naSaida: true);
    expect(s.peso, closeTo(550, 1e-9));
    expect(s.arrobasSaida, closeTo(19.8, 1e-9));
    expect(s.custoCab, closeTo(1200, 1e-9));
    expect(s.equilibrio, closeTo(4200 / 19.8, 1e-9));
    expect(s.margem, closeTo(19.8 * 300 - 4200, 1e-9));
    expect(htmlRelatorioConfinamento(c, hoje), contains('Curral 1'));
  });

  test('pesagem do lote dá o GMD real e morte sai das cabeças', () async {
    final (_, _, id) = await montar(animais: 2);
    final animais = Db.registros('animais');
    for (final a in animais) {
      await Db.inserir('pesagens', {'animal_id': a['id'], 'data': '2026-10-21', 'peso': 440.0});
    }
    await pumpEventQueue();
    final c = ciclo(id);
    expect(c.gmdReal('2026-10-21'), isTrue);
    expect(c.gmd('2026-10-21'), closeTo(2, 1e-9));
    expect(c.pesoAtual('2026-10-31'), closeTo(460, 1e-9));

    await Db.registrarSaida({'tipo': 'Morte', 'data': '2026-10-25'}, [animais.first['id'] as int]);
    await pumpEventQueue();
    expect(ciclo(id).cabecas, 1);
    expect(ciclo(id).mortes, 1);
  });

  test('encerrar guarda o resultado e apagar o ciclo mantém os custos', () async {
    final (_, _, id) = await montar();
    await registrarCocho(ciclo(id), data: '2026-10-01', kgPrevisto: 100, kgFornecido: 100);
    await pumpEventQueue();
    await encerrarCiclo(ciclo(id), data: '2026-12-30', pesoSaida: 580, rendReal: 55, arroba: 310);
    await pumpEventQueue();
    final c = ciclo(id);
    expect(c.aberto, isFalse);
    expect(c.cabecas, 10);
    expect(c.diasDeCocho('2027-02-01'), 90);
    expect(c.gmd('2027-02-01'), closeTo(2, 1e-9));
    expect(c.resultado('2027-02-01').arrobasSaida, closeTo(580 * 0.55 / 15, 1e-9));
    expect(ciclos(soAbertos: true), isEmpty);

    await Db.excluir('confinamentos', id);
    await pumpEventQueue();
    expect(Db.registros('cocho'), isEmpty);
    expect(Db.registros('custos').length, 1);
  });

  test('texto do trato para o WhatsApp', () async {
    final (_, _, id) = await montar();
    final t = textoTratoWhats([(ciclo(id), 105)], '2026-10-02', fazenda: 'Fazenda');
    expect(t, contains('Curral 1: 105 kg de Ração (10 cab.)'));
    expect(t, contains('Total: 105 kg'));
  });
}
