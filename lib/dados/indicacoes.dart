// Códigos de indicação (veterinário, zootecnista, lojista, vendedor).
// - indicacoes/{codigo}: nome, tipo e ativo. Quem cria a conta só confere o
//   código que digitou; a lista inteira só o administrador vê.
// - admins/{uid}: quem administra os códigos (criado à mão no console).
// - usuarios/{uid}: guarda indicacao, tipo e desconto de quem usou um código.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'db.dart';

/// Desconto, em %, para quem assina com um código de indicação.
const descontoIndicacao = 20;

const tiposIndicacao = {
  'veterinario': 'Veterinário',
  'zootecnista': 'Zootecnista',
  'lojista': 'Lojista',
  'vendedor': 'Vendedor',
};

/// Código sem espaços e em minúsculas: " Carol Nutroeste " vira "carolnutroeste".
String codigoIndicacao(String digitado) => digitado.replaceAll(RegExp(r'\s+'), '').toLowerCase();

class Indicacao {
  const Indicacao({required this.codigo, required this.nome, required this.tipo, this.ativo = true});
  final String codigo;
  final String nome;
  final String tipo;
  final bool ativo;

  String get tipoNome => tiposIndicacao[tipo] ?? tipo;

  factory Indicacao.de(String codigo, Map<String, dynamic> d) => Indicacao(
        codigo: codigo,
        nome: (d['nome'] ?? '') as String,
        tipo: (d['tipo'] ?? '') as String,
        ativo: d['ativo'] != false,
      );

  Map<String, dynamic> get dados => {'nome': nome, 'tipo': tipo, 'ativo': ativo};
}

class Indicacoes {
  Indicacoes._();

  static FirebaseFirestore get _banco => Db.banco;
  static CollectionReference<Map<String, dynamic>> get _codigos => _banco.collection('indicacoes');

  /// O código ativo, ou null quando não existe (ou foi desativado).
  static Future<Indicacao?> buscar(String digitado) async {
    final codigo = codigoIndicacao(digitado);
    if (codigo.isEmpty || codigo.contains('/')) return null;
    final d = await _codigos.doc(codigo).get(const GetOptions(source: Source.server));
    if (!d.exists) return null;
    final i = Indicacao.de(codigo, d.data()!);
    return i.ativo ? i : null;
  }

  /// Guarda no perfil de quem acabou de criar a conta qual código usou.
  static Future<void> registrarAdesao(String uid, String? email, Indicacao i) =>
      _banco.collection('usuarios').doc(uid).set({
        'indicacao': i.codigo,
        'indicacao_tipo': i.tipo,
        'desconto': descontoIndicacao,
        'email': email,
        'criadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  static bool? _admin;
  static String? _adminUid; // de quem é a resposta guardada em _admin

  static const emailDoCriador = 'eitogestaorural@gmail.com';

  /// Se quem está logado é o criador ou administrador (admins/{uid} existe e
  /// não está com ativo: false). A resposta guardada vale só para o mesmo login.
  static Future<bool> souAdmin() async {
    final u = FirebaseAuth.instance.currentUser;
    final uid = u?.uid;
    if (uid == null) return false;
    try {
      if (_admin != null && _adminUid == uid) return _admin!;
      final ref = _banco.collection('admins').doc(uid);
      final doc = await ref.get();
      var existe = doc.exists && doc.data()?['ativo'] != false;
      // A conta do criador se registra sozinha (as regras só deixam o e-mail dele, confirmado).
      if (!doc.exists && u!.emailVerified && u.email == emailDoCriador) {
        await ref.set({'ativo': true, 'email': u.email});
        existe = true;
      }
      _adminUid = uid;
      return _admin = existe;
    } catch (_) {
      return false; // sem permissão: não é administrador
    }
  }

  static void esquecerAdmin() {
    _admin = null;
    _adminUid = null;
  }

  static Future<List<Indicacao>> todas() async {
    final q = await _codigos.get();
    final l = [for (final d in q.docs) Indicacao.de(d.id, d.data())];
    l.sort((a, b) => a.codigo.compareTo(b.codigo));
    return l;
  }

  /// Cria ou altera um código. Devolve false quando o código já é de outra pessoa.
  static Future<bool> salvar(Indicacao i, {bool novo = false}) async {
    final ref = _codigos.doc(i.codigo);
    if (novo && (await ref.get()).exists) return false;
    await ref.set(i.dados);
    return true;
  }

  static Future<void> apagar(String codigo) => _codigos.doc(codigo).delete();

  /// Quantas contas foram criadas com o código.
  static Future<int> adesoes(String codigo) async {
    final q = await _banco.collection('usuarios').where('indicacao', isEqualTo: codigo).count().get();
    return q.count ?? 0;
  }

  /// Código de indicação usado por cada conta (uid → código).
  static Future<Map<String, String>> codigoPorConta() async {
    final q = await _banco.collection('usuarios').where('indicacao', isGreaterThan: '').get();
    return {for (final d in q.docs) d.id: '${d.data()['indicacao']}'};
  }
}
