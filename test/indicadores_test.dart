import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/indicadores.dart';
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

  Future<int> animal(String brinco, {String sexo = 'F', int? mae, String? nascimento, String? categoria}) =>
      Db.inserir('animais', {
        'propriedade_id': pid,
        'brinco': brinco,
        'sexo': sexo,
        'status': 'Ativo',
        'mae_id': mae,
        'nascimento': nascimento,
        'categoria': categoria,
      });

  test('carência vale até o último dia e pega o produto mais longo', () async {
    final boi = await animal('1', sexo: 'M');
    await Db.lancarSanidade([boi], {'data': '2026-10-01', 'tipo': 'Medicamento', 'produto': 'A', 'carencia': 10});
    await Db.lancarSanidade([boi], {'data': '2026-10-01', 'tipo': 'Medicamento', 'produto': 'B', 'carencia': 30});
    expect(emCarencia([boi], '2026-10-31').single.produto, 'B');
    expect(emCarencia([boi], '2026-10-31').single.libera, '2026-11-01');
    expect(emCarencia([boi], '2026-11-01'), isEmpty);
  });

  test('número oficial repetido é recusado', () async {
    await Db.inserir('animais', {'propriedade_id': pid, 'brinco': '1', 'status': 'Ativo', 'sisbov': '105000000000001'});
    await expectLater(
      Db.inserir('animais', {'propriedade_id': pid, 'brinco': '2', 'status': 'Ativo', 'sisbov': '105000000000001'}),
      throwsA(isA<RegistroDuplicado>()),
    );
    expect((await Db.buscarPorCodigo('105000000000001'))?['brinco'], '1');
  });

  test('declaração usa as colunas do SIDAGO', () async {
    await animal('1', nascimento: '2026-03-01');
    await animal('2', sexo: 'M', nascimento: '2025-06-01');
    await animal('3', nascimento: '2025-10-15'); // completou 12 meses: 13-24
    await animal('4', nascimento: '2020-01-01');
    await animal('5', sexo: 'M', categoria: 'Bezerro'); // sem nascimento: pela categoria
    final d = declaracaoRebanho('2026-10-15');
    expect(d.saldo['0-12F'], 1);
    expect(d.saldo['13-24M'], 1);
    expect(d.saldo['13-24F'], 1);
    expect(d.saldo['>36F'], 1);
    expect(d.saldo['0-12M'], 1);
    expect(d.semNascimento.length, 1);
    expect(d.total, 5);
  });

  test('prenhez pelo ECC usa o escore antes do serviço', () async {
    final magra = await animal('1', nascimento: '2020-01-01');
    final boa = await animal('2', nascimento: '2020-01-01');
    await lancarEcc(magra, '2026-01-01', 2.0);
    await lancarEcc(boa, '2026-01-01', 3.5);
    final r1 = await Db.registrarInseminacao(femeaId: magra, data: '2026-01-10', tipo: 'IATF');
    final r2 = await Db.registrarInseminacao(femeaId: boa, data: '2026-01-10', tipo: 'IATF');
    await pumpEventQueue(); // deixa chegar os avisos do banco
    await Db.lancarDiagnostico(r1, 'Vazia', '2026-02-10');
    await Db.lancarDiagnostico(r2, 'Prenhe', '2026-02-10');
    await pumpEventQueue();
    final p = prenhezPorEcc();
    expect(p['Até 2,5'], (0, 1));
    expect(p['3,5 ou mais'], (1, 1));
  });

  test('indicadores de cria contam matrizes, nascimentos e desmama', () async {
    final vaca = await animal('1', nascimento: '2020-01-01');
    await animal('2', nascimento: '2025-06-01'); // novilha, não é matriz em 2026
    final cria = await animal('3', mae: vaca, nascimento: '2026-02-01');
    await Db.inserir('pesagens', {'animal_id': cria, 'data': '2026-09-01', 'peso': 200, 'evento': 'Desmama'});
    final r = indicadoresCria(2026);
    expect(r.matrizes, 1);
    expect(r.nascimentos, 1);
    expect(r.desmamados, 1);
    expect(r.kgPorMatriz, 200);
  });

  test('fluxo de caixa põe parcelas vencidas no primeiro mês', () async {
    await Db.inserir('dividas', {
      'propriedade_id': pid,
      'descricao': 'Banco',
      'parcelas': [
        {'vencimento': '2026-09-01', 'valor': 1000, 'pago': false},
        {'vencimento': '2026-12-01', 'valor': 500, 'pago': false},
        {'vencimento': '2026-11-01', 'valor': 700, 'pago': true},
      ],
    });
    await Db.inserir('custos', {'propriedade_id': pid, 'data': '2026-08-10', 'categoria': 'Outros', 'valor': 300});
    final f = fluxoCaixa('2026-10-15');
    expect(f.meses.first.mes, '2026-10');
    expect(f.meses.first.parcelas, 1000);
    expect(f.meses[2].parcelas, 500);
    expect(f.meses[1].parcelas, 0);
    expect(f.custoMensal, 100);
  });
}
