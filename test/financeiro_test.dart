import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/financeiro.dart';
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

  test('livro caixa só tem as contas pagas, com saldo acumulado', () async {
    await salvarConta({'tipo': 'Receita', 'valor': 1000, 'vencimento': '2026-03-01', 'pago': true, 'pago_em': '2026-03-02'});
    await salvarConta({'tipo': 'Despesa', 'valor': 300, 'vencimento': '2026-02-01', 'pago': true, 'pago_em': '2026-02-10'});
    await salvarConta({'tipo': 'Despesa', 'valor': 50, 'vencimento': '2026-04-01'});
    final l = livroCaixa(2026);
    expect(l.length, 2);
    expect(l.first.saida, 300);
    expect(l.last.saldo, 700);
    expect(atrasada(contas(pagas: false).single, '2026-05-01'), isTrue);
  });

  test('trazer do rebanho não duplica e ignora o consumo do estoque', () async {
    await Db.inserir('saidas', {'propriedade_id': pid, 'tipo': 'Venda', 'data': '2026-05-01', 'valor_total': 5000});
    await Db.inserir('entradas', {'propriedade_id': pid, 'tipo': 'Compra', 'data': '2026-01-10', 'valor_total': 3000});
    await Db.inserir('custos', {'propriedade_id': pid, 'categoria': 'Sanidade', 'data': '2026-02-01', 'valor': 200});
    final trato = await Db.inserir('custos', {'propriedade_id': pid, 'categoria': 'Ração e sal', 'data': '2026-02-01', 'valor': 90});
    await Db.inserir('estoque', {'propriedade_id': pid, 'grupo': '$trato', 'qtd': -10, 'data': '2026-02-01'});
    await pumpEventQueue();
    expect(await trazerDoRebanho(2026), 3);
    await pumpEventQueue();
    expect(await trazerDoRebanho(2026), 0);
    expect(livroCaixa(2026).last.saldo, 1800);
  });

  test('LCDPR segue o leiaute: registros, valores sem vírgula e total de linhas', () async {
    await salvarDadosLcdpr({
      'cpf': '123.456.789-09',
      'nome': 'Fulano',
      'endereco': 'Rua A',
      'bairro': 'Centro',
      'uf': 'go',
      'cod_mun': '5208707',
      'cep': '76380-000',
      'email': 'a@b.com',
      'contas': [
        {'codigo': 1, 'banco': '1', 'nome_banco': 'Banco do Brasil', 'agencia': '1234', 'numero': '12345-6'},
      ],
    });
    await salvarConta({
      'tipo': 'Receita',
      'valor': 1129998.99,
      'vencimento': '2026-03-01',
      'pago': true,
      'pago_em': '2026-03-02',
      'participante_doc': '12.345.678/0001-90',
      'tipo_doc': 1,
      'conta_banco': 1,
      'descricao': 'Venda | boi',
    });
    await pumpEventQueue();
    final a = gerarLcdpr(2026);
    final linhas = a.texto.split('\r\n')..removeLast();
    expect(linhas.first, '0000|LCDPR|0013|12345678909|Fulano|0|0||01012026|31122026');
    expect(linhas[1], '0010|1');
    expect(linhas.any((l) => l.startsWith('0050|001|BR|001|Banco do Brasil|1234|123456')), isTrue);
    final q100 = linhas.firstWhere((l) => l.startsWith('Q100'));
    expect(q100, 'Q100|02032026|001|001||1|Venda / boi|12345678000190|1|112999899|0|112999899|P');
    expect(linhas.where((l) => l.startsWith('Q200')).length, 12);
    expect(linhas.last, startsWith('9999|'));
    expect(linhas.last.split('|').last, '${linhas.length}');
  });
}
