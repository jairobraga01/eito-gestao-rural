import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/estacao.dart';
import 'package:eito_gestao_rural/dados/estoque.dart';
import 'package:eito_gestao_rural/dados/iatf.dart';
import 'package:eito_gestao_rural/dados/indicadores.dart' show lancarEcc;
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

  Future<int> vaca(String brinco, {String nascimento = '2022-01-01'}) => Db.inserir('animais', {
        'propriedade_id': pid,
        'brinco': brinco,
        'sexo': 'F',
        'status': 'Ativo',
        'nascimento': nascimento,
        'categoria': 'Vaca',
      });

  Future<int> protocolo(List<int> femeas, {List<Map<String, Object?>> produtos = const []}) => Db.salvarProtocolo(
        nome: 'D0-D8-D10',
        inicio: '2026-10-01',
        etapas: [
          {'dia': 0, 'nome': 'Implante + BE', if (produtos.isNotEmpty) 'produtos': produtos},
          {'dia': 8, 'nome': 'Retirada'},
          {'dia': 10, 'nome': 'IATF'},
        ],
        femeas: femeas,
      );

  test('hormônios: custo por vaca, total do lote e baixa única no estoque', () async {
    final implante = await Db.inserir('insumos', {'propriedade_id': pid, 'nome': 'Implante', 'unidade': 'un', 'preco_saco': 100, 'kg_saco': 10});
    final be = await Db.inserir('insumos', {'propriedade_id': pid, 'nome': 'BE', 'unidade': 'ml', 'preco_saco': 50, 'kg_saco': 100});
    await entradaEstoque(implante, 20, data: '2026-09-01');
    final a = await vaca('1'), b = await vaca('2'), c = await vaca('3');
    final p = await protocolo([a, b, c], produtos: [
      {'insumo_id': implante, 'qtd': 1},
      {'insumo_id': be, 'qtd': 2},
    ]);
    await descartarDoProtocolo(p, c);
    await pumpEventQueue();
    final (porVaca, total) = custoHormonal(Db.registro('protocolos', p)!);
    expect(porVaca, 11); // 10 + 2 × 0,50
    expect(total, 22); // 2 vacas (uma descartada)
    expect(await darBaixaEtapa(p, 0, '2026-10-01'), 2);
    await pumpEventQueue();
    expect(saldo(implante), 18);
    expect(saldo(be), -4);
    expect(await darBaixaEtapa(p, 0, '2026-10-01'), 0); // não baixa duas vezes
  });

  test('repasse com touro: monta natural das vazias, resultado à parte', () async {
    final a = await vaca('10'), b = await vaca('11'), c = await vaca('12');
    final p = await protocolo([a, b, c]);
    for (final f in [a, b, c]) {
      final id = await Db.registrarInseminacao(femeaId: f, data: '2026-10-11', tipo: 'IATF');
      await Db.lancarDiagnostico(id, f == a ? 'Prenhe' : 'Vazia', '2026-11-10');
    }
    await pumpEventQueue();
    expect(await repasseComTouro(Db.registro('protocolos', p)!, touro: 'Tufão', entrada: '2026-11-12'), 2);
    await pumpEventQueue();
    final rep = Db.registros('reproducoes').where((r) => r['repasse_de'] == p).toList();
    expect(rep.length, 2);
    expect(rep.first['tipo'], 'Monta natural');
    expect(rep.first['touro'], 'Tufão');
    await Db.lancarDiagnostico(rep.first['id'] as int, 'Prenhe', '2026-12-20');
    await pumpEventQueue();
    expect(resultadoRepasse(Db.registro('protocolos', p)!), (1, 0, 1));
    expect(Db.registro('reproducoes', rep.first['id'])!['parto_previsto'], Db.partoPrevisto('2026-11-12'));
    // O resultado da IATF não muda com o repasse.
    expect(resultadoProtocolo(Db.registro('protocolos', p)!).prenhes, 1);
    expect(vaziasParaRepasse(Db.registro('protocolos', p)!), isEmpty);
  });

  test('estação de monta: aptas, prenhez acumulada por ciclo e custo por bezerro desmamado', () async {
    final a = await vaca('20'), b = await vaca('21'), c = await vaca('22');
    await vaca('23', nascimento: '2026-06-01'); // bezerra: não é apta
    final s = await Db.salvarSemen({'touro': 'Bandido', 'preco_dose': 60, 'doses': 10});
    final e = await salvarEstacao({'nome': 'Estação 26/27', 'inicio': '2026-10-01', 'fim': '2027-01-31', 'outros_custos': 120});
    final ia1 = await Db.registrarInseminacao(femeaId: a, data: '2026-10-05', tipo: 'IATF', semenId: s);
    final ia2 = await Db.registrarInseminacao(femeaId: b, data: '2026-10-30', tipo: 'IA', semenId: s);
    await Db.lancarDiagnostico(ia1, 'Prenhe', '2026-11-05');
    await Db.lancarDiagnostico(ia2, 'Prenhe', '2026-12-01');
    await pumpEventQueue();
    final cria = await Db.registrarNascimento(maeId: a, data: '2027-07-20', brinco: 'B1', sexo: 'F', reproducaoId: ia1);
    await Db.inserir('pesagens', {'animal_id': cria, 'data': '2028-03-01', 'peso': 210, 'evento': 'Desmama'});
    await pumpEventQueue();

    final r = resultadoEstacao(Db.registro('estacoes', e)!);
    expect(r.aptas.keys, unorderedEquals([a, b, c]));
    expect(r.prenhes.length, 2);
    expect(r.naoServidas.map((x) => x['id']), [c]);
    expect(r.taxaPrenhez, closeTo(2 / 3, 1e-9));
    expect(r.ciclos.first.prenhes, 1);
    expect(r.ciclos[1].prenhes, 1); // 30/10 cai no 2º ciclo (22/10 a 11/11)
    expect(r.ciclos[1].acumulado, 2);
    expect(r.custoTotal, 240); // 2 doses × 60 + 120
    expect(r.custoPorPrenhez, 120);
    expect(r.bezerrosDesmamados, 1);
    expect(r.custoPorDesmamado, 240);
  });

  test('sexagem fetal entra na previsão de partos', () async {
    final a = await vaca('30'), b = await vaca('31');
    final x = await Db.registrarInseminacao(femeaId: a, data: '2026-10-05', tipo: 'IATF');
    final y = await Db.registrarInseminacao(femeaId: b, data: '2026-10-05', tipo: 'IATF');
    await Db.lancarDiagnostico(x, 'Prenhe', '2026-11-05', sexoFeto: 'Fêmea');
    await Db.lancarDiagnostico(y, 'Prenhe', '2026-11-05');
    await Db.lancarConfirmacao(y, true, '2026-12-05', sexoFeto: 'Macho');
    await pumpEventQueue();
    final m = previsaoPartos().single;
    expect(m.mes, '2027-07');
    expect((m.femeas, m.machos, m.semSexagem), (1, 1, 0));
  });

  test('vacas problema: falhas seguidas, novilha passada e ECC baixo', () async {
    final a = await vaca('40'), novilha = await vaca('41', nascimento: '2023-01-01'), magra = await vaca('42');
    await Db.inserir('animais', {'propriedade_id': pid, 'brinco': 'C', 'sexo': 'M', 'status': 'Ativo', 'mae_id': a, 'nascimento': '2025-01-10'});
    for (final d in ['2026-03-01', '2026-04-10']) {
      final id = await Db.registrarInseminacao(femeaId: a, data: d, tipo: 'IA');
      await Db.lancarDiagnostico(id, 'Vazia', d);
      await pumpEventQueue();
    }
    await lancarEcc(magra, '2026-10-01', 2.0);
    // Uma vaca com cria recente e sem falhas não aparece.
    final ok = await vaca('43');
    await Db.inserir('animais', {'propriedade_id': pid, 'brinco': 'D', 'sexo': 'F', 'status': 'Ativo', 'mae_id': ok, 'nascimento': '2026-08-01'});
    await pumpEventQueue();

    final l = {for (final v in vacasProblema('2026-10-15')) v.vaca['id']: v.motivos};
    expect(l[a], contains('2 serviços vazios desde o último parto'));
    expect(l[a]!.any((m) => m.contains('dias sem parir')), isTrue);
    expect(l[novilha], ['novilha com 45 meses e não emprenhou']);
    expect(l[magra]!.any((m) => m.startsWith('ECC baixo')), isTrue);
    expect(l.containsKey(ok), isFalse);
  });
}
