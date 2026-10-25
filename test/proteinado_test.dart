import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/dividas.dart';
import 'package:eito_gestao_rural/dados/leite.dart';
import 'package:eito_gestao_rural/dados/proteinado.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    Db.bancoTeste = FakeFirebaseFirestore();
    await Db.iniciar('teste');
  });

  tearDown(Db.encerrar);

  Reg formula(String tipo, String nome) => formulas().firstWhere((f) => f['tipo'] == tipo && f['nome'] == nome);

  test('fórmulas da planilha batem com o cálculo dela', () async {
    expect(await carregarPlanilhaProteinado(), 11);
    await pumpEventQueue();
    expect(await carregarPlanilhaProteinado(), 0); // não duplica

    final n = CalculoFormula(formula('Baixo consumo', 'Nutroeste'));
    expect(n.kgBatida, 500);
    expect(n.custoBatida, closeTo(905, 1e-9)); // 873 de insumos + 12 de sacos + 20 de mão de obra
    expect(n.precoKg, closeTo(1.81, 1e-9));
    expect(n.custoCabecaDia, closeTo(0.8145, 1e-9));
    expect(n.kgSeca, closeTo(40.5, 1e-9));
    expect(n.custoSeca, closeTo(73.305, 1e-9));

    expect(CalculoFormula(formula('Baixo consumo', 'Fortaleza')).custoBatida, closeTo(720.8, 1e-9));
    expect(CalculoFormula(formula('Baixo consumo', 'Guedcy')).custoBatida, closeTo(688, 0.05));
    expect(CalculoFormula(formula('Alto consumo', 'Nutroeste 2')).custoBatida, closeTo(703.92, 1e-9));
    // A planilha divide por 400, mas a batida tem 800 kg.
    expect(CalculoFormula(formula('Alto consumo', 'Nutroeste')).precoKg, closeTo(1658.4 / 800, 1e-9));
    expect(CalculoFormula(formula('Ração creep', 'Nutroeste')).custoBatida, closeTo(806, 1e-9));
    expect(CalculoFormula(formula('Baixo consumo', 'Agrocria')).semPreco, ['Calcário calcítico', 'Fosfato bicálcico']);
  });

  test('tipos fixos na ordem, tipo antigo Creep e tipos criados pelo usuário', () async {
    await Db.inserir('formulas', {'propriedade_id': Db.pid, 'nome': 'Antiga', 'tipo': 'Creep'});
    await Db.inserir('formulas', {'propriedade_id': Db.pid, 'nome': 'Mineral', 'tipo': 'Sal mineral'});
    await Db.inserir('formulas', {'propriedade_id': Db.pid, 'nome': 'Leite', 'tipo': 'ração leite'});
    expect(tiposEmUso(), ['Alto consumo', 'Médio consumo', 'Baixo consumo', 'Ração creep', 'Ração leite', 'Sal mineral']);
    expect(formulas().map(tipoFormula), ['Ração creep', 'Ração leite', 'Sal mineral']);
    await pumpEventQueue();
    await carregarPlanilhaProteinado();
    await pumpEventQueue();
    expect(formulas().where((f) => tipoFormula(f) == 'Médio consumo').length, 1);
    expect(formulas().where((f) => tipoFormula(f) == 'Ração leite').length, 2);
  });

  test('preço novo do insumo refaz a fórmula e a batida vai para Custos', () async {
    await carregarPlanilhaProteinado();
    await pumpEventQueue();
    final milho = insumos().firstWhere((i) => i['nome'] == 'Milho');
    await Db.atualizar('insumos', milho['id'] as int, {'preco_saco': 90});
    final f = formula('Baixo consumo', 'Fortaleza');
    expect(CalculoFormula(f).custoBatida, closeTo(720.8 + 140 * 0.2, 1e-9));

    await registrarBatida(f, data: '2026-10-15', batidas: 2);
    final c = Db.registros('custos').single;
    expect(c['categoria'], 'Ração e sal');
    expect(c['valor'], closeTo(2 * 748.8, 1e-9));
    expect(c['descricao'], 'Proteinado Fortaleza · 2 batidas (800 kg)');
  });

  test('a última cotação passa a valer na projeção de abate', () async {
    await Db.salvarConfig('abate', {'alvo': 540, 'rendimento': 52, 'arroba': 280});
    await registrarCotacao(data: '2026-10-10', valor: 300);
    final id = await registrarCotacao(data: '2026-10-15', valor: 315.5, praca: 'MS');
    await pumpEventQueue();
    final abate = Db.registro('config', 'abate')!;
    expect(abate['arroba'], 315.5);
    expect(abate['alvo'], 540);
    expect(cotacoes().first['praca'], 'MS');

    await excluirCotacao(id);
    await pumpEventQueue();
    expect(Db.registro('config', 'abate')!['arroba'], 300);
  });

  group('Dívidas e ônus reais', () {
    test('gera parcelas iguais e a última leva os centavos', () {
      final ps = gerarParcelas(1000, 3, '2026-01-31', intervaloMeses: 1);
      expect(ps.map((p) => p['vencimento']), ['2026-01-31', '2026-02-28', '2026-03-31']);
      expect(ps.map((p) => p['valor']), [333.33, 333.33, 333.34]);
      expect(gerarParcelas(1009.80, 10, '2026-01-01').map((p) => p['valor']).toSet(), {100.98});
      expect(gerarParcelas(1024.36, 2, '2026-01-01').map((p) => p['valor']), [512.18, 512.18]);
    });

    test('saldo, parcelas a vencer, pagamento e ônus', () async {
      final id = await Db.inserir('dividas', {
        'propriedade_id': Db.pid,
        'credor': 'Banco',
        'tipo': 'Investimento',
        'valor_total': 30000,
        'parcelas': gerarParcelas(30000, 3, '2026-09-01'),
        'onus': 'Hipoteca',
        'bem': 'Fazenda',
      });
      expect(saldoDevedor(Db.registro('dividas', id)!), 30000);
      expect(onusAtivo(Db.registro('dividas', id)!), isTrue);

      final aVencer = parcelasAVencer('2026-10-15');
      expect(aVencer.single.vencimento, '2026-09-01'); // vencida; as outras ficam para 2027 e 2028

      await pagarParcela(Db.registro('dividas', id)!, 0, true, data: '2026-10-15');
      await pumpEventQueue();
      final d = Db.registro('dividas', id)!;
      expect(saldoDevedor(d), 20000);
      expect(totalPago(d), 10000);
      expect(proximaParcela(d)!['vencimento'], '2027-09-01');
      expect(parcelasAVencer('2026-10-15'), isEmpty);

      for (final i in [1, 2]) {
        await pagarParcela(Db.registro('dividas', id)!, i, true);
        await pumpEventQueue();
      }
      expect(quitada(Db.registro('dividas', id)!), isTrue);
      expect(onusAtivo(Db.registro('dividas', id)!), isFalse);
    });
  });

  test('produção leiteira por vaca, no mês e no ano', () async {
    Future<int> vaca(String b, {String sexo = 'F'}) =>
        Db.inserir('animais', {'propriedade_id': Db.pid, 'brinco': b, 'sexo': sexo, 'status': 'Ativo'});
    final a = await vaca('1'), b = await vaca('2'), boi = await vaca('3', sexo: 'M');
    await definirLeiteiras([a, b, boi]);
    await pumpEventQueue();
    expect(vacasLeiteiras().map((v) => v['brinco']), ['1', '2']);

    await lancarOrdenha(a, '2026-10-01', 20);
    await lancarOrdenha(a, '2026-10-02', 22);
    await lancarOrdenha(b, '2026-10-01', 10);
    await lancarOrdenha(b, '2026-09-30', 12);
    await pumpEventQueue();
    await lancarOrdenha(a, '2026-10-02', 18); // corrige o dia
    await lancarOrdenha(b, '2026-10-01', null); // apaga
    await pumpEventQueue();

    final out = ProducaoLeite.mes(2026, 10);
    expect(out.total, 38);
    expect(out.vacas.single.media, 19);
    expect(out.mediaDia, 19);
    expect(ordenhasDoDia('2026-10-02'), {a: 18});

    final ano = ProducaoLeite.ano(2026);
    expect(ano.total, 50);
    expect(ano.porMes[8], 12);
    expect(ano.vacas.map((v) => v.vaca['brinco']), ['1', '2']);
    expect(ano.mediaVacaDia, closeTo(50 / 3, 1e-9));

    await Db.excluir('animais', a);
    await pumpEventQueue();
    expect(Db.registros('ordenhas').length, 1);
  });
}
