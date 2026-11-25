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
    expect(PlanoEito.simples.cabe('peao', {}), isFalse);
    expect(PlanoEito.simplesPro.cabe('peao', {'peao': 1}), isFalse);
    expect(PlanoEito.plus.cabe('peao', {'peao': 9}), isTrue);
  });

  test('preços de tabela', () {
    expect(PlanoEito.todos.map((p) => '${p.nome} ${p.mes} ${p.ano}'),
        ['Simples 9,90 99,90', 'Simples PRO 19,90 199,90', 'Média 29,90 299,90', 'Plus 59,90 599,90']);
    expect(PlanoEito.todos.map((p) => p.maxAnimais), [100, 100, 300, null]);
  });

  test('versão simples só no Fazenda Simples', () {
    expect(PlanoEito.simples.completo, isFalse);
    expect(PlanoEito.de('Simples PRO'), PlanoEito.simplesPro);
    expect(PlanoEito.simplesPro.completo, isTrue);
    expect(PlanoEito.media.completo, isTrue);
    expect(PlanoEito.plus.completo, isTrue);
    expect(PlanoEito.de('Cortesia').completo, isTrue);
    expect(PlanoEito.simples.titulo, 'Fazenda Simples');
    expect(PlanoEito.simples.resumoEquipe, 'só o dono');
    expect(PlanoEito.simplesPro.resumoEquipe, '1 gerente, 1 peão');
    expect(PlanoEito.media.resumoEquipe, '1 gerente, 1 veterinário, 2 peões');
  });

  test('situação do rebanho pelo limite do plano', () {
    expect(PlanoEito.simples.situacao(80), 'ok');
    expect(PlanoEito.simples.situacao(90), 'perto');
    expect(PlanoEito.simples.situacao(100), 'perto');
    expect(PlanoEito.simples.situacao(101), 'acima');
    expect(PlanoEito.media.situacao(301), 'acima');
    expect(PlanoEito.plus.situacao(5000), 'ok');
  });

  test('passar do limite começa a contar; trava só depois de 15 dias', () async {
    Db.planoDaFazenda.value = 'Simples';
    await animais(101);
    expect(bloqueioDeAnimais('2026-10-19'), isNull); // cruzou agora: só avisa
    await conferirLimiteAnimais('2026-10-19');
    await pumpEventQueue();
    expect(diasParaTravar('2026-10-19'), 15);
    expect(bloqueioDeAnimais('2026-10-30'), isNull);
    expect(diasParaTravar('2026-10-30'), 4);
    expect(bloqueioDeAnimais('2026-11-04'), isNotNull);
  });

  test('cadastro em lote não passa muito do limite do plano', () async {
    Db.planoDaFazenda.value = 'Simples';
    await animais(99);
    expect(bloqueioDeAnimais('2026-10-19', novos: 5000), isNotNull);
    expect(bloqueioDeAnimais('2026-10-19', novos: 11), isNull); // 110 = folga de 10%
    expect(bloqueioDeAnimais('2026-10-19', novos: 12), isNotNull);
  });

  test('sem plano definido (teste) nada é travado', () async {
    Db.planoDaFazenda.value = 'Teste';
    await animais(3);
    expect(bloqueioDeAnimais('2026-10-19', novos: 5000), isNull);
    expect(planoAtual().completo, isTrue);
  });

  test('teste na versão escolhida no cadastro; vencido cai no Fazenda Simples', () {
    final hoje = DateTime(2026, 11, 25);
    final criado = DateTime(2026, 11, 20);
    Map<String, dynamic> conta(String? versao) =>
        {'plano': 'Teste', 'criado_em': criado, 'versao': ?versao};
    expect(planoEfetivo(conta('simples'), hoje), testeVersaoSimples);
    expect(PlanoEito.de(planoEfetivo(conta('simples'), hoje)).completo, isFalse);
    expect(PlanoEito.de(planoEfetivo(conta('simples'), hoje)).maxAnimais, isNull);
    expect(planoEfetivo(conta('completa'), hoje), 'Teste');
    expect(PlanoEito.de(planoEfetivo(conta('completa'), hoje)).completo, isTrue);
    expect(planoEfetivo(conta(null), hoje), 'Teste'); // contas antigas: completa
    expect(emTeste(conta('simples'), hoje), isTrue);
    final depois = DateTime(2026, 12, 21);
    expect(planoEfetivo(conta('completa'), depois), 'Simples');
    expect(emTeste(conta('completa'), depois), isFalse);
  });
}
