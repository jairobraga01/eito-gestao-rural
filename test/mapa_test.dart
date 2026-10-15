import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/mapa.dart';
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

  // Quadrado de ~1 km x 1 km perto de Goianésia (≈ 100 ha).
  final quadrado = <Ponto>[
    (lat: -15.3000, lng: -49.1000),
    (lat: -15.3000, lng: -49.0907),
    (lat: -15.2910, lng: -49.0907),
    (lat: -15.2910, lng: -49.1000),
  ];

  test('área do contorno e ponto dentro do piquete', () async {
    expect(areaHa(quadrado), closeTo(100, 2));
    final q = await Db.inserir('piquetes', {'propriedade_id': pid, 'nome': 'P1', 'contorno': contornoParaSalvar(quadrado)});
    expect(piqueteNoPonto((lat: -15.295, lng: -49.095))?['id'], q);
    expect(piqueteNoPonto((lat: -15.200, lng: -49.095)), isNull);
  });

  test('lotação usa a pesagem ou o peso da categoria', () async {
    final q = await Db.inserir('piquetes', {'propriedade_id': pid, 'nome': 'P1', 'area': 2});
    final a = await Db.inserir(
        'animais', {'propriedade_id': pid, 'brinco': '1', 'status': 'Ativo', 'piquete_id': q, 'categoria': 'Boi'});
    await Db.inserir('animais',
        {'propriedade_id': pid, 'brinco': '2', 'status': 'Ativo', 'piquete_id': q, 'categoria': 'Vaca'});
    await Db.inserir('pesagens', {'animal_id': a, 'data': '2026-10-01', 'peso': 450});
    final l = lotacaoPiquetes()[q]!;
    expect(l.cabecas, 2);
    expect(l.estimados, 1);
    expect(l.ua, 2);
    expect(l.uaHa, 1);
  });

  test('rodízio avisa a troca e o descanso cumprido', () async {
    final ocupado = await Db.inserir('piquetes', {'propriedade_id': pid, 'nome': 'A', 'dias_ocupacao': 5});
    final vazio = await Db.inserir('piquetes', {'propriedade_id': pid, 'nome': 'B', 'dias_descanso': 20});
    final boi = await Db.inserir('animais', {'propriedade_id': pid, 'brinco': '1', 'status': 'Ativo'});
    final r = Db.registro('animais', boi)!;
    await Db.moverParaPiquete([r], ocupado, '2026-10-01');
    await Db.inserir('pastagens', {'piquete_id': vazio, 'data': '2026-09-20', 'tipo': 'Saída de animais'});
    await pumpEventQueue(); // deixa chegar os avisos do banco
    final rod = {for (final x in rodizio('2026-10-15')) x.piquete['id']: x};
    expect(rod[ocupado]!.situacao, SituacaoPasto.trocar);
    expect(rod[ocupado]!.dias, 14);
    expect(rod[vazio]!.situacao, SituacaoPasto.pronto);
  });

  test('contagem guarda o esperado e o contado', () async {
    final q = await Db.inserir('piquetes', {'propriedade_id': pid, 'nome': 'P1'});
    await Db.inserir('animais', {'propriedade_id': pid, 'brinco': '1', 'status': 'Ativo', 'piquete_id': q});
    await registrarContagem(q, '2026-10-15', 3);
    final c = contagens().single;
    expect(c['esperado'], 1);
    expect(c['contado'], 3);
  });

  test('ocorrência resolvida sai das abertas e é apagada com o ponto mantido', () async {
    final ponto = await salvarPonto({'tipo': 'Aguada', 'nome': 'Córrego', 'lat': -15.29, 'lng': -49.09});
    final o = await salvarOcorrencia({'tipo': 'Aguada / bebedouro', 'data': '2026-10-15', 'ponto_id': ponto});
    expect(ocorrencias(soAbertas: true, pontoId: ponto).length, 1);
    await pumpEventQueue();
    await resolverOcorrencia(o, true, '2026-10-16');
    await pumpEventQueue();
    expect(ocorrencias(soAbertas: true), isEmpty);
    await Db.excluir('pontos', ponto);
    await pumpEventQueue();
    expect(Db.registro('ocorrencias', o)?['ponto_id'], isNull);
  });
}
