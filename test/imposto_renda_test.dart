import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/financeiro.dart';
import 'package:eito_gestao_rural/dados/imposto_renda.dart';
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

  test('movimentação do rebanho: estoque inicial, compras, nascidos, vendas e perdas', () async {
    final compra = await Db.inserir('entradas', {'propriedade_id': pid, 'tipo': 'Compra', 'data': '2025-03-01'});
    final venda = await Db.inserir('saidas', {'propriedade_id': pid, 'tipo': 'Venda', 'data': '2025-09-01'});
    final morte = await Db.inserir('saidas', {'propriedade_id': pid, 'tipo': 'Morte', 'data': '2025-10-01'});
    final antiga = await Db.inserir('saidas', {'propriedade_id': pid, 'tipo': 'Venda', 'data': '2024-06-01'});
    Future<void> animal(String brinco, Reg v) =>
        Db.inserir('animais', {'propriedade_id': pid, 'brinco': brinco, 'status': 'Ativo', ...v});
    await animal('1', {'criado_em': '2024-01-01'}); // já estava
    await animal('2', {'criado_em': '2024-01-01', 'saida_id': venda, 'status': 'Vendido'});
    await animal('3', {'entrada_id': compra, 'origem': 'Compra'});
    await animal('4', {'origem': 'Nascimento', 'nascimento': '2025-05-01', 'saida_id': morte, 'status': 'Morto'});
    await animal('5', {'criado_em': '2023-01-01', 'saida_id': antiga, 'status': 'Vendido'}); // saiu antes
    await animal('6', {'origem': 'Nascimento', 'nascimento': '2026-02-01'}); // nasceu depois
    final r = movimentacaoRebanho(2025);
    expect(r.estoqueInicial, 2);
    expect(r.aquisicoes, 1);
    expect(r.nascimentos, 1);
    expect(r.vendas, 1);
    expect(r.consumoPerdas, 1);
    expect(r.estoqueFinal, 2);
  });

  test('receitas e despesas por mês, investimento e opção pelos 20%', () async {
    await salvarConta({'tipo': 'Receita', 'valor': 10000, 'vencimento': '2025-03-01', 'pago': true, 'pago_em': '2025-03-05'});
    await salvarConta({'tipo': 'Despesa', 'categoria': 'Mão de obra', 'valor': 2000, 'pago': true, 'pago_em': '2025-03-10'});
    await salvarConta({
      'tipo': 'Despesa',
      'categoria': categoriaInvestimento,
      'valor': 1000,
      'pago': true,
      'pago_em': '2025-07-10',
    });
    final a = atividadeRural(2025);
    expect(a.meses[2].receita, 10000);
    expect(a.meses[2].custeio, 2000);
    expect(a.meses[6].investimento, 1000);
    expect(a.resultadoReal, 7000);
    expect(a.resultadoArbitrado, 2000);
    expect(a.compensaArbitrar, isTrue);
    expect(planilhaAtividadeRural(2025), contains('MOVIMENTAÇÃO DO REBANHO'));
  });

  test('dívida: saldo no fim de cada ano e o que foi pago', () async {
    await Db.inserir('dividas', {
      'propriedade_id': pid,
      'tipo': 'Custeio',
      'credor': 'Banco',
      'data': '2024-05-01',
      'parcelas': [
        {'vencimento': '2025-05-01', 'valor': 500.0, 'pago': true, 'pago_em': '2025-05-01'},
        {'vencimento': '2026-05-01', 'valor': 500.0, 'pago': false},
      ],
    });
    final d = atividadeRural(2025).dividas.single;
    expect(d.saldoAnterior, 1000);
    expect(d.saldoAtual, 500);
    expect(d.pagoNoAno, 500);
  });

  test('o contador lança no financeiro, mas não no rebanho', () async {
    await Db.encerrar();
    Db.bancoTeste = FakeFirebaseFirestore();
    await Db.iniciar('cont', dono: 'dono', papel: 'contador', nome: 'Contador');
    final c = await salvarConta({'tipo': 'Despesa', 'valor': 100, 'vencimento': '2025-01-10'});
    final a = await Db.inserir('animais', {'propriedade_id': Db.pid, 'brinco': '9', 'status': 'Ativo'});
    expect(Db.registro('contas', c), isNotNull);
    expect(Db.registro('animais', a), isNull);
  });
}
