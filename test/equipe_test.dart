import 'dart:math';

import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/equipe.dart';
import 'package:eito_gestao_rural/dados/historico.dart';
import 'package:eito_gestao_rural/dados/tarefas.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore banco;

  setUp(() async {
    banco = FakeFirebaseFirestore();
    Db.bancoTeste = banco;
  });

  tearDown(Db.encerrar);

  test('login de peão vira e-mail e o usuário sai do nome', () {
    expect(emailDoLogin('Joao1234'), 'joao1234@$dominioPeao');
    expect(emailDoLogin('ze@gmail.com'), 'ze@gmail.com');
    expect(ehLoginDePeao('joao1234@$dominioPeao'), isTrue);
    expect(usuarioPeao('José da Silva', Random(1)), matches(RegExp(r'^jose\d{4}$')));
    expect(usuarioPeao('!!', Random(1)), startsWith('peao'));
  });

  test('cada lançamento guarda quem lançou e quem alterou', () async {
    await Db.iniciar('dono', nome: 'Jairo');
    final a = await Db.inserir('animais', {'propriedade_id': Db.pid, 'brinco': '7', 'status': 'Ativo'});
    var r = Db.registro('animais', a)!;
    expect(r['criado_por'], 'dono');
    expect(r['criado_nome'], 'Jairo');
    expect(r['alterado_por'], isNull);

    Db.autor = (uid: 'p1', nome: 'Zé');
    await pumpEventQueue();
    await Db.atualizar('animais', a, {'brinco': '8'});
    await pumpEventQueue();
    r = Db.registro('animais', a)!;
    expect(r['criado_nome'], 'Jairo');
    expect(r['alterado_nome'], 'Zé');

    await Db.salvarConfig('teste', {'x': 1});
    expect(Db.registro('config', 'teste')!['criado_por'], isNull);

    final l = lancamentos();
    expect(l.where((x) => x.tabela == 'animais').single.quem, 'Zé');
    expect(lancamentos(uid: 'p1').length, 1);
    expect(lancamentos(uid: 'dono').map((x) => x.tabela), isNot(contains('animais')));
  });

  test('convite liga a pessoa aos dados do dono; peão não lê o financeiro', () async {
    await Db.iniciar('dono', nome: 'Jairo');
    final pid = Db.pid;
    await Db.inserir('animais', {'propriedade_id': pid, 'brinco': '1', 'status': 'Ativo'});
    await Db.inserir('contas', {'propriedade_id': pid, 'descricao': 'Luz', 'valor': 100});
    await Equipe.convidar(dono: 'dono', donoNome: 'Jairo', email: 'Ze@Gmail.com', nome: 'Zé', papel: 'peao');
    await Db.encerrar();

    final acesso = await Equipe.procurarAcesso('ze', 'ze@gmail.com');
    expect(acesso?.dono, 'dono');
    expect(acesso?.papel, 'peao');
    expect((await banco.doc('usuarios/dono/equipe/ze').get()).data()?['papel'], 'peao');

    await Db.iniciar('ze', dono: acesso!.dono, papel: acesso.papel, nome: acesso.nome);
    expect(Db.ehPeao, isTrue);
    expect(Db.pid, pid);
    expect(Db.registros('animais').length, 1);
    expect(Db.registros('contas'), isEmpty);

    final membros = await Equipe.membros('dono');
    expect(membros.single.uid, 'ze');
    await Equipe.remover('dono', membros.single);
    expect(await Equipe.membros('dono'), isEmpty);
    expect(await Equipe.procurarAcesso('ze', 'ze@gmail.com'), isNull);
  });

  test('sem convite a pessoa usa os próprios dados', () async {
    expect(await Equipe.procurarAcesso('outro', 'outro@gmail.com'), isNull);
  });

  test('tarefas: as do peão, atrasadas e concluídas', () async {
    await Db.iniciar('dono', nome: 'Jairo');
    final a = await salvarTarefa({'titulo': 'Cerca', 'responsavel': 'p1', 'prazo': '2026-10-01'});
    await salvarTarefa({'titulo': 'Cocho', 'responsavel': 'p2'});
    await salvarTarefa({'titulo': 'Aguada'});
    expect(tarefas(feitas: false, paraUid: 'p1').map((t) => t['titulo']), ['Cerca', 'Aguada']);
    expect(tarefaAtrasada(Db.registro('tarefas', a)!, '2026-10-15'), isTrue);
    await concluirTarefa(a, true);
    await pumpEventQueue();
    expect(tarefas(feitas: true).single['feita_nome'], 'Jairo');
    expect(tarefaAtrasada(Db.registro('tarefas', a)!, '2026-10-15'), isFalse);
  });
}
