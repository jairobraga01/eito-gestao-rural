// Cadastro de fornecedores e compradores, com o histórico de negócios de cada um.
import 'db.dart';

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
