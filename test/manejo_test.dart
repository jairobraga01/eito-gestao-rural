import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/manejo.dart';
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

  Future<int> animal(String brinco, {String sexo = 'F', int? mae, String? nascimento, int? lote}) =>
      Db.inserir('animais', {
        'propriedade_id': pid,
        'brinco': brinco,
        'sexo': sexo,
        'status': 'Ativo',
        'mae_id': mae,
        'nascimento': nascimento,
        'lote_id': lote,
      });

  group('Fila do dia', () {
    test('junta vacinas vencidas, diagnósticos, partos e etapas de IATF', () async {
      final boi = await animal('1', sexo: 'M');
      await Db.lancarSanidade([boi], {'data': '2026-04-01', 'tipo': 'Vacinação', 'produto': 'Aftosa', 'proxima': '2026-10-10'});
      final vaca = await animal('2');
      await Db.registrarInseminacao(femeaId: vaca, data: '2026-09-01', tipo: 'IATF');
      final prenhe = await animal('3');
      final r = await Db.registrarInseminacao(femeaId: prenhe, data: '2026-01-01', tipo: 'IA');
      await Db.lancarDiagnostico(r, 'Prenhe', '2026-02-01'); // parto previsto 2026-10-18
      final lote = await animal('4');
      await Db.salvarProtocolo(nome: 'D0-D8-D10', inicio: '2026-10-07', etapas: [
        {'dia': 0, 'nome': 'Implante'},
        {'dia': 8, 'nome': 'Retirada'},
        {'dia': 10, 'nome': 'IATF'},
      ], femeas: [lote]);

      final fila = filaDoDia('2026-10-15');
      expect(fila.map((i) => i.tipo), unorderedEquals(TipoFila.values));
      expect(fila.firstWhere((i) => i.tipo == TipoFila.sanidade).titulo, 'Aftosa · 1 animal');
      expect(fila.firstWhere((i) => i.tipo == TipoFila.sanidade).atrasado, isTrue);
      expect(fila.firstWhere((i) => i.tipo == TipoFila.protocolo).titulo, 'D8 · Retirada');
      expect(fila.firstWhere((i) => i.tipo == TipoFila.diagnostico).detalhe, 'IATF há 44 dias');
      expect(fila.firstWhere((i) => i.tipo == TipoFila.parto).detalhe, 'previsto em 3 dias');

      // Vacina refeita sai da fila.
      await Db.lancarSanidade([boi], {'data': '2026-10-15', 'tipo': 'Vacinação', 'produto': 'Aftosa'});
      expect(filaDoDia('2026-10-15').where((i) => i.tipo == TipoFila.sanidade), isEmpty);
    });

    test('inseminação de vaca em protocolo leva o nome do protocolo', () async {
      final vaca = await animal('5');
      await Db.salvarProtocolo(nome: 'D0-D7-D9', inicio: '2026-10-01', etapas: [
        {'dia': 0, 'nome': 'Implante'},
        {'dia': 9, 'nome': 'IATF'},
      ], femeas: [vaca]);
      final id = await Db.registrarInseminacao(femeaId: vaca, data: '2026-10-10', tipo: 'IATF');
      expect(Db.registro('reproducoes', id)!['protocolo'], 'D0-D7-D9');
    });
  });

  test('intervalo entre partos junta partos lançados e crias, sem contar gêmeos', () async {
    final vaca = await animal('10');
    await animal('11', mae: vaca, nascimento: '2024-01-10');
    await animal('12', mae: vaca, nascimento: '2024-01-10'); // gêmeo
    await animal('13', mae: vaca, nascimento: '2025-01-04');
    await Db.inserir('reproducoes', {'femea_id': vaca, 'data': '2025-03-01', 'parto_data': '2025-12-20'});

    expect(partosDaVaca(vaca), ['2024-01-10', '2025-01-04', '2025-12-20']);
    expect(intervaloEntrePartos(vaca), (360 + 350) / 2);
    expect(intervaloEntrePartos(await animal('14')), isNull);
    expect(intervaloEntrePartosRebanho(), ((360 + 350) / 2, 1));
  });

  group('Projeção de abate', () {
    test('calcula os dias até o peso pelo GMD', () {
      final p = projetarAnimal({'id': 1}, [
        {'id': 1, 'data': '2026-01-01', 'peso': 300},
        {'id': 2, 'data': '2026-05-01', 'peso': 420}, // 120 kg em 120 dias
      ], 540)!;
      expect(p.peso, 420);
      expect(p.gmd, 1.0);
      expect(p.dias, 120);
      expect(projetarAnimal({'id': 2}, [{'data': '2026-01-01', 'peso': 560}], 540)!.dias, 0);
      expect(projetarAnimal({'id': 3}, [{'data': '2026-01-01', 'peso': 300}], 540)!.dias, isNull);
      expect(projetarAnimal({'id': 4}, const [], 540), isNull);
    });

    test('agrupa por lote e calcula o valor pela arroba', () async {
      final lote = await Db.inserir('lotes', {'propriedade_id': pid, 'nome': 'Engorda'});
      final a = await animal('20', sexo: 'M', lote: lote);
      final b = await animal('21', sexo: 'M', lote: lote);
      await Db.registrarPesagem(a, 400, data: '2026-01-01');
      await Db.registrarPesagem(a, 500, data: '2026-04-11'); // 100 dias, GMD 1
      await Db.registrarPesagem(b, 560, data: '2026-04-11');

      final l = projecaoAbate(540).single;
      expect(l.nome, 'Engorda');
      expect(l.prontos, 1);
      expect(l.pesoMedio, 530);
      expect(l.diasMediana, 0);
      expect(valorArroba(540, 0.5, 300), 5400);
    });
  });
}
