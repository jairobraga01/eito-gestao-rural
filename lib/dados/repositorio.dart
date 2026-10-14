import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Um animal do rebanho. Documento em usuarios/{uid}/animais/{id}.
class Animal {
  const Animal({
    required this.id,
    required this.brinco,
    required this.sexo,
    required this.status,
    this.rfid,
    this.nome,
    this.raca,
    this.lote,
    this.nascimento,
    this.pesoAtual,
    this.dataUltimoPeso,
  });

  final String id;
  final String brinco; // número do brinco visual
  final String? rfid; // brinco eletrônico (bastão)
  final String? nome;
  final String sexo; // 'F' ou 'M'
  final String? raca;
  final String? lote;
  final DateTime? nascimento;
  final double? pesoAtual;
  final DateTime? dataUltimoPeso;
  final String status; // ativo, vendido, morto, descartado

  bool get femea => sexo == 'F';

  factory Animal.doDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return Animal(
      id: d.id,
      brinco: (m['brinco'] as String?) ?? '',
      rfid: m['rfid'] as String?,
      nome: m['nome'] as String?,
      sexo: (m['sexo'] as String?) ?? 'F',
      raca: m['raca'] as String?,
      lote: m['lote'] as String?,
      nascimento: (m['nascimento'] as Timestamp?)?.toDate(),
      pesoAtual: (m['pesoAtual'] as num?)?.toDouble(),
      dataUltimoPeso: (m['dataUltimoPeso'] as Timestamp?)?.toDate(),
      status: (m['status'] as String?) ?? 'ativo',
    );
  }
}

/// Um lançamento (pesagem, sanidade, cadastro, saída).
/// Documento em usuarios/{uid}/eventos/{id}.
class Evento {
  const Evento({required this.id, required this.tipo, required this.data, required this.dados});
  final String id;
  final String tipo;
  final DateTime data;
  final Map<String, dynamic> dados;

  factory Evento.doDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return Evento(
      id: d.id,
      tipo: (m['tipo'] as String?) ?? '',
      data: (m['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dados: m,
    );
  }
}

/// Acesso aos dados de UM usuário. Tudo fica em usuarios/{uid}/...,
/// que é exatamente o que as regras do Firestore liberam.
///
/// Gravações NÃO usam await de propósito: sem sinal, o Future só termina
/// quando a nuvem confirma, e o peão não pode ficar esperando. O Firestore
/// grava na hora no aparelho e envia sozinho quando a internet voltar.
class Repositorio {
  Repositorio(this.uid);
  final String uid;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _raiz =>
      _db.collection('usuarios').doc(uid);
  CollectionReference<Map<String, dynamic>> get animais =>
      _raiz.collection('animais');
  CollectionReference<Map<String, dynamic>> get eventos =>
      _raiz.collection('eventos');

  static void _erro(Object e, StackTrace s) => debugPrint('Eito: falha ao gravar: $e');

  // ---------- Leitura ----------

  /// Busca pelo brinco eletrônico (RFID) ou pelo número do brinco visual.
  /// Responde na hora com o que já está no aparelho, mesmo sem internet.
  Future<Animal?> buscarPorCodigo(String codigo) async {
    final c = codigo.trim();
    if (c.isEmpty) return null;
    for (final campo in ['rfid', 'brinco']) {
      final q = await _consultar(animais.where(campo, isEqualTo: c).limit(1));
      if (q.docs.isNotEmpty) return Animal.doDoc(q.docs.first);
    }
    return null;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _consultar(
      Query<Map<String, dynamic>> q) async {
    try {
      final cache = await q.get(const GetOptions(source: Source.cache));
      if (cache.docs.isNotEmpty) return cache;
    } catch (_) {/* cache ainda vazio */}
    try {
      return await q.get().timeout(const Duration(seconds: 6));
    } catch (_) {
      return q.get(const GetOptions(source: Source.cache));
    }
  }

  Stream<List<Animal>> rebanhoAtivo() => animais
      .where('status', isEqualTo: 'ativo')
      .snapshots()
      .map((s) => s.docs.map(Animal.doDoc).toList());

  Stream<Animal?> animal(String id) =>
      animais.doc(id).snapshots().map((d) => d.exists ? Animal.doDoc(d) : null);

  Stream<List<Evento>> historico(String animalId) => eventos
      .where('animalId', isEqualTo: animalId)
      .snapshots()
      .map((s) => s.docs.map(Evento.doDoc).toList()..sort((a, b) => b.data.compareTo(a.data)));

  /// Quantos lançamentos ainda estão só no aparelho, esperando sinal.
  Stream<int> pendentes() => eventos
      .orderBy('data', descending: true)
      .limit(500)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.where((d) => d.metadata.hasPendingWrites).length);

  // ---------- Gravação ----------

  void _evento(String tipo, String animalId, String brinco, Map<String, dynamic> dados) {
    eventos.doc().set({
      'tipo': tipo,
      'animalId': animalId,
      'brinco': brinco,
      ...dados,
      'data': Timestamp.fromDate(DateTime.now()),
      'criadoEm': FieldValue.serverTimestamp(),
    }).catchError(_erro);
  }

  String novoAnimal({
    required String brinco,
    required String sexo,
    String? rfid,
    String? nome,
    String? raca,
    String? lote,
    DateTime? nascimento,
    double? peso,
  }) {
    String? limpo(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    final ref = animais.doc();
    final agora = Timestamp.fromDate(DateTime.now());
    ref.set({
      'brinco': brinco.trim(),
      'rfid': limpo(rfid),
      'nome': limpo(nome),
      'sexo': sexo,
      'raca': limpo(raca),
      'lote': limpo(lote),
      'nascimento': nascimento == null ? null : Timestamp.fromDate(nascimento),
      'pesoAtual': peso,
      'dataUltimoPeso': peso == null ? null : agora,
      'status': 'ativo',
      'criadoEm': FieldValue.serverTimestamp(),
    }).catchError(_erro);
    _evento('cadastro', ref.id, brinco.trim(), {if (peso != null) 'peso': peso});
    return ref.id;
  }

  /// Registra a pesagem e calcula o ganho médio diário (GMD) desde a anterior.
  double? registrarPeso(Animal a, double peso) {
    final agora = DateTime.now();
    double? gmd;
    if (a.pesoAtual != null && a.dataUltimoPeso != null) {
      final dias = agora.difference(a.dataUltimoPeso!).inHours / 24;
      if (dias >= 1) gmd = (peso - a.pesoAtual!) / dias;
    }
    animais.doc(a.id).update({
      'pesoAtual': peso,
      'dataUltimoPeso': Timestamp.fromDate(agora),
    }).catchError(_erro);
    _evento('pesagem', a.id, a.brinco, {
      'peso': peso,
      if (a.pesoAtual != null) 'pesoAnterior': a.pesoAtual,
      if (gmd != null) 'gmd': gmd,
    });
    return gmd;
  }

  void registrarSanidade(Animal a, String produto, {String? dose}) =>
      _evento('sanidade', a.id, a.brinco, {
        'produto': produto.trim(),
        if (dose != null && dose.trim().isNotEmpty) 'dose': dose.trim(),
      });

  void vincularRfid(Animal a, String rfid) {
    animais.doc(a.id).update({'rfid': rfid.trim()}).catchError(_erro);
    _evento('rfid', a.id, a.brinco, {'rfid': rfid.trim()});
  }

  /// motivo: vendido, morto ou descartado.
  void registrarSaida(Animal a, String motivo, {String? observacao}) {
    animais.doc(a.id).update({'status': motivo}).catchError(_erro);
    _evento('saida', a.id, a.brinco, {
      'motivo': motivo,
      if (observacao != null && observacao.trim().isNotEmpty) 'observacao': observacao.trim(),
    });
  }
}
