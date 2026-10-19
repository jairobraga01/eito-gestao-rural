import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/planos.dart';
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

  Future<void> animais(int n) async {
    for (var i = 0; i < n; i++) {
      await Db.inserir('animais', {'propriedade_id': pid, 'brinco': 'A$i', 'sexo': 'F', 'status': 'Ativo'});
    }
    await pumpEventQueue();
  }

  test('nomes de plano e papéis permitidos', () {
    expect(PlanoEito.de('Essencial'), PlanoEito.simples);
    expect(PlanoEito.de('Profissional'), PlanoEito.media);
    expect(PlanoEito.de('Completa'), PlanoEito.plus);
    expect(PlanoEito.de('Teste').maxAnimais, isNull);
    expect(PlanoEito.de('Cortesia').permite('contador'), isTrue);
    expect(PlanoEito.simples.permite('veterinario'), isFalse);
    expect(PlanoEito.media.permite('zootecnista'), isFalse);
    expect(PlanoEito.plus.permite('contador'), isTrue);
    expect(PlanoEito.media.cabe('peao', {'peao': 1}), isTrue);
    expect(PlanoEito.media.cabe('peao', {'peao': 2}), isFalse);
    expect(PlanoEito.simples.cabe('peao', {'peao': 1}), isFalse);
    expect(PlanoEito.plus.cabe('peao', {'peao': 9}), isTrue);
  });

  test('preços de tabela', () {
    expect(PlanoEito.todos.map((p) => '${p.nome} ${p.mes} ${p.ano}'),
        ['Simples 9,90 99,90', 'Média 29,90 299,90', 'Plus 59,90 599,90']);
  });

  test('situação do rebanho pelo limite do plano', () {
    expect(PlanoEito.simples.situacao(150), 'ok');
    expect(PlanoEito.simples.situacao(180), 'perto');
    expect(PlanoEito.simples.situacao(200), 'perto');
    expect(PlanoEito.simples.situacao(201), 'acima');
    expect(PlanoEito.plus.situacao(5000), 'ok');
  });

  test('passar do limite começa a contar; trava só depois de 15 dias', () async {
    Db.planoDaFazenda.value = 'Simples';
    await animais(201);
    expect(bloqueioDeAnimais('2026-10-19'), isNull); // cruzou agora: só avisa
    await conferirLimiteAnimais('2026-10-19');
    await pumpEventQueue();
    expect(diasParaTravar('2026-10-19'), 15);
    expect(bloqueioDeAnimais('2026-10-30'), isNull);
    expect(diasParaTravar('2026-10-30'), 4);
    expect(bloqueioDeAnimais('2026-11-04'), isNotNull);
  });

  test('sem plano definido (teste) nada é travado', () async {
    Db.planoDaFazenda.value = 'Teste';
    await animais(3);
    expect(bloqueioDeAnimais('2026-10-19', novos: 5000), isNull);
    expect(planoAtual().completo, isTrue);
  });
}
