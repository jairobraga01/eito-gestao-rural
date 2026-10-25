import 'dart:convert';

import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/estoque.dart';
import 'package:eito_gestao_rural/dados/proteinado.dart';
import 'package:eito_gestao_rural/dados/voz.dart';
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

  Future<int> animal(String brinco, {String sexo = 'M', int? lote}) => Db.inserir(
      'animais', {'propriedade_id': pid, 'brinco': brinco, 'sexo': sexo, 'status': 'Ativo', 'lote_id': lote});

  test('vacinação com o nome do insumo dá baixa e o estorno volta', () async {
    final vac = await Db.inserir('insumos', {'propriedade_id': pid, 'nome': 'Aftosa', 'categoria': 'Vacina', 'dose_animal': 2});
    await entradaEstoque(vac, 50, data: '2026-10-01', validade: '2026-10-20');
    final ids = [await animal('1'), await animal('2'), await animal('3')];
    final g = await Db.lancarSanidade(ids, {'data': '2026-10-10', 'tipo': 'Vacinação', 'produto': 'aftosa '});
    await pumpEventQueue();
    expect(saldo(vac), 44);
    expect(unidadeInsumo(Db.registro('insumos', vac)!), 'dose');
    expect(alertasEstoque('2026-10-15').map((a) => a.texto), ['Vence em 5 dia(s)']);

    await Db.excluirGrupoSanidade(g);
    await pumpEventQueue();
    expect(saldo(vac), 50);

    await Db.atualizar('insumos', vac, {'estoque_min': 60});
    await ajustarSaldo(vac, 0, data: '2026-10-15');
    await pumpEventQueue();
    expect(saldo(vac), 0);
    expect(alertasEstoque('2026-10-15').first.texto, 'Sem estoque');
  });

  test('batida de proteinado tira os insumos e apagar o custo devolve', () async {
    await carregarPlanilhaProteinado();
    await pumpEventQueue();
    final milho = insumos().firstWhere((i) => i['nome'] == 'Milho')['id'] as int;
    await entradaEstoque(milho, 500, data: '2026-10-01');
    final f = formulas().firstWhere((f) => f['nome'] == 'Fortaleza');
    final custo = await registrarBatida(f, data: '2026-10-10');
    await pumpEventQueue();
    expect(saldo(milho), 360);
    expect(consumoDiario(milho, '2026-10-15'), closeTo(140 / 30, 1e-9));

    await Db.excluir('custos', custo);
    await pumpEventQueue();
    expect(saldo(milho), 500);
  });

  test('dieta do cocho: consumo do mês, trato e dias de estoque', () async {
    final lote = await Db.inserir('lotes', {'propriedade_id': pid, 'nome': 'Recria'});
    for (var i = 0; i < 10; i++) {
      await animal('$i', lote: lote);
    }
    final sal = await Db.inserir('insumos',
        {'propriedade_id': pid, 'nome': 'Sal mineral', 'categoria': 'Sal mineral', 'preco_saco': 150, 'kg_saco': 30});
    await entradaEstoque(sal, 60, data: '2026-10-01');
    final pasto = await Db.inserir('piquetes', {'propriedade_id': pid, 'nome': 'Pasto 1'});
    await Db.moverParaPiquete(Db.registros('animais'), pasto, '2026-10-01');
    await Db.inserir('dietas', {'propriedade_id': pid, 'piquete_id': pasto, 'insumo_id': sal, 'kg_cab_dia': 0.1});
    await pumpEventQueue();

    final d = dietas().single;
    expect(d.local, 'Pasto 1');
    expect(d.cabecas, 10);
    expect(d.kgDia, closeTo(1, 1e-9));
    expect(d.custoMes, closeTo(150, 1e-9)); // 30 kg × R$ 5
    expect(d.diasDeEstoque, closeTo(60, 1e-9));

    await lancarTrato(d, data: '2026-10-10', dias: 5);
    await pumpEventQueue();
    expect(saldo(sal), closeTo(55, 1e-9));
    final c = Db.registros('custos').single;
    expect(c['valor'], 25);
    expect(c['lote_id'], lote);
  });

  test('vender ou esperar compara ganho de peso com o custo diário', () async {
    final lote = await Db.inserir('lotes', {'propriedade_id': pid, 'nome': 'Engorda'});
    final a = await animal('1', lote: lote);
    await Db.registrarPesagem(a, 400, data: '2026-01-01');
    await Db.registrarPesagem(a, 500, data: '2026-04-11'); // GMD 1
    await Db.salvarConfig('abate', {'rendimento': 50, 'arroba': 300});

    final l = venderOuEsperar(custoFixoDia: 5).single;
    expect(l.valorHoje, 5000);
    final c30 = l.cenarios.first;
    expect(c30.peso, 530);
    expect(c30.ganho, closeTo(300 - 150, 1e-9));
    expect(c30.arrobaEmpate, closeTo(5150 * 15 / 265, 1e-9));
    expect(l.melhor, 90);

    expect(venderOuEsperar(custoFixoDia: 20).single.melhor, 0);
  });

  group('Voz', () {
    test('entende as frases do curral', () {
      String? d(String f) => interpretarVoz(f)?.descricao;
      expect(d('Brinco 123 peso 450'), 'Brinco 123 · peso 450 kg');
      expect(d('brinco cento e vinte e três pesou quatrocentos e cinquenta quilos'), 'Brinco 123 · peso 450 kg');
      expect(d('Brinco 45 vacina aftosa'), 'Brinco 45 · vacinação: Aftosa');
      expect(d('brinco 45 vermífugo ivermectina'), 'Brinco 45 · antiparasitário: Ivermectina');
      expect(d('vaca 12 prenhe'), 'Brinco 12 · diagnóstico: Prenhe');
      expect(d('brinco 12 vazia'), 'Brinco 12 · diagnóstico: Vazia');
      expect(d('vaca 12 leite 18 vírgula 5 litros'), 'Brinco 12 · leite 18,5 L');
      expect(d('chuva 25 milímetros'), 'Chuva 25 mm');
      expect(d('bom dia'), isNull);
    });

    test('brinco falado dígito a dígito, mil no meio e vírgula digitada', () {
      String? d(String f) => interpretarVoz(f)?.descricao;
      expect(d('brinco um dois três peso 300'), 'Brinco 123 · peso 300 kg');
      expect(d('brinco 1 2 3 peso 300'), 'Brinco 123 · peso 300 kg');
      expect(d('brinco 45 peso mil cento e vinte'), 'Brinco 45 · peso 1120 kg');
      expect(d('brinco 45, peso 450'), 'Brinco 45 · peso 450 kg');
      expect(d('brinco número 45 peso 450'), 'Brinco 45 · peso 450 kg');
      expect(d('brinco cento e vinte e três pesou quatrocentos e cinquenta quilos'), 'Brinco 123 · peso 450 kg');
    });

    test('voz para os outros lançamentos', () {
      String? d(String f, {List<String> insumos = const []}) => interpretarVoz(f, insumos: insumos)?.descricao;
      expect(d('vaca 12 inseminada touro bravo'), 'Brinco 12 · inseminação · touro Bravo');
      expect(d('vaca 12 monta'), 'Brinco 12 · monta natural');
      expect(d('vaca 12 pariu macho brinco 300'), 'Brinco 12 · pariu macho · cria 300');
      expect(d('brinco 45 morreu picada de cobra'), 'Brinco 45 · morte: Picada cobra');
      expect(d('brinco 45 escore 3 e meio'), 'Brinco 45 · escore 3,5');
      expect(d('brinco 45 piquete 3'), 'Brinco 45 · para o piquete 3');
      expect(d('despesa 350 reais diesel'), 'Despesa R\$ 350 · Diesel (Combustível e máquinas)');
      expect(d('entrada 20 sal mineral', insumos: ['Sal mineral']), 'Entrada no estoque: 20 Sal mineral');
    });

    test('voz grava inseminação, parto, escore, piquete, morte e despesa', () async {
      final v = await animal('12', sexo: 'F');
      final b = await animal('45');
      final pq = await Db.inserir('piquetes', {'propriedade_id': Db.pid, 'nome': 'Piquete 3'});
      await pumpEventQueue();
      await executarVoz(interpretarVoz('vaca 12 inseminada touro bravo')!, data: '2026-01-10');
      await pumpEventQueue();
      expect(Db.registros('reproducoes').single['touro'], 'Bravo');
      await executarVoz(interpretarVoz('vaca 12 pariu femea brinco 300')!, data: '2026-10-20');
      await executarVoz(interpretarVoz('brinco 45 escore 3 e meio')!, data: '2026-10-20');
      await executarVoz(interpretarVoz('brinco 45 piquete 3')!, data: '2026-10-20');
      await executarVoz(interpretarVoz('despesa 350 reais diesel')!, data: '2026-10-20');
      await pumpEventQueue();
      expect(Db.registros('animais').any((a) => a['brinco'] == '300' && a['mae_id'] == v), isTrue);
      expect(Db.registros('escores').single['ecc'], 3.5);
      expect(Db.registro('animais', b)!['piquete_id'], pq);
      expect(Db.registros('custos').single['categoria'], 'Combustível e máquinas');
      await executarVoz(interpretarVoz('brinco 45 morreu raio')!, data: '2026-10-21');
      await pumpEventQueue();
      expect(Db.registro('animais', b)!['status'], 'Morto');
    });

    test('mensagens coladas do WhatsApp', () {
      final m = lerConversaWhatsApp('[25/10/2026 14:20:01] Zé: brinco 45 peso 450\n'
          '25/10/26 14:21 - Zé: <Mídia oculta>\n'
          '26/10/2026 07:02 - João: vaca 12 prenhe\n'
          'bom dia pessoal\n'
          'chuva 20 mm');
      expect(m.length, 4);
      expect((m[0].data, m[0].autor, m[0].comando?.descricao), ('2026-10-25', 'Zé', 'Brinco 45 · peso 450 kg'));
      expect((m[1].data, m[1].comando?.descricao), ('2026-10-26', 'Brinco 12 · diagnóstico: Prenhe'));
      expect(m[2].comando, isNull);
      expect((m[3].data, m[3].comando?.descricao), (null, 'Chuva 20 mm'));
    });

    test('voz recusa peso zero', () async {
      await animal('78');
      expect(() => executarVoz(interpretarVoz('brinco 78 peso zero')!, data: '2026-10-15'), throwsStateError);
    });

    test('grava pesagem e diagnóstico pelo brinco', () async {
      final a = await animal('77', sexo: 'F');
      await executarVoz(interpretarVoz('brinco 77 peso 380')!, data: '2026-10-15');
      final r = await Db.registrarInseminacao(femeaId: a, data: '2026-08-01', tipo: 'IA');
      await pumpEventQueue();
      await executarVoz(interpretarVoz('brinco 77 prenhe')!, data: '2026-10-15');
      await pumpEventQueue();
      expect(Db.registros('pesagens').single['peso'], 380);
      expect(Db.registro('reproducoes', r)!['diagnostico'], 'Prenhe');
      expect(() => executarVoz(interpretarVoz('brinco 99 peso 300')!, data: '2026-10-15'), throwsStateError);
    });
  });

  test('fotos entram no backup e voltam na restauração', () async {
    final a = await animal('5');
    await Db.salvarFoto(a, 'Zm90bw==');
    final texto = Db.exportarJson();
    expect((jsonDecode(texto)['fotos'] as List).single['imagem'], 'Zm90bw==');

    await Db.salvarFoto(a, null);
    await Db.importarJson(texto);
    expect(await Db.foto(a), 'Zm90bw==');
  });

  test('backup leva patrimônio e dados do LCDPR (config)', () async {
    await animal('6');
    await Db.salvarConfig('patrimonio', {'valor_cabeca': 3000});
    await Db.salvarConfig('fila', {'dia': '2026-10-20'});
    await pumpEventQueue();
    final texto = Db.exportarJson();
    await Db.salvarConfig('patrimonio', {'valor_cabeca': 0});
    await Db.importarJson(texto);
    await pumpEventQueue();
    expect(Db.registro('config', 'patrimonio')!['valor_cabeca'], 3000);
    expect(texto, isNot(contains('2026-10-20')));
  });
}
