// Cadastro de fornecedores e compradores, com o histórico de negócios de cada um.
import 'db.dart';
import 'financeiro.dart' show csv;
import 'importar_animais.dart' show lerCsv;

const tiposContato = ['Fornecedor', 'Comprador', 'Os dois'];

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _n(Object? v) => v is num ? v.toDouble() : 0;
String _t(Object? v) => v == null ? '' : '$v';

List<Reg> contatos() => [
      for (final c in Db.registros('contatos'))
        if (_int(c['propriedade_id']) == Db.pid) c,
    ]..sort((a, b) => _t(a['nome']).toLowerCase().compareTo(_t(b['nome']).toLowerCase()));

/// O que o fornecedor vende (liga o cadastro às cotações e aos estoques).
const forneceOpcoes = ['Medicamentos', 'Insumos'];

/// O que o fornecedor marcou que vende (vazio = não marcou nada).
List<String> forneceDo(Reg c) => [for (final x in (c['fornece'] as List? ?? const [])) '$x'];

/// Fornecedores de medicamentos ou de insumos ([tipo] de [forneceOpcoes]).
/// Quem não marcou o que vende aparece nos dois.
List<Reg> fornecedoresDe(String tipo) => [
      for (final c in contatosPara('Fornecedor'))
        if (forneceDo(c).isEmpty || forneceDo(c).contains(tipo)) c,
    ];

/// Contatos que servem para [tipo] ('Fornecedor' ou 'Comprador').
List<Reg> contatosPara(String tipo) =>
    contatos().where((c) => _t(c['tipo']) == 'Os dois' || _t(c['tipo']) == tipo).toList();

bool _mesmo(Object? texto, Reg c) => _t(texto).trim().toLowerCase() == _t(c['nome']).trim().toLowerCase();

class HistoricoContato {
  int compras = 0, cabecasCompradas = 0, vendas = 0, cabecasVendidas = 0;
  double totalComprado = 0, totalVendido = 0;
  double contasAbertas = 0;
  String? ultimo;

  double? get precoMedioCompra => cabecasCompradas == 0 ? null : totalComprado / cabecasCompradas;
  double? get precoMedioVenda => cabecasVendidas == 0 ? null : totalVendido / cabecasVendidas;
}

/// Compras (pelo vendedor), vendas (pelo comprador) e contas em aberto ligadas ao nome do contato.
HistoricoContato historicoDoContato(Reg c) {
  final h = HistoricoContato();
  void data(Object? d) {
    final x = _t(d).length >= 10 ? _t(d).substring(0, 10) : '';
    if (x.isNotEmpty && (h.ultimo ?? '').compareTo(x) < 0) h.ultimo = x;
  }

  for (final e in Db.registros('entradas')) {
    if (_int(e['propriedade_id']) != Db.pid || e['tipo'] != 'Compra' || !_mesmo(e['origem'], c)) continue;
    h.compras++;
    h.cabecasCompradas += _int(e['quantidade']) ?? 0;
    h.totalComprado += _n(e['valor_total']);
    data(e['data']);
  }
  for (final s in Db.registros('saidas')) {
    if (_int(s['propriedade_id']) != Db.pid || s['tipo'] != 'Venda' || !_mesmo(s['destino'], c)) continue;
    h.vendas++;
    h.cabecasVendidas += _int(s['quantidade']) ?? 0;
    h.totalVendido += _n(s['valor_total']);
    data(s['data']);
  }
  for (final k in Db.registros('contas')) {
    if (_int(k['propriedade_id']) != Db.pid || !_mesmo(k['participante'], c)) continue;
    if (k['pago'] != true) h.contasAbertas += _n(k['valor']);
  }
  return h;
}

// ======================= Exportar e importar o cadastro =======================

const _colunas = ['nome', 'tipo', 'fornece', 'telefone', 'documento', 'cidade', 'obs'];

/// Planilha (CSV com ";") dos contatos de [lista], para levar a outra propriedade.
String planilhaContatos(List<Reg> lista) => csv(_colunas, [
      for (final c in lista)
        [c['nome'], c['tipo'], forneceDo(c).join(', '), c['telefone'], c['documento'], c['cidade'], c['obs']],
    ]);

String _soDigitos(Object? v) => _t(v).replaceAll(RegExp(r'\D'), '');
String _nomeChave(Object? v) => _t(v).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Já existe na propriedade atual um contato com o mesmo nome ou o mesmo telefone?
bool contatoRepetido(Reg novo, [List<Reg>? atuais]) {
  final n = _nomeChave(novo['nome']);
  final f = _soDigitos(novo['telefone']);
  for (final c in atuais ?? contatos()) {
    if (n.isNotEmpty && _nomeChave(c['nome']) == n) return true;
    if (f.length >= 8 && _soDigitos(c['telefone']) == f) return true;
  }
  return false;
}

/// Lê a planilha exportada (ou uma feita à mão com a coluna "nome").
/// [tipoPadrao] vale para as linhas sem tipo.
List<Reg> lerPlanilhaContatos(String texto, {String tipoPadrao = 'Fornecedor'}) {
  final tab = lerCsv(texto);
  if (tab.isEmpty) return const [];
  final cab = [for (final x in tab.first) _nomeChave(x)];
  final iNome = cab.indexOf('nome');
  if (iNome < 0) return const [];
  String col(List<String> l, String nome) {
    final i = cab.indexOf(nome);
    return i >= 0 && i < l.length ? l[i].trim() : '';
  }

  return [
    for (final l in tab.skip(1))
      if (col(l, 'nome').isNotEmpty)
        () {
          final tipo = tiposContato.firstWhere((t) => t.toLowerCase() == col(l, 'tipo').toLowerCase(),
              orElse: () => tipoPadrao);
          final vende = col(l, 'fornece').toLowerCase();
          return <String, Object?>{
            'nome': col(l, 'nome'),
            'tipo': tipo,
            'fornece': tipo == 'Comprador'
                ? null
                : [for (final o in forneceOpcoes) if (vende.contains(o.toLowerCase())) o],
            'telefone': col(l, 'telefone').isEmpty ? null : col(l, 'telefone'),
            'documento': col(l, 'documento').isEmpty ? null : col(l, 'documento'),
            'cidade': col(l, 'cidade').isEmpty ? null : col(l, 'cidade'),
            'obs': col(l, 'obs').isEmpty ? null : col(l, 'obs'),
          };
        }(),
  ];
}

/// Grava na propriedade atual os contatos que ainda não existem nela.
/// Devolve (gravados, repetidos).
Future<(int, int)> importarContatos(List<Reg> novos) async {
  final atuais = [...contatos()];
  var ok = 0, rep = 0;
  for (final n in novos) {
    if (contatoRepetido(n, atuais)) {
      rep++;
      continue;
    }
    final v = {
      for (final k in _colunas) k: n[k],
      'propriedade_id': Db.pid,
    };
    await Db.inserir('contatos', v);
    atuais.add(v);
    ok++;
  }
  return (ok, rep);
}

/// Contatos de outra propriedade da mesma conta.
List<Reg> contatosDaPropriedade(int propriedadeId) => [
      for (final c in Db.registros('contatos'))
        if (_int(c['propriedade_id']) == propriedadeId) c,
    ];
