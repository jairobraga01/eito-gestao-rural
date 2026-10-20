// Cotação de compra de medicamentos e de insumos com os fornecedores.
//
// Cada fornecedor recebe pelo WhatsApp um link só dele
// (eitogestao.com.br/cotacao.html?c=<código>). Ele abre no celular, preenche
// os preços sem entrar no app e envia. O código é sorteado e serve de senha.
//
// Firestore (fora de usuarios/, ver firestore.rules):
//   pedidos_cotacao/{codigo}  um documento por fornecedor de cada cotação
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'db.dart';

const tipoMedicamentos = 'Medicamentos';
const tipoInsumos = 'Insumos';

/// Endereço da página que o fornecedor preenche.
const siteCotacaoFornecedor = 'https://eitogestao.com.br/cotacao.html';

double? _num(Object? v) => v is num ? v.toDouble() : null;
String _t(Object? v) => v == null ? '' : '$v';

/// Item pedido na cotação.
class ItemCotacao {
  ItemCotacao({required this.nome, required this.unidade, required this.qtd, this.insumoId, this.estoque});
  final String nome, unidade;
  final double qtd;
  final int? insumoId;

  /// Estoque que a fazenda tinha ao pedir (null = item sem controle de estoque).
  final double? estoque;

  Map<String, Object?> paraMapa() =>
      {'nome': nome, 'unidade': unidade, 'qtd': qtd, 'insumo_id': insumoId, 'estoque': estoque};

  static ItemCotacao deMapa(Object? m) {
    final x = m is Map ? m : const {};
    return ItemCotacao(
      nome: _t(x['nome']),
      unidade: _t(x['unidade']),
      qtd: _num(x['qtd']) ?? 0,
      insumoId: x['insumo_id'] is num ? (x['insumo_id'] as num).toInt() : null,
      estoque: _num(x['estoque']),
    );
  }
}

/// Uma cotação enviada a um fornecedor (e a resposta dele).
class PedidoCotacao {
  PedidoCotacao(this.codigo, this.dados);
  final String codigo;
  final Map<String, dynamic> dados;

  String get tipo => _t(dados['tipo']);
  String get grupo => _t(dados['grupo']);
  String get titulo => _t(dados['titulo']);
  String get fornecedor => _t((dados['fornecedor'] as Map?)?['nome']);
  String get telefone => _t((dados['fornecedor'] as Map?)?['telefone']);
  int? get contatoId => switch ((dados['fornecedor'] as Map?)?['contato_id']) { final num n => n.toInt(), _ => null };
  String get pedidoObs => _t(dados['pedido_obs']);
  bool get respondida => dados['status'] == 'respondida';
  bool get visto => dados['visto'] == true;
  DateTime? get criadoEm => _data(dados['criado_em']);
  DateTime? get respondidoEm => _data(dados['respondido_em']);
  List<ItemCotacao> get itens => [for (final i in (dados['itens'] as List? ?? const [])) ItemCotacao.deMapa(i)];

  /// Preço por unidade de cada item (null = o fornecedor não tem).
  List<double?> get precos {
    final p = dados['precos'] as List? ?? const [];
    return [for (var i = 0; i < itens.length; i++) i < p.length ? _num(p[i]) : null];
  }

  /// Preço a prazo de cada item: 30/60/90 dias e 90 dias direto (null = não informado).
  List<double?> get precos30 => _lista('precos_30_60_90');
  List<double?> get precos90 => _lista('precos_90_direto');

  List<double?> _lista(String campo) {
    final p = dados[campo] as List? ?? const [];
    return [for (var i = 0; i < itens.length; i++) i < p.length ? _num(p[i]) : null];
  }

  /// Preços de um prazo: 0 = à vista, 1 = 30/60/90 dias, 2 = 90 dias direto.
  List<double?> precosModo(int modo) => switch (modo) { 0 => precos, 1 => precos30, _ => precos90 };

  int cotadosModo(int modo) => precosModo(modo).whereType<double>().length;

  /// Total de um prazo: preço × quantidade dos itens cotados nele, mais o frete.
  double totalModo(int modo) {
    final p = precosModo(modo), it = itens;
    var s = frete;
    for (var i = 0; i < it.length; i++) {
      if (p[i] != null) s += p[i]! * it[i].qtd;
    }
    return s;
  }

  double get frete => _num(dados['frete']) ?? 0;
  String get prazo => _t(dados['prazo']);
  String get pagamento => _t(dados['pagamento']);
  String get obs => _t(dados['obs']);
  String get respondidoPor => _t(dados['respondido_por']);

  /// Itens com preço.
  int get cotados => precos.whereType<double>().length;

  /// Preço final: soma de preço × quantidade dos itens cotados, mais o frete.
  double get total {
    final p = precos, it = itens;
    var s = frete;
    for (var i = 0; i < it.length; i++) {
      if (p[i] != null) s += p[i]! * it[i].qtd;
    }
    return s;
  }

  String get link => '$siteCotacaoFornecedor?c=$codigo';

  static DateTime? _data(Object? v) => switch (v) {
        Timestamp t => t.toDate(),
        DateTime d => d,
        String s => DateTime.tryParse(s),
        _ => null,
      };
}

/// Cotações de um mesmo pedido (uma por fornecedor), para comparar.
class GrupoCotacao {
  GrupoCotacao(this.pedidos);
  final List<PedidoCotacao> pedidos;

  PedidoCotacao get primeiro => pedidos.first;
  String get titulo => primeiro.titulo;
  String get tipo => primeiro.tipo;
  List<ItemCotacao> get itens => primeiro.itens;
  List<PedidoCotacao> get respondidas => [for (final p in pedidos) if (p.respondida) p];

  /// Menor preço de cada item entre as respostas (null = ninguém cotou).
  List<double?> get menores => [
        for (var i = 0; i < itens.length; i++)
          respondidas.map((p) => p.precos[i]).whereType<double>().fold<double?>(null, (m, v) => m == null || v < m ? v : m),
      ];

  /// Melhor preço final entre quem cotou todos os itens (ou, se ninguém cotou
  /// tudo, entre quem cotou mais itens).
  PedidoCotacao? get melhor {
    final r = respondidas;
    if (r.isEmpty) return null;
    final mais = r.map((p) => p.cotados).reduce(max);
    final candidatos = r.where((p) => p.cotados == mais).toList()..sort((a, b) => a.total.compareTo(b.total));
    return candidatos.first;
  }
}

class CotacoesCompra {
  CotacoesCompra._();

  static CollectionReference<Map<String, dynamic>> get colecao => Db.banco.collection('pedidos_cotacao');

  /// Todas as cotações da fazenda (as mais novas primeiro).
  static final pedidos = ValueNotifier<List<PedidoCotacao>>(const []);

  /// Respostas que ainda não foram abertas: viram o aviso "Cotação Recebida".
  static final recebidas = ValueNotifier<List<PedidoCotacao>>(const []);

  static StreamSubscription<Object?>? _sub;

  /// Começa a escutar as cotações do dono da fazenda.
  static void iniciar() {
    parar();
    final dono = Db.dono;
    if (dono == null) return;
    _sub = colecao.where('dono', isEqualTo: dono).snapshots().listen((s) {
      final lista = [for (final d in s.docs) PedidoCotacao(d.id, d.data())]
        ..sort((a, b) => (b.criadoEm ?? DateTime(2100)).compareTo(a.criadoEm ?? DateTime(2100)));
      pedidos.value = lista;
      recebidas.value = [for (final p in lista) if (p.respondida && !p.visto) p];
    }, onError: (Object e) => debugPrint('Eito: cotações: $e'));
  }

  static void parar() {
    _sub?.cancel();
    _sub = null;
    pedidos.value = const [];
    recebidas.value = const [];
  }

  /// Cotações do tipo, agrupadas por pedido (as mais novas primeiro).
  static List<GrupoCotacao> grupos(String tipo, [List<PedidoCotacao>? lista]) {
    final porGrupo = <String, List<PedidoCotacao>>{};
    for (final p in lista ?? pedidos.value) {
      if (p.tipo != tipo || _t(p.dados['propriedade_id']) != '${Db.pid}') continue;
      porGrupo.putIfAbsent(p.grupo.isEmpty ? p.codigo : p.grupo, () => []).add(p);
    }
    return [for (final g in porGrupo.values) GrupoCotacao(g..sort((a, b) => a.fornecedor.compareTo(b.fornecedor)))];
  }

  static final _rnd = Random.secure();

  /// Código sorteado que vai no link (difícil de adivinhar).
  static String novoCodigo() {
    const letras = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(24, (_) => letras[_rnd.nextInt(letras.length)]).join();
  }

  /// Cria uma cotação por fornecedor e devolve os pedidos para enviar.
  static Future<List<PedidoCotacao>> criar({
    required String tipo,
    required String titulo,
    required List<ItemCotacao> itens,
    required List<Reg> fornecedores,
    String? obs,
    String? grupoExistente,
  }) async {
    final grupo = grupoExistente ?? 'g${Db.novoId()}';
    final fazenda = _t(Db.prop.value?['nome']);
    final criados = <PedidoCotacao>[];
    final lote = Db.banco.batch();
    for (final f in fornecedores) {
      final codigo = novoCodigo();
      final dados = <String, dynamic>{
        'dono': Db.dono,
        'propriedade_id': Db.pid,
        'fazenda': fazenda,
        'fazenda_telefone': _t(Db.prop.value?['telefone']),
        'tipo': tipo,
        'grupo': grupo,
        'titulo': titulo,
        'pedido_obs': obs,
        'solicitante': Db.autor?.nome ?? '',
        'fornecedor': {'nome': _t(f['nome']), 'telefone': _t(f['telefone']), 'contato_id': f['id']},
        'itens': [for (final i in itens) i.paraMapa()],
        'status': 'aberta',
        'visto': false,
        'criado_em': FieldValue.serverTimestamp(),
      };
      lote.set(colecao.doc(codigo), dados);
      criados.add(PedidoCotacao(codigo, {...dados, 'criado_em': DateTime.now()}));
    }
    // Sem await de propósito: sem sinal, grava no aparelho e envia depois.
    lote.commit().catchError((Object e) => debugPrint('Eito: falha ao gravar a cotação: $e'));
    return criados;
  }

  static Future<void> marcarVisto(PedidoCotacao p) async {
    if (p.visto) return;
    recebidas.value = [for (final r in recebidas.value) if (r.codigo != p.codigo) r];
    await colecao.doc(p.codigo).update({'visto': true}).catchError((Object e) => debugPrint('Eito: $e'));
  }

  static Future<void> excluirGrupo(GrupoCotacao g) async {
    final lote = Db.banco.batch();
    for (final p in g.pedidos) {
      lote.delete(colecao.doc(p.codigo));
    }
    await lote.commit();
  }
}

/// Só os números do telefone, com o 55 do Brasil (para o wa.me).
String? telefoneWhats(String telefone) {
  var n = telefone.replaceAll(RegExp(r'\D'), '');
  if (n.isEmpty) return null;
  if (n.startsWith('0')) n = n.substring(1);
  if (n.length <= 11) n = '55$n';
  return n;
}

/// Mensagem do WhatsApp para o fornecedor, com o link da cotação.
String textoWhatsCotacao(PedidoCotacao p) {
  final fazenda = _t(p.dados['fazenda']), fone = _t(p.dados['fazenda_telefone']);
  final quem = '${fazenda.isEmpty ? 'Nossa propriedade' : fazenda}${fone.isEmpty ? '' : ' (tel. $fone)'}';
  final itens = p.itens;
  return 'Olá, ${p.fornecedor}!\n'
      '$quem pede uma cotação de ${p.tipo.toLowerCase()} '
      '(${itens.length} ${itens.length == 1 ? 'item' : 'itens'}).\n'
      'Informe o preço por unidade de cada item: À vista, 30/60/90 dias e 90 dias direto. '
      'Deixe em branco o que não tiver o produto específico ou similar.\n'
      'No caso de produto SIMILAR, coloque o nome do produto em Observações.\n\n'
      'Preencha neste link, não precisa baixar nada:\n${p.link}\n\nObrigado!';
}

/// Endereço do WhatsApp para enviar a cotação (com o número, se houver).
Uri linkWhatsCotacao(PedidoCotacao p) {
  final n = telefoneWhats(p.telefone);
  final texto = Uri.encodeComponent(textoWhatsCotacao(p));
  return Uri.parse(n == null ? 'https://wa.me/?text=$texto' : 'https://wa.me/$n?text=$texto');
}
