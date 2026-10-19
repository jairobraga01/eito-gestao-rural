import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/importar_animais.dart';
import 'package:eito_gestao_rural/dados/patrimonio.dart';
import 'package:eito_gestao_rural/dados/plataforma.dart';
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

  group('importação de planilha', () {
    test('lê CSV com ; e aspas', () {
      final t = lerCsv('brinco;obs\n1;"tem ; dentro"\n2;"aspas ""duplas"""\n');
      expect(t, [
        ['brinco', 'obs'],
        ['1', 'tem ; dentro'],
        ['2', 'aspas "duplas"'],
      ]);
    });

    test('lê CSV com vírgula e datas', () {
      expect(lerCsv('a,b\n1,2')[1], ['1', '2']);
      expect(dataImportada('05/03/2021'), '2021-03-05');
      expect(dataImportada('2021-03-05'), '2021-03-05');
      expect(dataImportada('31/02/2021'), isNull);
      expect(dataImportada('5/3/21'), '2021-03-05');
    });

    test('confere linhas e aponta erros', () async {
      await Db.inserir('animais', {'propriedade_id': pid, 'brinco': '50', 'sexo': 'F', 'status': 'Ativo'});
      await Db.inserir('lotes', {'propriedade_id': pid, 'nome': 'Desmama'});
      const csv = 'Brinco;Sexo;Raça;Nascimento;Peso;Lote;Mãe\n'
          '101;F;Nelore;15/03/2021;420;;\n'
          '102;Macho;Nelore;10/08/2025;180,5;desmama;101\n'
          '101;F;;;;;\n'
          '50;F;;;;;\n'
          ';M;;;;;\n'
          '103;X;;99/99/2020;abc;Inexistente;\n';
      final c = conferirImportacao(csv, propriedadeId: pid, hoje: '2026-10-18');
      expect(c.erroGeral, isNull);
      expect(c.linhas, hasLength(6));
      expect(c.boas.map((l) => l.brinco), ['101', '102']);
      final l102 = c.linhas[1];
      expect(l102.animal['sexo'], 'M');
      expect(l102.peso, 180.5);
      expect(l102.animal['lote_id'], isNotNull);
      expect(c.linhas[2].erros.single, contains('repetido'));
      expect(c.linhas[3].erros.single, contains('Já existe'));
      expect(c.linhas[4].erros, contains('Sem brinco.'));
      expect(c.linhas[5].erros, hasLength(3));
      expect(c.linhas[5].avisos.single, contains('Inexistente'));

      final n = await gravarImportacao(c, propriedadeId: pid);
      expect(n, 2);
      final cria = Db.registros('animais').firstWhere((a) => a['brinco'] == '102');
      final mae = Db.registros('animais').firstWhere((a) => a['brinco'] == '101');
      expect(cria['mae_id'], mae['id']);
      expect(Db.registros('pesagens'), hasLength(2));
    });

    test('sem coluna de brinco dá erro geral', () {
      final c = conferirImportacao('nome;sexo\nA;F', propriedadeId: pid);
      expect(c.erroGeral, contains('brinco'));
    });
  });

  group('patrimônio', () {
    test('soma rebanho, terra e bens e desconta dívidas', () async {
      await Db.atualizar('propriedades', pid, {'area_pastagem': 90, 'area_app': 10});
      for (final b in ['1', '2', '3']) {
        await Db.inserir('animais', {'propriedade_id': pid, 'brinco': b, 'sexo': 'F', 'categoria': 'Vaca', 'status': 'Ativo'});
      }
      await Db.inserir('animais', {'propriedade_id': pid, 'brinco': '9', 'sexo': 'M', 'categoria': 'Boi', 'status': 'Vendido'});
      await salvarPatrimonio(
        precos: {'Vaca': 3000},
        terra: {'$pid': 10000},
        listaBens: [
          {'nome': 'Trator', 'tipo': 'Máquinas e implementos', 'valor': 150000},
        ],
      );
      await Db.inserir('dividas', {
        'descricao': 'Financiamento',
        'parcelas': [
          {'valor': 20000, 'pago': false},
          {'valor': 20000, 'pago': true},
        ],
      });
      final p = calcularPatrimonio();
      expect(p.cabecas, 3);
      expect(p.totalRebanho, 9000);
      expect(p.totalTerra, 1000000);
      expect(p.totalBens, 150000);
      expect(p.dividas, 20000);
      expect(p.liquido, 9000 + 1000000 + 150000 - 20000);
      expect(p.semPreco, isEmpty);
    });
  });

  test('situação da conta', () {
    expect(situacaoConta({'status': 'suspensa'}), 'Suspensa');
    expect(situacaoConta({'plano': 'Essencial'}), 'Essencial');
    expect(situacaoConta({'plano': 'Teste', 'teste_ate': DateTime(2000, 1, 2)}), startsWith('Teste vencido'));
  });
}
