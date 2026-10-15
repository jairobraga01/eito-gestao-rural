import 'package:eito_gestao_rural/dados/db.dart';
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

  Future<int> animal(String brinco, {String sexo = 'F', String? origem, String? nascimento}) =>
      Db.inserir('animais', {
        'propriedade_id': pid,
        'brinco': brinco,
        'sexo': sexo,
        'status': 'Ativo',
        'origem': origem,
        'nascimento': nascimento,
      });

  Future<int> semen({double preco = 50, int doses = 10}) =>
      Db.salvarSemen({'touro': 'Bandido', 'preco_dose': preco, 'doses': doses});

  group('Modo Inseminação', () {
    test('registra a IATF com touro, protocolo e preço e dá baixa de uma dose', () async {
      final vaca = await animal('10');
      final s = await semen();
      final id = await Db.registrarInseminacao(
          femeaId: vaca, data: '2026-03-01', tipo: 'IATF', semenId: s, inseminador: 'Zé', protocolo: 'D0-D8-D10');

      final r = Db.registro('reproducoes', id)!;
      expect(r['touro'], 'Bandido');
      expect(r['custo_dose'], 50);
      expect(r['protocolo'], 'D0-D8-D10');
      expect(r['inseminador'], 'Zé');
      expect(r['diagnostico'], 'Pendente');
      expect(Db.registro('semens', s)!['doses'], 9);
    });

    test('repasse fecha o serviço anterior como vazia', () async {
      final vaca = await animal('11');
      final primeiro = await Db.registrarInseminacao(femeaId: vaca, data: '2026-03-01', tipo: 'IATF');
      await Db.registrarInseminacao(femeaId: vaca, data: '2026-03-25', tipo: 'IA');

      expect(Db.registro('reproducoes', primeiro)!['diagnostico'], 'Vazia');
      expect(Db.registro('reproducoes', primeiro)!['data_diagnostico'], '2026-03-25');
    });

    test('não insemina vaca prenhe', () async {
      final vaca = await animal('12');
      final id = await Db.registrarInseminacao(femeaId: vaca, data: '2026-03-01', tipo: 'IATF');
      await Db.lancarDiagnostico(id, 'Prenhe', '2026-04-01');
      expect(() => Db.registrarInseminacao(femeaId: vaca, data: '2026-04-02', tipo: 'IA'),
          throwsA(isA<RegistroDuplicado>()));
    });

    test('diagnóstico prenhe calcula o parto previsto; vazia limpa', () async {
      final vaca = await animal('13');
      final id = await Db.registrarInseminacao(femeaId: vaca, data: '2026-01-01', tipo: 'IATF');

      await Db.lancarDiagnostico(id, 'Prenhe', '2026-02-05');
      expect(Db.registro('reproducoes', id)!['parto_previsto'], '2026-10-18'); // 290 dias
      expect(Db.registro('reproducoes', id)!['data_diagnostico'], '2026-02-05');

      await Db.lancarDiagnostico(id, 'Vazia', '2026-02-06');
      expect(Db.registro('reproducoes', id)!['parto_previsto'], isNull);
    });

    test('excluir a inseminação devolve a dose ao estoque', () async {
      final vaca = await animal('14');
      final s = await semen(doses: 3);
      final id = await Db.registrarInseminacao(femeaId: vaca, data: '2026-03-01', tipo: 'IA', semenId: s);
      expect(Db.registro('semens', s)!['doses'], 2);

      await Db.excluir('reproducoes', id);
      expect(Db.registro('semens', s)!['doses'], 3);
    });

    test('lista de sêmen mostra usadas, prenhes e custo', () async {
      final s = await semen(preco: 40);
      for (final (b, diag) in [('20', 'Prenhe'), ('21', 'Vazia'), ('22', 'Prenhe')]) {
        final id = await Db.registrarInseminacao(femeaId: await animal(b), data: '2026-03-01', tipo: 'IATF', semenId: s);
        await Db.lancarDiagnostico(id, diag, '2026-04-01');
      }
      await pumpEventQueue(); // deixa chegar os avisos do banco
      final l = await Db.semens();
      expect(l.single['usadas'], 3);
      expect(l.single['prenhes'], 2);
      expect(l.single['custo'], 120);
      expect(l.single['doses'], 7);
    });
  });

  group('Relatório do período', () {
    test('conta nascimentos, inseminadas, taxa de prenhez e custo por prenhez', () async {
      await animal('30', origem: 'Nascimento', nascimento: '2026-05-10');
      await animal('31', sexo: 'M', origem: 'Nascimento', nascimento: '2026-05-20');
      await animal('32', origem: 'Compra', nascimento: '2026-05-21'); // comprado não conta
      await animal('33', origem: 'Nascimento', nascimento: '2026-06-01'); // outro mês

      final s = await semen(preco: 60);
      final a = await Db.registrarInseminacao(femeaId: await animal('40'), data: '2026-05-02', tipo: 'IATF', semenId: s);
      final b = await Db.registrarInseminacao(femeaId: await animal('41'), data: '2026-05-02', tipo: 'IATF', semenId: s);
      await Db.registrarInseminacao(femeaId: await animal('42'), data: '2026-05-03', tipo: 'IATF', semenId: s);
      await Db.lancarDiagnostico(a, 'Prenhe', '2026-06-02');
      await Db.lancarDiagnostico(b, 'Vazia', '2026-06-02');

      final mai = ResumoPeriodo.mes(2026, 5);
      expect(mai.nascimentos, 2);
      expect(mai.nascMachos, 1);
      expect(mai.nascFemeas, 1);
      expect(mai.inseminadas, 3);
      expect(mai.prenhes, 1);
      expect(mai.vazias, 1);
      expect(mai.pendentes, 1);
      expect(mai.taxaPrenhez, 0.5);
      expect(mai.custoSemen, 180);
      expect(mai.custoPorPrenhez, 180);

      // Parto previsto da prenhe: 2026-05-02 + 290 dias = 2027-02-16.
      expect(ResumoPeriodo.mes(2027, 2).partosPrevistos, 1);
      expect(ResumoPeriodo.ano(2026).nascimentos, 3);
      expect(ResumoPeriodo.mesesDoAno(2026).map((m) => m.nascimentos).toList(),
          [0, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0]);
    });

    test('vacinações, GMD e saídas ficam no mês certo', () async {
      final boi = await animal('50', sexo: 'M');
      await Db.lancarSanidade([boi], {'data': '2026-07-01', 'tipo': 'Vacinação', 'produto': 'Aftosa'});
      await Db.lancarSanidade([boi], {'data': '2026-07-02', 'tipo': 'Antiparasitário', 'produto': 'Ivermectina'});
      await Db.lancarSanidade([boi], {'data': '2026-08-01', 'tipo': 'Vacinação', 'produto': 'Raiva'});
      await Db.registrarPesagem(boi, 300, data: '2026-07-01');
      await Db.registrarPesagem(boi, 330, data: '2026-07-31');
      await Db.registrarSaida({'tipo': 'Venda', 'data': '2026-07-31', 'valor_total': 9000}, [boi]);

      final jul = ResumoPeriodo.mes(2026, 7);
      expect(jul.vacinacoes, 1);
      expect(jul.manejosSanitarios, 2);
      expect(jul.vacinasPorProduto, {'Aftosa': 1});
      expect(jul.pesagens, 2);
      expect(jul.gmdMedio, closeTo(1.0, 1e-9));
      expect(jul.saidas, 1);
      expect(jul.saidasPorTipo, {'Venda': 1});
      expect(jul.valorVendas, 9000);
      expect(ResumoPeriodo.mes(2026, 8).vacinacoes, 1);
      expect(ResumoPeriodo.mes(2026, 8).gmdMedio, isNull);
    });
  });
}
