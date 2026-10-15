// Dados do Eito no Firestore, em usuarios/{uid}/{tabela}/{id}.
// Quem entra pela equipe (gerente ou peão) usa os dados do dono: usuarios/{dono}.
//
// Como funciona:
// - Ao entrar, o app "escuta" todas as tabelas do usuário. O Firestore guarda
//   uma cópia no aparelho (IndexedDB), então tudo abre e funciona sem sinal.
// - As telas leem de uma cópia em memória (rápida) e se atualizam sozinhas
//   quando algo muda, inclusive quando outro aparelho (iPhone/computador) grava.
// - Gravações NÃO esperam a nuvem: vão para o aparelho na hora e o Firestore
//   envia sozinho quando houver internet. [pendentes] mostra quantas faltam.
//
// As funções têm os mesmos nomes da Caderneta do Rebanho (versão SQLite),
// para as telas continuarem iguais. As antigas consultas SQL viraram Dart.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

typedef Reg = Map<String, Object?>;

/// Duração média da gestação bovina (dias). Zebuínos (Nelore) ~290; taurinos ~283.
const diasGestacao = 290;

/// Situação do animal conforme o tipo de saída.
const statusPorSaida = {
  'Venda': 'Vendido',
  'Morte': 'Morto',
  'Consumo': 'Consumido',
  'Transferência': 'Transferido',
  'Doação': 'Doado',
};

String _hoje() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Tentativa de gravar um brinco (ou brinco eletrônico) que já existe.
class RegistroDuplicado implements Exception {
  const RegistroDuplicado(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Campos que guardam números inteiros (ids e contagens).
const _camposInteiros = {
  'id',
  'propriedade_id',
  'lote_id',
  'piquete_id',
  'mae_id',
  'saida_id',
  'entrada_id',
  'femea_id',
  'cria_id',
  'animal_id',
  'semen_id',
  'protocolo_id',
  'origem_id',
  'rodada',
  'ordem',
  'dias_parida',
  'dg_dias',
  'ponto_id',
  'esperado',
  'contado',
  'tipo_doc',
  'conta_banco',
  'doses',
  'quantidade',
  'carencia',
  'propriedade',
};

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

int _comparaNome(Object? a, Object? b) =>
    '${a ?? ''}'.toLowerCase().compareTo('${b ?? ''}'.toLowerCase());

/// Compara textos de data (ISO) como o SQLite: nulos por último.
int _comparaDataDesc(Object? a, Object? b) {
  final x = a?.toString(), y = b?.toString();
  if (x == null && y == null) return 0;
  if (x == null) return 1;
  if (y == null) return -1;
  return y.compareTo(x);
}

int _comparaId(Object? a, Object? b) => (_int(a) ?? 0).compareTo(_int(b) ?? 0);

bool _iguais(Reg? a, Reg b) {
  if (a == null || a.length != b.length) return false;
  for (final e in b.entries) {
    if (!a.containsKey(e.key) || a[e.key] != e.value) return false;
  }
  return true;
}

Reg _normalizar(Map<String, dynamic> m) {
  final r = <String, Object?>{};
  m.forEach((k, v) {
    if (_camposInteiros.contains(k) && v is num) {
      r[k] = v.toInt();
    } else if (v is Timestamp) {
      r[k] = v.toDate().toIso8601String();
    } else {
      r[k] = v;
    }
  });
  return r;
}

/// Junta gravações: atualiza a cópia em memória na hora e manda para o
/// Firestore em lotes (o Firestore aceita até 500 operações por lote).
class _Mudancas {
  final _ops = <(String, String, Reg?, bool)>[]; // tabela, id do doc, valores (null = apagar), mesclar

  void gravar(String tabela, Reg v) {
    final id = '${v['id']}';
    v = Db._carimbar(tabela, Db._dados[tabela]?[id], v);
    Db._dados[tabela]?[id] = Map.of(v);
    _ops.add((tabela, id, Map.of(v), false));
  }

  void mesclar(String tabela, Object id, Reg v) {
    final atual = Db._dados[tabela]?['$id'];
    if (atual == null) return; // registro já não existe
    v = Db._carimbar(tabela, atual, v, mesclando: true);
    Db._dados[tabela]!['$id'] = {...atual, ...v};
    _ops.add((tabela, '$id', Map.of(v), true));
  }

  /// Soma [delta] a um campo numérico. Na nuvem vai como incremento, para
  /// não perder baixas feitas em sequência ou em dois aparelhos.
  void somar(String tabela, Object id, String campo, int delta) {
    final atual = Db._dados[tabela]?['$id'];
    if (atual == null) return;
    Db._dados[tabela]!['$id'] = {...atual, campo: (_int(atual[campo]) ?? 0) + delta};
    _ops.add((tabela, '$id', {campo: FieldValue.increment(delta)}, true));
  }

  void apagar(String tabela, Object id) {
    Db._dados[tabela]?.remove('$id');
    _ops.add((tabela, '$id', null, false));
  }

  void enviar() {
    const porLote = 450;
    for (var i = 0; i < _ops.length; i += porLote) {
      final b = Db._banco.batch();
      for (final (t, id, v, merge) in _ops.skip(i).take(porLote)) {
        final ref = Db._col(t).doc(id);
        if (v == null) {
          b.delete(ref);
        } else {
          b.set(ref, v, SetOptions(merge: merge));
        }
      }
      // Sem await de propósito: sem sinal, o Future só termina quando a nuvem
      // confirmar. O dado já está gravado no aparelho.
      b.commit().catchError((Object e) => debugPrint('Eito: falha ao gravar: $e'));
    }
    _ops.clear();
    Db._avisar();
  }
}

class Db {
  Db._();

  /// Ordem respeita as ligações (pais antes dos filhos).
  static const tabelas = [
    'propriedades',
    'lotes',
    'piquetes',
    'pastagens',
    'pontos',
    'ocorrencias',
    'contagens',
    'saidas',
    'entradas',
    'semens',
    'protocolos',
    'custos',
    'chuvas',
    'insumos',
    'formulas',
    'dividas',
    'contas',
    'cotacoes',
    'estoque',
    'dietas',
    'tarefas',
    'animais',
    'reproducoes',
    'sanidade',
    'pesagens',
    'escores',
    'ordenhas',
    'config',
  ];

  /// Dono dos dados abertos (o próprio usuário ou quem o pôs na equipe).
  static String? _uid;

  /// Papel de quem está usando: 'dono', 'gerente', 'peao' ou 'veterinario'.
  static final papel = ValueNotifier<String>('dono');
  static bool get ehDono => papel.value == 'dono';
  static bool get ehPeao => papel.value == 'peao';
  static bool get ehVeterinario => papel.value == 'veterinario';

  /// Peão e veterinário: não veem o financeiro nem os cadastros da fazenda.
  static bool get ehCampo => ehPeao || ehVeterinario;

  /// Quem está lançando. Vai gravado em cada registro (quem lançou o quê).
  static ({String uid, String nome})? autor;

  /// Tabelas que o peão e o veterinário não leem (financeiro). As regras do Firestore bloqueiam.
  static const tabelasSemPeao = {'contas', 'dividas', 'custos'};

  /// Marca quem lançou (registro novo) ou quem alterou (registro existente).
  static Reg _carimbar(String tabela, Reg? atual, Reg v, {bool mesclando = false}) {
    final a = autor;
    if (a == null || tabela == 'config') return v;
    final agora = DateTime.now().toIso8601String();
    if (atual == null && !mesclando) {
      return {...v, 'criado_por': a.uid, 'criado_nome': a.nome, 'criado_em': agora};
    }
    return {
      ...v,
      if (!mesclando && atual?['criado_por'] != null) ...{
        'criado_por': atual!['criado_por'],
        'criado_nome': atual['criado_nome'],
        'criado_em': atual['criado_em'],
      },
      'alterado_por': a.uid,
      'alterado_nome': a.nome,
      'alterado_em': agora,
    };
  }
  static final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs = [];
  static final Map<String, Map<String, Reg>> _dados = {};
  static final Map<String, int> _pendentesPorTabela = {};

  /// Incrementado a cada mudança; as telas escutam para se atualizar.
  static final changes = ValueNotifier<int>(0);

  /// Quantos registros foram gravados no aparelho e ainda não chegaram à nuvem.
  static final pendentes = ValueNotifier<int>(0);

  /// Propriedade (fazenda) selecionada. Todas as telas mostram só os dados dela.
  static final prop = ValueNotifier<Reg?>(null);
  /// Id da propriedade aberta (-1 se ninguém estiver logado).
  static int get pid => _int(prop.value?['id']) ?? -1;

  static bool _avisoAgendado = false;
  static void _avisar() {
    if (_avisoAgendado) return;
    _avisoAgendado = true;
    scheduleMicrotask(() {
      _avisoAgendado = false;
      changes.value++;
    });
  }

  /// Banco usado nos testes (um Firestore falso); no app fica nulo.
  @visibleForTesting
  static FirebaseFirestore? bancoTeste;
  static FirebaseFirestore get _banco => bancoTeste ?? FirebaseFirestore.instance;

  /// Firestore em uso (o falso nos testes). Para o que fica fora das tabelas, como a equipe.
  static FirebaseFirestore get banco => _banco;

  static CollectionReference<Map<String, dynamic>> _col(String t) =>
      _banco.collection('usuarios').doc(_uid).collection(t);

  // ---------- Identificadores ----------

  static int _ultimoId = 0;
  static final _rnd = Random();

  /// Id numérico único entre aparelhos: milissegundos × 1000 + sorteio.
  /// Fica abaixo de 2^53, o maior inteiro exato no navegador.
  static int novoId() {
    var id = DateTime.now().millisecondsSinceEpoch * 1000 + _rnd.nextInt(1000);
    if (id <= _ultimoId) id = _ultimoId + 1;
    _ultimoId = id;
    return id;
  }

  // ---------- Início e fim da sessão ----------

  /// Liga a escuta das tabelas do usuário e carrega a propriedade selecionada.
  /// [dono] e [papel] vêm da equipe; [nome] marca os lançamentos.
  static Future<void> iniciar(String uid, {String? dono, String papel = 'dono', String? nome}) async {
    await encerrar();
    _uid = dono ?? uid;
    Db.papel.value = papel;
    if (nome != null) autor = (uid: uid, nome: nome);
    final prontos = <Future<void>>[];
    for (final t in tabelas) {
      _dados[t] = {};
      if (ehCampo && tabelasSemPeao.contains(t)) continue;
      final pronto = Completer<void>();
      _subs.add(_col(t).snapshots(includeMetadataChanges: true).listen(
        (s) {
          _receber(t, s);
          // Num aparelho novo, a primeira resposta vem do cache vazio. Para as
          // propriedades, espera a nuvem antes de concluir que não há nenhuma.
          final podeSeguir = t != 'propriedades' || !s.metadata.isFromCache || s.docs.isNotEmpty;
          if (podeSeguir && !pronto.isCompleted) pronto.complete();
        },
        onError: (Object e) {
          debugPrint('Eito: erro ao ler $t: $e');
          if (!pronto.isCompleted) pronto.complete();
        },
      ));
      prontos.add(pronto.future);
    }
    await Future.wait(prontos).timeout(const Duration(seconds: 15), onTimeout: () => const <void>[]);
    await _carregarPropriedade();
    _avisar();
  }

  static Future<void> encerrar() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _dados.clear();
    _fotos.clear();
    _pendentesPorTabela.clear();
    pendentes.value = 0;
    prop.value = null;
    _uid = null;
    papel.value = 'dono';
    autor = null;
  }

  static void _receber(String t, QuerySnapshot<Map<String, dynamic>> s) {
    final mapa = _dados[t];
    if (mapa == null) return;
    var mudou = false;
    for (final c in s.docChanges) {
      final id = c.doc.id;
      if (c.type == DocumentChangeType.removed) {
        if (mapa.remove(id) != null) mudou = true;
      } else {
        final novo = _normalizar(c.doc.data() ?? const {});
        if (!_iguais(mapa[id], novo)) {
          mapa[id] = novo;
          mudou = true;
        }
      }
    }
    _pendentesPorTabela[t] = s.docs.where((d) => d.metadata.hasPendingWrites).length;
    final total = _pendentesPorTabela.values.fold(0, (a, b) => a + b);
    if (pendentes.value != total) pendentes.value = total;
    if (mudou) {
      if (t == 'propriedades') _atualizarProp();
      _avisar();
    }
  }

  /// Outro aparelho mudou ou apagou a propriedade aberta.
  static void _atualizarProp() {
    final atual = prop.value;
    if (atual == null) return;
    final r = _reg('propriedades', atual['id']);
    if (r != null) {
      if (!_iguais(atual, r)) prop.value = Map.of(r);
      return;
    }
    final outras = _todos('propriedades')..sort((a, b) => _comparaNome(a['nome'], b['nome']));
    if (outras.isNotEmpty) prop.value = Map.of(outras.first);
  }

  static Future<void> _carregarPropriedade() async {
    var props = _todos('propriedades');
    if (props.isEmpty) {
      if (!ehDono) return; // a equipe não cria propriedade no lugar do dono
      await inserir('propriedades', {'nome': 'Minha propriedade'});
      props = _todos('propriedades');
    }
    props.sort((a, b) => _comparaNome(a['nome'], b['nome']));
    final salvo = _int(_reg('config', 'app')?['propriedade']);
    prop.value = Map.of(props.firstWhere((x) => _int(x['id']) == salvo, orElse: () => props.first));
  }

  static Future<void> selecionarPropriedade(int id) async {
    final r = _reg('propriedades', id);
    if (r == null) return;
    prop.value = Map.of(r);
    if (!ehDono) return; // a escolha do dono fica guardada só para ele
    final m = _Mudancas();
    if (_reg('config', 'app') == null) {
      _dados['config']?['app'] = {'propriedade': id};
      m._ops.add(('config', 'app', {'propriedade': id}, true));
    } else {
      m.mesclar('config', 'app', {'propriedade': id});
    }
    m.enviar();
  }

  // ---------- Acesso direto (somente leitura) ----------

  static List<Reg> _todos(String t) => [...?_dados[t]?.values];
  static Reg? _reg(String t, Object? id) => id == null ? null : _dados[t]?['$id'];

  /// Todos os registros de uma tabela (todas as propriedades). Não altere os mapas.
  static List<Reg> registros(String tabela) => _todos(tabela);

  /// Um registro pelo id, ou null.
  static Reg? registro(String tabela, Object? id) {
    final r = _reg(tabela, id);
    return r == null ? null : Map.of(r);
  }

  /// Animais desta propriedade (todos os status).
  static Iterable<Reg> _animaisDaProp([int? propriedadeId]) {
    final p = propriedadeId ?? pid;
    return _todos('animais').where((a) => _int(a['propriedade_id']) == p);
  }

  static Set<int> _idsAnimaisDaProp() => {for (final a in _animaisDaProp()) _int(a['id'])!};

  // ---------- Genéricos ----------

  static Future<int> inserir(String tabela, Reg valores) async {
    final id = _int(valores['id']) ?? novoId();
    final v = <String, Object?>{...valores, 'id': id};
    if (tabela == 'animais') _checarAnimal(v);
    (_Mudancas()..gravar(tabela, v)).enviar();
    return id;
  }

  static Future<void> atualizar(String tabela, int id, Reg valores) async {
    final atual = _reg(tabela, id);
    if (atual == null) return;
    if (tabela == 'animais') _checarAnimal({...atual, ...valores, 'id': id});
    (_Mudancas()..mesclar(tabela, id, valores)).enviar();
  }

  /// Exclui e aplica as mesmas regras do banco antigo (apaga os registros
  /// dependentes ou limpa a ligação).
  static Future<void> excluir(String tabela, int id) async {
    final m = _Mudancas();
    _apagarCascata(m, tabela, id);
    m.enviar();
  }

  static void _apagarCascata(_Mudancas m, String t, int id) {
    switch (t) {
      case 'propriedades':
        for (final l in _todos('lotes').where((x) => _int(x['propriedade_id']) == id)) {
          _apagarCascata(m, 'lotes', _int(l['id'])!);
        }
        for (final p in _todos('piquetes').where((x) => _int(x['propriedade_id']) == id)) {
          _apagarCascata(m, 'piquetes', _int(p['id'])!);
        }
        for (final a in _todos('animais').where((x) => _int(x['propriedade_id']) == id)) {
          _apagarCascata(m, 'animais', _int(a['id'])!);
        }
        for (final s in _todos('saidas').where((x) => _int(x['propriedade_id']) == id)) {
          _apagarCascata(m, 'saidas', _int(s['id'])!);
        }
        for (final e in _todos('entradas').where((x) => _int(x['propriedade_id']) == id)) {
          m.apagar('entradas', e['id']!);
        }
        for (final t in ['protocolos', 'custos', 'chuvas', 'insumos', 'formulas', 'dividas', 'estoque', 'dietas', 'pontos', 'contagens', 'contas', 'tarefas']) {
          for (final p in _todos(t).where((x) => _int(x['propriedade_id']) == id)) {
            m.apagar(t, p['id']!);
          }
        }
        for (final s in _todos('semens').where((x) => _int(x['propriedade_id']) == id)) {
          m.apagar('semens', s['id']!);
        }
        for (final o in _todos('ocorrencias').where((x) => _int(x['propriedade_id']) == id)) {
          _apagarCascata(m, 'ocorrencias', _int(o['id'])!);
        }
      case 'lotes':
        for (final a in _todos('animais').where((x) => _int(x['lote_id']) == id)) {
          m.mesclar('animais', a['id']!, {'lote_id': null});
        }
        for (final c in _todos('custos').where((x) => _int(x['lote_id']) == id)) {
          m.mesclar('custos', c['id']!, {'lote_id': null});
        }
        for (final d in _todos('dietas').where((x) => _int(x['lote_id']) == id)) {
          m.apagar('dietas', d['id']!);
        }
      case 'custos':
        // Batida ou trato apagado: o que saiu do estoque volta.
        for (final e in _todos('estoque').where((x) => '${x['grupo']}' == '$id')) {
          m.apagar('estoque', e['id']!);
        }
      case 'insumos':
        for (final e in _todos('estoque').where((x) => _int(x['insumo_id']) == id)) {
          m.apagar('estoque', e['id']!);
        }
        for (final d in _todos('dietas').where((x) => _int(x['insumo_id']) == id)) {
          m.apagar('dietas', d['id']!);
        }
      case 'formulas':
        for (final d in _todos('dietas').where((x) => _int(x['formula_id']) == id)) {
          m.apagar('dietas', d['id']!);
        }
      case 'piquetes':
        for (final p in _todos('pastagens').where((x) => _int(x['piquete_id']) == id)) {
          m.apagar('pastagens', p['id']!);
        }
        for (final c in _todos('contagens').where((x) => _int(x['piquete_id']) == id)) {
          m.apagar('contagens', c['id']!);
        }
        for (final d in _todos('dietas').where((x) => _int(x['piquete_id']) == id)) {
          m.apagar('dietas', d['id']!);
        }
        for (final o in _todos('ocorrencias').where((x) => _int(x['piquete_id']) == id)) {
          m.mesclar('ocorrencias', o['id']!, {'piquete_id': null});
        }
        for (final a in _todos('animais').where((x) => _int(x['piquete_id']) == id)) {
          m.mesclar('animais', a['id']!, {'piquete_id': null});
        }
      case 'pontos':
        for (final o in _todos('ocorrencias').where((x) => _int(x['ponto_id']) == id)) {
          m.mesclar('ocorrencias', o['id']!, {'ponto_id': null});
        }
      case 'ocorrencias':
        m.apagar('fotos', id);
        _fotos.remove(id);
      case 'saidas':
        for (final a in _todos('animais').where((x) => _int(x['saida_id']) == id)) {
          m.mesclar('animais', a['id']!, {'saida_id': null});
        }
      case 'entradas':
        for (final a in _todos('animais').where((x) => _int(x['entrada_id']) == id)) {
          m.mesclar('animais', a['id']!, {'entrada_id': null});
        }
      case 'semens':
        for (final r in _todos('reproducoes').where((x) => _int(x['semen_id']) == id)) {
          m.mesclar('reproducoes', r['id']!, {'semen_id': null});
        }
      case 'reproducoes':
        // Lançamento apagado (ex.: vaca errada): a dose volta para o estoque.
        final semen = _reg('semens', _reg('reproducoes', id)?['semen_id']);
        if (semen != null) m.somar('semens', semen['id']!, 'doses', 1);
      case 'animais':
        for (final r in _todos('reproducoes').where((x) => _int(x['femea_id']) == id)) {
          m.apagar('reproducoes', r['id']!);
        }
        for (final r in _todos('reproducoes').where((x) => _int(x['cria_id']) == id)) {
          m.mesclar('reproducoes', r['id']!, {'cria_id': null});
        }
        for (final tab in ['sanidade', 'pesagens', 'escores', 'ordenhas']) {
          for (final r in _todos(tab).where((x) => _int(x['animal_id']) == id)) {
            m.apagar(tab, r['id']!);
          }
        }
        for (final f in _todos('animais').where((x) => _int(x['mae_id']) == id)) {
          m.mesclar('animais', f['id']!, {'mae_id': null});
        }
        m.apagar('fotos', id);
        _fotos.remove(id);
    }
    m.apagar(t, id);
  }

  /// Brinco repetido entre os animais ativos da mesma propriedade, ou brinco
  /// eletrônico repetido em qualquer animal ativo.
  static void _checarAnimal(Reg v) {
    if ((v['status'] ?? 'Ativo') != 'Ativo') return;
    final id = _int(v['id']);
    final brinco = '${v['brinco'] ?? ''}'.trim().toLowerCase();
    final rfid = '${v['rfid'] ?? ''}'.trim();
    final sisbov = '${v['sisbov'] ?? ''}'.trim();
    final propId = _int(v['propriedade_id']);
    for (final a in _todos('animais')) {
      if (_int(a['id']) == id || a['status'] != 'Ativo') continue;
      if (brinco.isNotEmpty &&
          _int(a['propriedade_id']) == propId &&
          '${a['brinco'] ?? ''}'.trim().toLowerCase() == brinco) {
        throw RegistroDuplicado('Já existe um animal ativo com o brinco ${v['brinco']} nesta propriedade.');
      }
      if (rfid.isNotEmpty && '${a['rfid'] ?? ''}'.trim() == rfid) {
        throw RegistroDuplicado('Esse brinco eletrônico já é do animal ${a['brinco']}.');
      }
      if (sisbov.isNotEmpty && '${a['sisbov'] ?? ''}'.trim() == sisbov) {
        throw RegistroDuplicado('Esse número oficial (SISBOV) já é do animal ${a['brinco']}.');
      }
    }
  }

  // ---------- Propriedades ----------

  static Future<List<Reg>> propriedades() async {
    final qtd = <int, int>{};
    for (final a in _todos('animais')) {
      if (a['status'] != 'Ativo') continue;
      final p = _int(a['propriedade_id']);
      if (p != null) qtd[p] = (qtd[p] ?? 0) + 1;
    }
    return [
      for (final p in _todos('propriedades')) {...p, 'qtd': qtd[_int(p['id'])] ?? 0},
    ]..sort((a, b) => _comparaNome(a['nome'], b['nome']));
  }

  static Future<void> salvarPropriedade(Reg v, {int? id}) async {
    if (id == null) {
      final novo = await inserir('propriedades', v);
      await selecionarPropriedade(novo);
    } else {
      await atualizar('propriedades', id, v);
      if (id == pid) prop.value = Map.of(_reg('propriedades', id)!);
    }
  }

  static Future<void> excluirPropriedade(int id) async {
    await excluir('propriedades', id);
    if (_int(prop.value?['id']) == id) {
      await _carregarPropriedade();
      _avisar();
    }
  }

  // ---------- Animais ----------

  static const ordens = {'Nascimento': 'nascimento', 'Número': 'numero', 'Nome': 'nome'};

  /// Última pesagem de cada animal (por data e, no empate, pela mais recente).
  static Map<int, Reg> _ultimasPesagens() {
    final r = <int, Reg>{};
    for (final p in _todos('pesagens')) {
      final a = _int(p['animal_id']);
      if (a == null) continue;
      final atual = r[a];
      if (atual == null) {
        r[a] = p;
        continue;
      }
      final c = '${p['data']}'.compareTo('${atual['data']}');
      if (c > 0 || (c == 0 && _comparaId(p['id'], atual['id']) > 0)) r[a] = p;
    }
    return r;
  }

  static Reg _completo(Reg a, Map<int, Reg> ultimas) {
    final mae = _reg('animais', a['mae_id']);
    return {
      ...a,
      'mae_brinco': mae?['brinco'],
      'mae_nome': mae?['nome'],
      'lote_nome': _reg('lotes', a['lote_id'])?['nome'],
      'piquete_nome': _reg('piquetes', a['piquete_id'])?['nome'],
      'ultimo_peso': ultimas[_int(a['id'])]?['peso'],
    };
  }

  static Future<List<Reg>> animais({
    String busca = '',
    String? sexo,
    bool soAtivos = false,
    int? loteId,
    int? piqueteId,
    bool semLote = false,
    String ordem = 'numero',
  }) async {
    final ultimas = _ultimasPesagens();
    final b = busca.trim().toLowerCase();
    final lista = <Reg>[];
    for (final a0 in _animaisDaProp()) {
      if (sexo != null && a0['sexo'] != sexo) continue;
      if (soAtivos && a0['status'] != 'Ativo') continue;
      if (loteId != null && _int(a0['lote_id']) != loteId) continue;
      if (piqueteId != null && _int(a0['piquete_id']) != piqueteId) continue;
      if (semLote && a0['lote_id'] != null) continue;
      final a = _completo(a0, ultimas);
      if (b.isNotEmpty) {
        final alvo = [a['brinco'], a['nome'], a['lote_nome'], a['raca'], a['rfid'], a['sisbov']]
            .map((x) => '${x ?? ''}'.toLowerCase());
        if (!alvo.any((x) => x.contains(b))) continue;
      }
      lista.add(a);
    }
    int porOrdem(Reg x, Reg y) {
      switch (ordem) {
        case 'nascimento':
          return _comparaDataDesc(x['nascimento'], y['nascimento']);
        case 'nome':
          String chave(Reg r) {
            final n = '${r['nome'] ?? ''}';
            return (n.isEmpty ? '${r['brinco'] ?? ''}' : n).toLowerCase();
          }
          return chave(x).compareTo(chave(y));
        default:
          final bx = '${x['brinco'] ?? ''}', by = '${y['brinco'] ?? ''}';
          final c = bx.length.compareTo(by.length);
          return c != 0 ? c : bx.compareTo(by);
      }
    }

    lista.sort((x, y) {
      final ax = x['status'] == 'Ativo' ? 0 : 1, ay = y['status'] == 'Ativo' ? 0 : 1;
      return ax != ay ? ax.compareTo(ay) : porOrdem(x, y);
    });
    return lista;
  }

  static Future<Reg?> animal(int id) async {
    final a = _reg('animais', id);
    return a == null ? null : _completo(a, _ultimasPesagens());
  }

  static Future<List<Reg>> filhos(int maeId) async => [
        for (final a in _todos('animais'))
          if (_int(a['mae_id']) == maeId) Map.of(a),
      ]..sort((x, y) => _comparaDataDesc(x['nascimento'], y['nascimento']));

  /// Busca pelo brinco eletrônico (RFID), pelo número oficial (SISBOV) ou pelo brinco visual.
  /// Procura primeiro os ativos da propriedade aberta, depois os demais.
  static Future<Reg?> buscarPorCodigo(String codigo) async {
    final c = codigo.trim().toLowerCase();
    if (c.isEmpty) return null;
    bool bate(Reg a) =>
        '${a['rfid'] ?? ''}'.trim().toLowerCase() == c ||
        '${a['sisbov'] ?? ''}'.trim().toLowerCase() == c ||
        '${a['brinco'] ?? ''}'.trim().toLowerCase() == c;
    final todos = _todos('animais').where(bate).toList();
    if (todos.isEmpty) return null;
    int peso(Reg a) =>
        (a['status'] == 'Ativo' ? 0 : 2) + (_int(a['propriedade_id']) == _int(prop.value?['id']) ? 0 : 1);
    todos.sort((x, y) => peso(x).compareTo(peso(y)));
    return animal(_int(todos.first['id'])!);
  }

  // ---------- Lotes ----------

  static bool loteAtivo(Reg l) {
    final f = l['data_final'] as String?;
    return f == null || f.isEmpty || f.compareTo(_hoje()) >= 0;
  }

  static Future<List<Reg>> lotes({bool soAtivos = false, int? propriedadeId}) async {
    final p = propriedadeId ?? pid;
    final qtd = <int, int>{};
    for (final a in _todos('animais')) {
      if (a['status'] != 'Ativo') continue;
      final l = _int(a['lote_id']);
      if (l != null) qtd[l] = (qtd[l] ?? 0) + 1;
    }
    final r = [
      for (final l in _todos('lotes'))
        if (_int(l['propriedade_id']) == p) {...l, 'qtd': qtd[_int(l['id'])] ?? 0},
    ]..sort((x, y) {
        final c = _comparaDataDesc(x['data_inicial'], y['data_inicial']);
        return c != 0 ? c : _comparaNome(x['nome'], y['nome']);
      });
    return soAtivos ? r.where(loteAtivo).toList() : r;
  }

  static Future<Reg?> lote(int id) async => registro('lotes', id);

  static Future<int> contarSemLote() async =>
      _animaisDaProp().where((a) => a['status'] == 'Ativo' && a['lote_id'] == null).length;

  static Future<int> salvarLote(Reg v, {int? id, List<int>? animais}) async {
    final m = _Mudancas();
    final int lid;
    if (id == null) {
      lid = novoId();
      m.gravar('lotes', {...v, 'id': lid, 'propriedade_id': pid});
    } else {
      if (v.isNotEmpty) m.mesclar('lotes', id, v);
      lid = id;
    }
    if (animais != null) {
      final novos = animais.toSet();
      for (final a in _todos('animais')) {
        final aid = _int(a['id'])!;
        if (novos.contains(aid)) continue;
        if (_int(a['lote_id']) == lid && a['status'] == 'Ativo') m.mesclar('animais', aid, {'lote_id': null});
      }
      for (final a in novos) {
        m.mesclar('animais', a, {'lote_id': lid});
      }
    }
    m.enviar();
    return lid;
  }

  static Future<void> definirLote(List<int> animalIds, int? loteId) async {
    final m = _Mudancas();
    for (final a in animalIds) {
      m.mesclar('animais', a, {'lote_id': loteId});
    }
    m.enviar();
  }

  // ---------- Piquetes e pastagem ----------

  static Future<List<Reg>> piquetes({int? propriedadeId}) async {
    final p = propriedadeId ?? pid;
    final qtd = <int, int>{};
    for (final a in _todos('animais')) {
      if (a['status'] != 'Ativo') continue;
      final q = _int(a['piquete_id']);
      if (q != null) qtd[q] = (qtd[q] ?? 0) + 1;
    }
    final ultimo = <int, String>{};
    for (final ps in _todos('pastagens')) {
      final q = _int(ps['piquete_id']);
      final d = ps['data'] as String?;
      if (q == null || d == null) continue;
      if ((ultimo[q] ?? '').compareTo(d) < 0) ultimo[q] = d;
    }
    return [
      for (final pq in _todos('piquetes'))
        if (_int(pq['propriedade_id']) == p)
          {...pq, 'qtd': qtd[_int(pq['id'])] ?? 0, 'ultimo_manejo': ultimo[_int(pq['id'])]},
    ]..sort((x, y) => _comparaNome(x['nome'], y['nome']));
  }

  static Future<Reg?> piquete(int id) async => registro('piquetes', id);

  static Future<List<Reg>> pastagens({int? piqueteId}) async {
    final r = <Reg>[];
    for (final ps in _todos('pastagens')) {
      final pq = _reg('piquetes', ps['piquete_id']);
      if (pq == null || _int(pq['propriedade_id']) != pid) continue;
      if (piqueteId != null && _int(ps['piquete_id']) != piqueteId) continue;
      r.add({...ps, 'piquete_nome': pq['nome']});
    }
    r.sort((x, y) {
      final c = _comparaDataDesc(x['data'], y['data']);
      return c != 0 ? c : _comparaId(y['id'], x['id']);
    });
    return r;
  }

  static Reg _movimento(int piqueteId, String data, String tipo, List<Reg> animais) => {
        'id': novoId(),
        'piquete_id': piqueteId,
        'data': data,
        'tipo': tipo,
        'quantidade': '${animais.length} cab.',
        'descricao': animais.map((a) => a['brinco']).join(', '),
      };

  /// Coloca os animais no piquete e registra a entrada no histórico de pastagem.
  static Future<void> moverParaPiquete(List<Reg> animais, int piqueteId, String data) async {
    final m = _Mudancas();
    for (final a in animais) {
      m.mesclar('animais', a['id']!, {'piquete_id': piqueteId});
    }
    m.gravar('pastagens', _movimento(piqueteId, data, 'Entrada de animais', animais));
    m.enviar();
  }

  static Future<void> retirarDoPiquete(List<Reg> animais, int piqueteId, String data) async {
    final m = _Mudancas();
    for (final a in animais) {
      m.mesclar('animais', a['id']!, {'piquete_id': null});
    }
    m.gravar('pastagens', _movimento(piqueteId, data, 'Saída de animais', animais));
    m.enviar();
  }

  // ---------- Mudanças de lote, piquete, propriedade e categoria ----------

  /// Aplica [mudancas] (chaves propriedade_id, lote_id, piquete_id) aos animais.
  /// Quando o piquete muda, registra a saída e a entrada no histórico de pastagem.
  static Future<void> moverAnimais(List<Reg> animais, Reg mudancas, String data) async {
    final m = _Mudancas();
    if (mudancas.containsKey('piquete_id')) {
      final novo = _int(mudancas['piquete_id']);
      final saindo = <int, List<Reg>>{};
      for (final a in animais) {
        final velho = _int(a['piquete_id']);
        if (velho != null && velho != novo) saindo.putIfAbsent(velho, () => []).add(a);
      }
      for (final e in saindo.entries) {
        m.gravar('pastagens', _movimento(e.key, data, 'Saída de animais', e.value));
      }
      final entrando = animais.where((a) => _int(a['piquete_id']) != novo).toList();
      if (novo != null && entrando.isNotEmpty) {
        m.gravar('pastagens', _movimento(novo, data, 'Entrada de animais', entrando));
      }
    }
    for (final a in animais) {
      m.mesclar('animais', a['id']!, mudancas);
    }
    m.enviar();
  }

  /// Muda a categoria dos animais ativos do lote (ex.: Bezerra → Novilha).
  /// Opcionalmente leva todos para outro lote ou para um lote novo. Retorna quantos mudaram.
  static Future<int> migrarLote({
    required int loteId,
    String? deCategoria,
    required String paraCategoria,
    int? destinoLoteId,
    String? novoLote,
    required String data,
  }) async {
    final m = _Mudancas();
    var destino = destinoLoteId;
    if (novoLote != null) {
      destino = novoId();
      m.gravar('lotes', {'id': destino, 'propriedade_id': pid, 'nome': novoLote, 'data_inicial': data});
    }
    var n = 0;
    for (final a in _todos('animais')) {
      if (_int(a['lote_id']) != loteId || a['status'] != 'Ativo') continue;
      final cat = '${a['categoria'] ?? ''}';
      if (deCategoria == '' && cat.isNotEmpty) continue;
      if (deCategoria != null && deCategoria != '' && cat != deCategoria) continue;
      m.mesclar('animais', a['id']!, {'categoria': paraCategoria, if (destino != null) 'lote_id': destino});
      n++;
    }
    m.enviar();
    return n;
  }

  // ---------- Reprodução ----------

  /// filtro: null (todas), 'Pendente', 'Prenhe', 'Vazia', 'Parida'
  /// monta: null (todas), true (só monta natural), false (só inseminação/TE)
  static Future<List<Reg>> reproducoes({String? filtro, int? femeaId, bool? monta}) async {
    final r = <Reg>[];
    for (final x in _todos('reproducoes')) {
      final a = _reg('animais', x['femea_id']);
      if (a == null) continue;
      switch (filtro) {
        case 'Pendente':
          if (x['diagnostico'] != 'Pendente') continue;
        case 'Prenhe':
          if (x['diagnostico'] != 'Prenhe' || x['parto_data'] != null) continue;
        case 'Vazia':
          if (x['diagnostico'] != 'Vazia') continue;
        case 'Parida':
          if (x['parto_data'] == null) continue;
      }
      if (femeaId != null) {
        if (_int(x['femea_id']) != femeaId) continue;
      } else if (_int(a['propriedade_id']) != pid) {
        continue;
      }
      if (monta == true && x['tipo'] != 'Monta natural') continue;
      if (monta == false && x['tipo'] == 'Monta natural') continue;
      r.add({
        ...x,
        'brinco': a['brinco'],
        'nome': a['nome'],
        'femea_status': a['status'],
        'cria_brinco': _reg('animais', x['cria_id'])?['brinco'],
      });
    }
    r.sort((x, y) {
      final c = _comparaDataDesc(x['data'], y['data']);
      return c != 0 ? c : _comparaId(y['id'], x['id']);
    });
    return r;
  }

  static Reg? _servicoAberto(int femeaId) {
    final abertos = _todos('reproducoes')
        .where((r) => _int(r['femea_id']) == femeaId && r['parto_data'] == null && r['diagnostico'] != 'Vazia')
        .toList()
      ..sort((x, y) {
        final c = _comparaDataDesc(x['data'], y['data']);
        return c != 0 ? c : _comparaId(y['id'], x['id']);
      });
    return abertos.isEmpty ? null : abertos.first;
  }

  /// Último serviço da fêmea ainda sem parto (e não vazio).
  static Future<Reg?> reproducaoAberta(int femeaId) async {
    final r = _servicoAberto(femeaId);
    return r == null ? null : Map.of(r);
  }

  /// Cria o bezerro, a pesagem ao nascer, fecha o serviço da mãe e
  /// atualiza a categoria da mãe para Vaca.
  static Future<int> registrarNascimento({
    required int maeId,
    required String data,
    required String brinco,
    required String sexo,
    String? nome,
    String? raca,
    String? pai,
    double? peso,
    int? loteId,
    String? obs,
    int? reproducaoId,
  }) async {
    final criaId = novoId();
    final cria = <String, Object?>{
      'id': criaId,
      'brinco': brinco,
      'nome': nome,
      'sexo': sexo,
      'raca': raca,
      'categoria': sexo == 'F' ? 'Bezerra' : 'Bezerro',
      'nascimento': data,
      'mae_id': maeId,
      'pai': pai,
      'lote_id': loteId,
      'propriedade_id': pid,
      'origem': 'Nascimento',
      'status': 'Ativo',
      'obs': obs,
      'criado_em': DateTime.now().toIso8601String(),
    };
    _checarAnimal(cria);
    final m = _Mudancas()..gravar('animais', cria);
    if (peso != null && peso > 0) {
      m.gravar('pesagens', {'id': novoId(), 'animal_id': criaId, 'data': data, 'peso': peso, 'evento': 'Nascimento'});
    }
    final repId = reproducaoId ?? _int(_servicoAberto(maeId)?['id']);
    if (repId != null) {
      m.mesclar('reproducoes', repId, {'parto_data': data, 'cria_id': criaId, 'diagnostico': 'Prenhe'});
    }
    final mae = _reg('animais', maeId);
    final cat = mae?['categoria'];
    if (mae != null && (cat == null || cat == 'Novilha' || cat == 'Bezerra')) {
      m.mesclar('animais', maeId, {'categoria': 'Vaca'});
    }
    m.enviar();
    return criaId;
  }

  /// Data prevista do parto para um serviço feito em [dataServico].
  static String? partoPrevisto(Object? dataServico) {
    final d = DateTime.tryParse('${dataServico ?? ''}');
    if (d == null) return null;
    final p = DateTime(d.year, d.month, d.day + diasGestacao);
    return '${p.year.toString().padLeft(4, '0')}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
  }

  /// Registra IA, IATF ou TE e dá baixa de uma dose do sêmen escolhido.
  /// Se a fêmea tinha serviço aguardando diagnóstico, ele fica como vazia
  /// (repasse). Fêmea já prenhe não recebe novo serviço.
  static Future<int> registrarInseminacao({
    required int femeaId,
    required String data,
    required String tipo,
    int? semenId,
    String? inseminador,
    String? protocolo,
    String? obs,
    Reg? ficha,
  }) async {
    final m = _Mudancas();
    final aberto = _servicoAberto(femeaId);
    if (aberto != null) {
      if (aberto['diagnostico'] == 'Prenhe') {
        throw RegistroDuplicado('Esta fêmea já está prenhe (parto previsto ${aberto['parto_previsto'] ?? '-'}).');
      }
      m.mesclar('reproducoes', aberto['id']!, {'diagnostico': 'Vazia', 'data_diagnostico': data, 'parto_previsto': null});
    }
    final semen = _reg('semens', semenId);
    final lote = protocoloDaFemea(femeaId, data);
    protocolo ??= lote?['nome'] as String?;
    final id = novoId();
    m.gravar('reproducoes', {
      ...?ficha,
      'id': id,
      'femea_id': femeaId,
      'tipo': tipo,
      'data': data,
      'semen_id': semen == null ? null : semenId,
      'touro': semen?['touro'],
      'partida': semen?['partida'],
      'custo_dose': semen?['preco_dose'],
      'inseminador': inseminador,
      'protocolo': protocolo,
      'protocolo_id': lote?['id'],
      'diagnostico': 'Pendente',
      'data_diagnostico': null,
      'parto_previsto': null,
      'obs': obs,
    });
    if (semen != null) m.somar('semens', semenId!, 'doses', -1);
    m.enviar();
    return id;
  }

  /// 2º diagnóstico (confirmação, por volta de 60 dias). Prenhe que deu vazia
  /// na confirmação é perda embrionária: fica vazia e marcada como perda.
  static Future<void> lancarConfirmacao(int reproducaoId, bool prenhe, String data) async {
    if (_reg('reproducoes', reproducaoId) == null) return;
    await atualizar(
        'reproducoes',
        reproducaoId,
        prenhe
            ? {'confirmado': true, 'perda': false, 'data_confirmacao': data}
            : {'confirmado': false, 'perda': true, 'data_confirmacao': data, 'diagnostico': 'Vazia', 'parto_previsto': null});
  }

  /// Lança o diagnóstico de gestação e calcula o parto previsto.
  static Future<void> lancarDiagnostico(int reproducaoId, String diagnostico, String data) async {
    final r = _reg('reproducoes', reproducaoId);
    if (r == null) return;
    await atualizar('reproducoes', reproducaoId, {
      'diagnostico': diagnostico,
      'data_diagnostico': diagnostico == 'Pendente' ? null : data,
      'parto_previsto': diagnostico == 'Prenhe' ? partoPrevisto(r['data']) : null,
    });
  }

  // ---------- Protocolos de IATF ----------

  /// Protocolos desta propriedade, os mais recentes primeiro.
  static Future<List<Reg>> protocolos() async => [
        for (final p in _todos('protocolos'))
          if (_int(p['propriedade_id']) == pid) Map.of(p),
      ]..sort((x, y) => _comparaDataDesc(x['inicio'], y['inicio']));

  /// Grava um lote de vacas em protocolo. [etapas]: lista de {dia, nome}, com o D0 em [inicio].
  static Future<int> salvarProtocolo({
    int? id,
    required String nome,
    required String inicio,
    required List<Map<String, Object?>> etapas,
    required List<int> femeas,
    Reg? extras,
  }) async {
    final v = {...?extras, 'nome': nome, 'inicio': inicio, 'etapas': etapas, 'femeas': femeas};
    if (id != null) {
      await atualizar('protocolos', id, v);
      return id;
    }
    return inserir('protocolos', {...v, 'propriedade_id': pid});
  }

  /// Data (ISO) de uma etapa: D0 + dia.
  static String dataEtapa(Object? inicio, Object? dia) {
    final d = DateTime.parse('$inicio'.substring(0, 10));
    final e = DateTime(d.year, d.month, d.day + (_int(dia) ?? 0));
    return '${e.year.toString().padLeft(4, '0')}-${e.month.toString().padLeft(2, '0')}-${e.day.toString().padLeft(2, '0')}';
  }

  /// Protocolo em que a fêmea está cuja inseminação cai perto de [data] (até 5 dias).
  static Reg? protocoloDaFemea(int femeaId, String data) {
    final alvo = DateTime.tryParse(data);
    if (alvo == null) return null;
    for (final p in _todos('protocolos')) {
      if (!((p['femeas'] as List?) ?? const []).map(_int).contains(femeaId)) continue;
      final etapas = (p['etapas'] as List?) ?? const [];
      if (etapas.isEmpty || p['inicio'] == null) continue;
      final ia = DateTime.parse(dataEtapa(p['inicio'], (etapas.last as Map)['dia']));
      if (alvo.difference(ia).inDays.abs() <= 5) return p;
    }
    return null;
  }

  /// Grava um ajuste do app (ex.: valores da projeção de abate) em config/[chave].
  static Future<void> salvarConfig(String chave, Reg valores) async =>
      (_Mudancas()..gravar('config', {...valores, 'id': chave})).enviar();

  // ---------- Fila do dia ----------

  /// Itens da fila riscados hoje.
  static Set<String> filaFeitos() {
    final f = _reg('config', 'fila');
    if (f == null || f['dia'] != _hoje()) return {};
    return {for (final c in (f['feitos'] as List?) ?? const []) '$c'};
  }

  static Future<void> marcarFila(String chave, bool feito) async {
    final feitos = filaFeitos();
    feito ? feitos.add(chave) : feitos.remove(chave);
    (_Mudancas()..gravar('config', {'id': 'fila', 'dia': _hoje(), 'feitos': feitos.toList()})).enviar();
  }

  // ---------- Foto do animal ----------
  // Fica fora das tabelas escutadas (é pesada): lida só quando a ficha abre.

  static final Map<int, String?> _fotos = {};

  /// Foto (JPEG em base64) do animal, ou null.
  static Future<String?> foto(int animalId) async {
    if (_fotos.containsKey(animalId)) return _fotos[animalId];
    try {
      final d = await _col('fotos').doc('$animalId').get();
      return _fotos[animalId] = d.data()?['imagem'] as String?;
    } catch (e) {
      debugPrint('Eito: erro ao ler foto: $e');
      return null;
    }
  }

  /// Lê todas as fotos da conta (para o backup). Retorna quantas há, ou null sem sinal.
  static Future<int?> carregarFotos() async {
    try {
      final q = await _col('fotos').get();
      for (final d in q.docs) {
        final id = _int(d.data()['animal_id']) ?? int.tryParse(d.id);
        if (id != null) _fotos[id] = d.data()['imagem'] as String?;
      }
      return _fotos.values.whereType<String>().length;
    } catch (e) {
      debugPrint('Eito: erro ao ler as fotos: $e');
      return null;
    }
  }

  static Future<void> salvarFoto(int animalId, String? base64) async {
    _fotos[animalId] = base64;
    final ref = _col('fotos').doc('$animalId');
    final f = base64 == null
        ? ref.delete()
        : ref.set({'animal_id': animalId, 'imagem': base64, 'data': DateTime.now().toIso8601String()});
    f.catchError((Object e) => debugPrint('Eito: falha ao gravar foto: $e'));
    _avisar();
  }

  // ---------- Sêmen ----------

  /// Sêmen (touros) cadastrado nesta propriedade, com o uso de cada um:
  /// usadas, prenhes, vazias e custo das doses usadas.
  static Future<List<Reg>> semens() async {
    final uso = <int, Map<String, num>>{};
    for (final r in _todos('reproducoes')) {
      final s = _int(r['semen_id']);
      if (s == null) continue;
      final u = uso.putIfAbsent(s, () => {'usadas': 0, 'prenhes': 0, 'vazias': 0, 'custo': 0});
      u['usadas'] = u['usadas']! + 1;
      if (r['diagnostico'] == 'Prenhe') u['prenhes'] = u['prenhes']! + 1;
      if (r['diagnostico'] == 'Vazia') u['vazias'] = u['vazias']! + 1;
      if (r['custo_dose'] is num) u['custo'] = u['custo']! + (r['custo_dose'] as num);
    }
    return [
      for (final s in _todos('semens'))
        if (_int(s['propriedade_id']) == pid)
          {...s, 'usadas': 0, 'prenhes': 0, 'vazias': 0, 'custo': 0, ...?uso[_int(s['id'])]},
    ]..sort((a, b) {
        final c = _comparaNome(a['touro'], b['touro']);
        return c != 0 ? c : _comparaNome(a['partida'], b['partida']);
      });
  }

  static Future<int> salvarSemen(Reg v, {int? id}) async {
    if (id == null) return inserir('semens', {...v, 'propriedade_id': pid});
    await atualizar('semens', id, v);
    return id;
  }

  // ---------- Sanidade ----------

  static Future<List<Reg>> sanidadeGrupos() async {
    final grupos = <String, Reg>{};
    final brincos = <String, List<String>>{};
    for (final s in _todos('sanidade')) {
      final a = _reg('animais', s['animal_id']);
      if (a == null || _int(a['propriedade_id']) != pid) continue;
      final g = '${s['grupo']}';
      grupos.putIfAbsent(g, () => {
            'grupo': g,
            for (final k in ['data', 'tipo', 'produto', 'dose', 'carencia', 'proxima', 'obs']) k: s[k],
          });
      brincos.putIfAbsent(g, () => []).add('${a['brinco']}');
    }
    final r = [
      for (final e in grupos.entries) {...e.value, 'qtd': brincos[e.key]!.length, 'brincos': brincos[e.key]!.join(', ')},
    ]..sort((x, y) {
        final c = _comparaDataDesc(x['data'], y['data']);
        return c != 0 ? c : '${y['grupo']}'.compareTo('${x['grupo']}');
      });
    return r;
  }

  static Future<List<Reg>> sanidadeDoAnimal(int animalId) async => [
        for (final s in _todos('sanidade'))
          if (_int(s['animal_id']) == animalId) Map.of(s),
      ]..sort((x, y) {
          final c = _comparaDataDesc(x['data'], y['data']);
          return c != 0 ? c : _comparaId(y['id'], x['id']);
        });

  /// Lança o mesmo manejo para vários animais. Passe [grupo] para juntar
  /// com um lançamento já feito (ex.: vacinação em série no curral).
  static Future<String> lancarSanidade(List<int> animalIds, Reg valores, {String? grupo}) async {
    final g = grupo ?? '${novoId()}';
    final m = _Mudancas();
    for (final id in animalIds) {
      m.gravar('sanidade', {...valores, 'id': novoId(), 'grupo': g, 'animal_id': id});
    }
    _baixaSanidade(m, valores, animalIds.length, g);
    m.enviar();
    return g;
  }

  /// Vacina ou remédio com o mesmo nome de um insumo do estoque: tira do
  /// estoque a dose de cada animal.
  static void _baixaSanidade(_Mudancas m, Reg valores, int animais, String grupo) {
    final produto = '${valores['produto'] ?? ''}'.trim().toLowerCase();
    if (produto.isEmpty || animais == 0) return;
    final insumo = _todos('insumos').where((i) =>
        _int(i['propriedade_id']) == pid && '${i['nome'] ?? ''}'.trim().toLowerCase() == produto).firstOrNull;
    if (insumo == null) return;
    final dose = insumo['dose_animal'] is num && (insumo['dose_animal'] as num) > 0 ? insumo['dose_animal'] as num : 1;
    m.gravar('estoque', {
      'id': novoId(),
      'propriedade_id': pid,
      'insumo_id': insumo['id'],
      'data': '${valores['data'] ?? _hoje()}'.substring(0, 10),
      'qtd': -(dose * animais),
      'motivo': 'Sanidade · $animais animal(is)',
      'grupo': grupo,
    });
  }

  static Future<void> excluirGrupoSanidade(String grupo) async {
    final m = _Mudancas();
    for (final s in _todos('sanidade').where((x) => '${x['grupo']}' == grupo)) {
      m.apagar('sanidade', s['id']!);
    }
    for (final e in _todos('estoque').where((x) => '${x['grupo']}' == grupo)) {
      m.apagar('estoque', e['id']!);
    }
    m.enviar();
  }

  // ---------- Pesagens ----------

  static Future<List<Reg>> pesagens({int? animalId}) async {
    final ids = animalId == null ? _idsAnimaisDaProp() : {animalId};
    final r = <Reg>[];
    for (final p in _todos('pesagens')) {
      final aid = _int(p['animal_id']);
      if (!ids.contains(aid)) continue;
      final a = _reg('animais', aid);
      if (a == null) continue;
      r.add({...p, 'brinco': a['brinco'], 'nome': a['nome']});
    }
    r.sort((x, y) {
      final c = _comparaDataDesc(x['data'], y['data']);
      return c != 0 ? c : _comparaId(y['id'], x['id']);
    });
    return r;
  }

  static Future<void> lancarPesagens(List<Reg> linhas) async {
    final m = _Mudancas();
    for (final l in linhas) {
      m.gravar('pesagens', {...l, 'id': novoId()});
    }
    m.enviar();
  }

  /// Pesagem rápida (Modo Curral). Devolve o ganho médio diário desde a
  /// pesagem anterior, se houver ao menos um dia entre elas.
  static Future<double?> registrarPesagem(int animalId, double peso,
      {String evento = 'Rotina', String? data}) async {
    final dia = data ?? _hoje();
    final anterior = _ultimasPesagens()[animalId];
    double? gmd;
    if (anterior != null) {
      final d0 = DateTime.tryParse('${anterior['data']}');
      final d1 = DateTime.tryParse(dia);
      if (d0 != null && d1 != null) {
        final dias = DateTime.utc(d1.year, d1.month, d1.day).difference(DateTime.utc(d0.year, d0.month, d0.day)).inDays;
        if (dias >= 1) gmd = (peso - (anterior['peso'] as num)) / dias;
      }
    }
    await inserir('pesagens', {'animal_id': animalId, 'data': dia, 'peso': peso, 'evento': evento});
    return gmd;
  }

  // ---------- Saídas (vendas, mortes...) ----------

  static Future<List<Reg>> saidas() async {
    final brincos = <int, List<String>>{};
    for (final a in _todos('animais')) {
      final s = _int(a['saida_id']);
      if (s != null) brincos.putIfAbsent(s, () => []).add('${a['brinco']}');
    }
    return [
      for (final s in _todos('saidas'))
        if (_int(s['propriedade_id']) == pid) {...s, 'brincos': brincos[_int(s['id'])]?.join(', ')},
    ]..sort((x, y) {
        final c = _comparaDataDesc(x['data'], y['data']);
        return c != 0 ? c : _comparaId(y['id'], x['id']);
      });
  }

  static Future<Reg?> saida(int id) async => registro('saidas', id);

  static Future<void> registrarSaida(Reg saida, List<int> animalIds) async {
    final status = statusPorSaida[saida['tipo']] ?? 'Baixado';
    final id = novoId();
    final m = _Mudancas()
      ..gravar('saidas', {...saida, 'id': id, 'quantidade': animalIds.length, 'propriedade_id': pid});
    for (final a in animalIds) {
      m.mesclar('animais', a, {'status': status, 'saida_id': id, 'piquete_id': null});
    }
    m.enviar();
  }

  /// Exclui a saída e devolve os animais ao rebanho ativo.
  static Future<void> excluirSaida(int id) async {
    final m = _Mudancas();
    for (final a in _todos('animais').where((x) => _int(x['saida_id']) == id)) {
      m.mesclar('animais', a['id']!, {'status': 'Ativo', 'saida_id': null});
    }
    m.apagar('saidas', id);
    m.enviar();
  }

  // ---------- Entradas (compras, transferências...) ----------

  static Future<List<Reg>> entradas() async {
    final brincos = <int, List<String>>{};
    for (final a in _todos('animais')) {
      final e = _int(a['entrada_id']);
      if (e != null) brincos.putIfAbsent(e, () => []).add('${a['brinco']}');
    }
    return [
      for (final e in _todos('entradas'))
        if (_int(e['propriedade_id']) == pid) {...e, 'brincos': brincos[_int(e['id'])]?.join(', ')},
    ]..sort((x, y) {
        final c = _comparaDataDesc(x['data'], y['data']);
        return c != 0 ? c : _comparaId(y['id'], x['id']);
      });
  }

  /// Cadastra os animais que chegaram (um por brinco) com os dados comuns em
  /// [animal] e registra a entrada. Com peso total, cada animal ganha uma
  /// pesagem de entrada com o peso médio.
  static Future<int> registrarEntrada(Reg entrada, List<String> brincos, Reg animal) async {
    final lista = [for (final b in brincos) b.trim()]..removeWhere((b) => b.isEmpty);
    final vistos = <String>{};
    for (final b in lista) {
      if (!vistos.add(b.toLowerCase())) throw RegistroDuplicado('O brinco $b foi digitado duas vezes.');
    }
    final id = novoId();
    final data = '${entrada['data'] ?? _hoje()}';
    final peso = entrada['peso_total'];
    final pesoMedio = peso is num && peso > 0 && lista.isNotEmpty ? peso / lista.length : null;
    final novos = [
      for (final b in lista)
        <String, Object?>{
          ...animal,
          'id': novoId(),
          'brinco': b,
          'propriedade_id': pid,
          'origem': entrada['tipo'] == 'Compra' ? 'Compra' : 'Outro',
          'entrada_id': id,
          'status': 'Ativo',
          'criado_em': DateTime.now().toIso8601String(),
        },
    ];
    for (final a in novos) {
      _checarAnimal(a);
    }
    final m = _Mudancas()
      ..gravar('entradas', {...entrada, 'id': id, 'data': data, 'quantidade': lista.length, 'propriedade_id': pid});
    for (final a in novos) {
      m.gravar('animais', a);
      if (pesoMedio != null) {
        m.gravar('pesagens', {'id': novoId(), 'animal_id': a['id'], 'data': data, 'peso': pesoMedio, 'evento': 'Entrada'});
      }
    }
    m.enviar();
    return id;
  }

  /// Exclui a entrada. Com [apagarAnimais], apaga também os animais que
  /// chegaram nela (e o histórico deles); sem, eles continuam no rebanho.
  static Future<void> excluirEntrada(int id, {bool apagarAnimais = false}) async {
    final m = _Mudancas();
    if (apagarAnimais) {
      for (final a in _todos('animais').where((x) => _int(x['entrada_id']) == id)) {
        _apagarCascata(m, 'animais', _int(a['id'])!);
      }
    }
    _apagarCascata(m, 'entradas', id);
    m.enviar();
  }

  // ---------- Backup ----------

  /// Texto com todos os dados (todas as propriedades). Síncrono de propósito:
  /// o navegador só deixa copiar para a área de transferência logo após o toque.
  static String exportarJson({bool comFotos = true}) {
    final dados = <String, Object?>{};
    for (final t in tabelas) {
      if (t == 'config') {
        dados[t] = [
          if (prop.value != null) {'chave': 'propriedade', 'valor': '$pid'},
        ];
      } else {
        dados[t] = _todos(t)..sort((a, b) => _comparaId(a['id'], b['id']));
      }
    }
    return jsonEncode({
      'app': 'eito_gestao_rural',
      'versao': 2,
      'gerado_em': DateTime.now().toIso8601String(),
      'tabelas': dados,
      if (comFotos)
        'fotos': [
          for (final e in _fotos.entries)
            if (e.value != null && _reg('animais', e.key) != null) {'animal_id': e.key, 'imagem': e.value},
        ],
    });
  }

  /// Substitui todos os dados (na nuvem e no aparelho) pelos do backup.
  /// Aceita também backups da Caderneta do Rebanho. Retorna o nº de animais.
  static Future<int> importarJson(String texto) async {
    final mapa = jsonDecode(texto) as Map<String, dynamic>;
    if (mapa['app'] != 'caderneta_rebanho' && mapa['app'] != 'eito_gestao_rural') {
      throw const FormatException('Este texto não é um backup do Eito nem da Caderneta do Rebanho.');
    }
    final tabelasBackup = mapa['tabelas'] as Map<String, dynamic>;
    final versao = _int(mapa['versao']) ?? 1;

    final novos = <String, List<Reg>>{};
    int? propriedadeEscolhida;
    for (final t in tabelas) {
      final linhas = (tabelasBackup[t] as List? ?? const [])
          .map((l) => _normalizar(Map<String, dynamic>.from(l as Map)))
          .toList();
      if (t == 'config') {
        for (final l in linhas) {
          if (l['chave'] == 'propriedade') propriedadeEscolhida = _int(l['valor']);
        }
        continue;
      }
      novos[t] = [for (final l in linhas) if (_int(l['id']) != null) l];
    }

    if (versao < 2) {
      // Backup antigo, sem propriedades: põe tudo numa propriedade padrão.
      final p = novoId();
      novos['propriedades'] = [
        {'id': p, 'nome': 'Minha propriedade'}
      ];
      for (final a in novos['animais']!) {
        a['propriedade_id'] = p;
      }
      for (final s in novos['saidas']!) {
        s['propriedade_id'] = p;
      }
      final lotesPorNome = <String, int>{};
      for (final a in novos['animais']!) {
        final nome = '${a['lote'] ?? ''}'.trim();
        if (nome.isEmpty) continue;
        a['lote_id'] = lotesPorNome.putIfAbsent(nome, () {
          final lid = novoId();
          novos['lotes']!.add({'id': lid, 'propriedade_id': p, 'nome': nome, 'data_inicial': _hoje()});
          return lid;
        });
      }
      propriedadeEscolhida = p;
    }

    final m = _Mudancas();
    for (final t in tabelas) {
      if (t == 'config') continue;
      final ficam = {for (final l in novos[t]!) '${_int(l['id'])}'};
      for (final antigo in _todos(t)) {
        if (!ficam.contains('${antigo['id']}')) m.apagar(t, antigo['id']!);
      }
      for (final l in novos[t]!) {
        m.gravar(t, {...l, 'id': _int(l['id'])});
      }
    }
    m.enviar();

    // Fotos uma a uma: cada uma pesa e o lote do Firestore tem limite de tamanho.
    for (final f in (mapa['fotos'] as List?) ?? const []) {
      final foto = Map<String, dynamic>.from(f as Map);
      final id = _int(foto['animal_id']);
      if (id != null && foto['imagem'] is String) await salvarFoto(id, foto['imagem'] as String);
    }

    if (_todos('propriedades').isEmpty) {
      await inserir('propriedades', {'nome': 'Minha propriedade'});
    }
    final escolhida = propriedadeEscolhida != null && _reg('propriedades', propriedadeEscolhida) != null
        ? propriedadeEscolhida
        : _int((_todos('propriedades')..sort((a, b) => _comparaNome(a['nome'], b['nome']))).first['id'])!;
    await selecionarPropriedade(escolhida);
    _avisar();
    return novos['animais']!.length;
  }
}
