import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/financeiro.dart';
import 'package:eito_gestao_rural/dados/iatf.dart';
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

  Future<int> vaca(String brinco, {String? raca}) => Db.inserir('animais', {
        'propriedade_id': pid,
        'brinco': brinco,
        'sexo': 'F',
        'status': 'Ativo',
        'raca': raca,
      });

  Future<int> protocolo(List<int> femeas, {String inicio = '2026-03-01', int dg = 30}) => Db.salvarProtocolo(
        nome: 'D0-D8-D10',
        inicio: inicio,
        etapas: [
          {'dia': 0, 'nome': 'Implante + BE', 'hora': '07:00'},
          {'dia': 8, 'nome': 'Retirada + PGF + eCG + cipionato'},
          {'dia': 10, 'nome': 'IATF'},
        ],
        femeas: femeas,
        extras: {'dg_dias': dg, 'veterinario': 'Dr. Paulo'},
      );

  group('Ficha da vaca', () {
    test('grava categoria, dias de parida, ordem, partida e os campos da ficha', () async {
      final v = await vaca('1');
      await Db.inserir('animais', {'propriedade_id': pid, 'brinco': 'B1', 'sexo': 'M', 'status': 'Ativo', 'mae_id': v, 'nascimento': '2025-12-01'});
      final s = await Db.salvarSemen({'touro': 'Bandido', 'partida': '0042', 'preco_dose': 40, 'doses': 5});
      final id = await inseminarComFicha(
        femeaId: v,
        data: '2026-03-11',
        tipo: 'IATF',
        semenId: s,
        inseminador: 'Zé',
        ficha: {'ecc': 3.0, 'escore_cio': escoresCio[1], 'bezerro': true, 'tratamentos': ['Suplemento P4'], 'obs': 'ok'},
      );
      final r = Db.registro('reproducoes', id)!;
      expect(r['categoria_ia'], 'Primípara');
      expect(r['dias_parida'], 100);
      expect(r['ordem'], 1);
      expect(r['partida'], '0042');
      expect(r['bezerro'], true);
      expect(r['tratamentos'], ['Suplemento P4']);
      expect(r['obs'], 'ok');
      // O ECC também vai para o histórico do animal.
      expect(Db.registros('escores').where((e) => e['animal_id'] == v).single['ecc'], 3.0);
      // Repasse: 2º serviço.
      await inseminarComFicha(femeaId: v, data: '2026-04-05', tipo: 'IA');
      expect(ordemServico(v, '2026-04-06'), 3);
      expect(categoriaReprodutiva(await vaca('2'), '2026-03-11'), 'Novilha');
    });
  });

  group('Resultado do protocolo', () {
    test('liga o serviço ao lote, conta P+, V−, perda e calcula as taxas', () async {
      final a = await vaca('10'), b = await vaca('11'), c = await vaca('12'), d = await vaca('13'), e = await vaca('14');
      final p = await protocolo([a, b, c, d, e]);
      final ia = <int, int>{};
      for (final f in [a, b, c, d]) {
        ia[f] = await Db.registrarInseminacao(femeaId: f, data: '2026-03-11', tipo: 'IATF');
      }
      expect(Db.registro('reproducoes', ia[a])!['protocolo_id'], p);
      await Db.lancarDiagnostico(ia[a]!, 'Prenhe', '2026-04-10');
      await Db.lancarDiagnostico(ia[b]!, 'Prenhe', '2026-04-10');
      await Db.lancarDiagnostico(ia[c]!, 'Vazia', '2026-04-10');
      await Db.lancarConfirmacao(ia[b]!, false, '2026-05-10'); // perdeu
      await Db.lancarConfirmacao(ia[a]!, true, '2026-05-10');
      await pumpEventQueue();

      final r = resultadoProtocolo(Db.registro('protocolos', p)!);
      expect(r.prenhes, 1);
      expect(r.vazias, 1);
      expect(r.perdas, 1);
      expect(r.aguardando, 1);
      expect(r.semIa, 1);
      expect(r.taxaPrenhez, closeTo(1 / 3, 1e-9));
      expect(r.taxaPerda, 0.5);
      expect(r.dgPrevisto, '2026-04-10');
      expect(r.confirmacaoPrevista, '2026-05-10');
      expect(r.vacas.firstWhere((v) => v.animal['id'] == a).confirmada, isTrue);
      expect(Db.registro('reproducoes', ia[b])!['parto_previsto'], isNull);

      final texto = relatorioProtocolo(Db.registro('protocolos', p)!, completo: true);
      expect(texto, contains('Taxa de prenhez: 33%'));
      expect(texto, contains('Veterinário: Dr. Paulo'));
      expect(relatorioProtocolo(Db.registro('protocolos', p)!), isNot(contains('Veterinário')));
      final planilha = planilhaProtocolo(Db.registro('protocolos', p)!);
      expect(planilha.split('\r\n').where((l) => l.isNotEmpty).length, 6); // cabeçalho + 5 vacas
    });

    test('ressincroniza as vazias e as perdas, sem as descartadas', () async {
      final a = await vaca('20'), b = await vaca('21'), c = await vaca('22');
      final p = await protocolo([a, b, c]);
      for (final f in [a, b, c]) {
        final id = await Db.registrarInseminacao(femeaId: f, data: '2026-03-11', tipo: 'IATF');
        await Db.lancarDiagnostico(id, f == a ? 'Prenhe' : 'Vazia', '2026-04-10');
      }
      await Db.atualizar('animais', c, {'descarte': true});
      await pumpEventQueue();
      final novo = await ressincronizar(Db.registro('protocolos', p)!, '2026-04-12');
      final n = Db.registro('protocolos', novo)!;
      expect(n['femeas'], [b]);
      expect(n['rodada'], 2);
      expect(n['nome'], 'D0-D8-D10 · ressinc. 2');
      expect(n['dg_dias'], 30);
      await pumpEventQueue();
      // Já ressincronizada: não entra num segundo protocolo.
      expect(vaziasParaRessinc(Db.registro('protocolos', p)!), isEmpty);
    });

    test('vazia que emprenhou no repasse não volta para a ressincronização', () async {
      final a = await vaca('40');
      final p = await protocolo([a]);
      final id = await Db.registrarInseminacao(femeaId: a, data: '2026-03-11', tipo: 'IATF');
      await Db.lancarDiagnostico(id, 'Vazia', '2026-04-10');
      await pumpEventQueue();
      expect(vaziasParaRessinc(Db.registro('protocolos', p)!), [a]);
      final m = await Db.registrarInseminacao(femeaId: a, data: '2026-04-15', tipo: 'Monta natural');
      await Db.lancarDiagnostico(m, 'Prenhe', '2026-05-20');
      await pumpEventQueue();
      expect(vaziasParaRessinc(Db.registro('protocolos', p)!), isEmpty);
    });

    test('descarte tira a vaca do lote e da fila', () async {
      final a = await vaca('30'), b = await vaca('31');
      final p = await protocolo([a, b], inicio: '2026-10-07');
      await descartarDoProtocolo(p, b);
      await pumpEventQueue();
      expect(Db.registro('animais', b)!['descarte'], true);
      final r = resultadoProtocolo(Db.registro('protocolos', p)!);
      expect(r.descartadas, 1);
      final fila = filaDoDia('2026-10-15');
      expect(fila.firstWhere((i) => i.tipo == TipoFila.protocolo).detalhe, contains('1 vaca: 30'));
    });
  });

  group('Fila do dia', () {
    test('avisa a etapa na véspera com o horário', () async {
      await protocolo([await vaca('40')], inicio: '2026-10-16');
      final f = filaDoDia('2026-10-15').where((i) => i.tipo == TipoFila.protocolo).single;
      expect(f.titulo, 'Amanhã às 07:00 · D0 · Implante + BE');
      expect(f.atrasado, isFalse);
    });

    test('DG pela palpação só aos 50 dias e confirmação aos 60', () async {
      final a = await vaca('41'), b = await vaca('42');
      await protocolo([a], dg: 50, inicio: '2026-08-01');
      await Db.registrarInseminacao(femeaId: a, data: '2026-08-11', tipo: 'IATF');
      final prenhe = await Db.registrarInseminacao(femeaId: b, data: '2026-08-11', tipo: 'IATF');
      await Db.lancarDiagnostico(prenhe, 'Prenhe', '2026-09-10');

      var fila = filaDoDia('2026-09-20'); // 40 dias
      expect(fila.where((i) => i.chave.startsWith('diag_')), isEmpty);
      fila = filaDoDia('2026-10-01'); // 51 dias
      expect(fila.where((i) => i.chave.startsWith('diag_')).length, 1);
      expect(fila.where((i) => i.chave.startsWith('conf_')).length, 0);
      fila = filaDoDia('2026-10-11'); // 61 dias
      expect(fila.where((i) => i.chave == 'conf_$prenhe').length, 1);
      await Db.lancarConfirmacao(prenhe, true, '2026-10-11');
      expect(filaDoDia('2026-10-12').where((i) => i.chave.startsWith('conf_')), isEmpty);
    });
  });

  test('concepção por fator: inseminador, bezerro ao pé e só diagnosticadas', () async {
    for (final (i, insem, bez, diag) in [
      (1, 'Zé', true, 'Prenhe'),
      (2, 'Zé', false, 'Prenhe'),
      (3, 'João', true, 'Vazia'),
      (4, 'João', false, 'Prenhe'),
      (5, 'João', false, null),
    ]) {
      final v = await vaca('5$i');
      final id = await inseminarComFicha(
          femeaId: v, data: '2026-03-11', tipo: 'IATF', inseminador: insem, ficha: {'bezerro': bez});
      if (diag != null) await Db.lancarDiagnostico(id, diag, '2026-04-10');
    }
    final porInsem = {for (final l in concepcaoPorFator('Inseminador')) l.valor: l};
    expect(porInsem['Zé']!.taxa, 1);
    expect(porInsem['João']!.total, 2);
    expect(porInsem['João']!.prenhes, 1);
    final porBezerro = {for (final l in concepcaoPorFator('Bezerro ao pé')) l.valor: l};
    expect(porBezerro['Sim']!.taxa, 0.5);
    expect(porBezerro['Não']!.taxa, 1);
    expect(concepcaoPorFator('Inseminador', ano: 2025), isEmpty);
  });

  test('relatório financeiro junta contas pagas e o que veio do rebanho sem repetir', () async {
    await salvarConta({'tipo': 'Receita', 'categoria': 'Venda de leite', 'valor': 1000, 'vencimento': '2026-03-01', 'pago': true, 'pago_em': '2026-03-02'});
    await salvarConta({'tipo': 'Despesa', 'categoria': 'Mão de obra', 'valor': 300, 'vencimento': '2026-03-05'});
    await Db.inserir('saidas', {'propriedade_id': pid, 'tipo': 'Venda', 'data': '2026-05-01', 'valor_total': 5000});
    await Db.inserir('custos', {'propriedade_id': pid, 'categoria': 'Sanidade', 'data': '2026-05-03', 'valor': 200});
    await pumpEventQueue();

    var r = relatorioFinanceiro(2026);
    expect(r.receitas, 6000);
    expect(r.despesas, 200);
    expect(r.porMes[4], (5000.0, 200.0));
    await trazerDoRebanho(2026);
    await pumpEventQueue();
    r = relatorioFinanceiro(2026);
    expect(r.receitas, 6000); // não conta duas vezes
    expect(r.resultado, 5800);
    expect(r.despesasPorCategoria['Medicamentos e vacinas'], 200);

    final p = PosicaoFinanceira('2026-04-01');
    expect(p.aPagar, 300);
    expect(p.atrasadas, 1);
    final texto = textoRelatorioFinanceiro(2026, '2026-04-01');
    expect(texto, contains('Resultado: R\$ 5.800,00'));
    expect(planilhaRelatorioFinanceiro(2026), contains('Total 2026'));
  });

  test('o veterinário não lê o financeiro', () async {
    await Db.encerrar();
    Db.bancoTeste = FakeFirebaseFirestore();
    await Db.iniciar('vet', dono: 'dono', papel: 'veterinario', nome: 'Dr. Paulo');
    expect(Db.ehVeterinario, isTrue);
    expect(Db.ehCampo, isTrue);
    expect(Db.ehPeao, isFalse);
  });
}
