// Patrimônio da conta: rebanho (cabeças × valor de referência por categoria),
// terra (hectares × valor do hectare de cada propriedade), bens (máquinas,
// benfeitorias, veículos...) e, descontadas as dívidas em aberto, o
// patrimônio líquido. Os valores de referência ficam em config/patrimonio.
import '../util/util.dart' show categoriasF, categoriasM, sugerirCategoria;
import 'db.dart';
import 'dividas.dart' show saldoDevedor;

double _n(Object? v) => v is num ? v.toDouble() : 0;
int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String _t(Object? v) => v == null ? '' : '$v';

const tiposBem = ['Máquinas e implementos', 'Veículos', 'Benfeitorias e construções', 'Equipamentos', 'Outros'];

/// Categorias na ordem de exibição.
const categoriasRebanho = [...categoriasF, ...categoriasM];

Reg configPatrimonio() => Db.registro('config', 'patrimonio') ?? {};

Map<String, double> precosCategoria([Reg? cfg]) {
  final m = (cfg ?? configPatrimonio())['precos'];
  return {
    if (m is Map)
      for (final e in m.entries)
        if (e.value is num) '${e.key}': (e.value as num).toDouble(),
  };
}

Map<String, double> valorHectare([Reg? cfg]) {
  final m = (cfg ?? configPatrimonio())['terra'];
  return {
    if (m is Map)
      for (final e in m.entries)
        if (e.value is num) '${e.key}': (e.value as num).toDouble(),
  };
}

List<Reg> bens([Reg? cfg]) {
  final l = (cfg ?? configPatrimonio())['bens'];
  return [
    if (l is List)
      for (final b in l)
        if (b is Map) Map<String, Object?>.from(b),
  ];
}

/// Área total da propriedade em hectares (pastagem + agricultura + benfeitorias + APP/reserva).
double areaPropriedade(Reg p) =>
    _n(p['area_pastagem']) + _n(p['area_agricultura']) + _n(p['area_benfeitoria']) + _n(p['area_app']);

String categoriaDoAnimal(Reg a) {
  final c = _t(a['categoria']);
  if (c.isNotEmpty) return c;
  return sugerirCategoria(_t(a['sexo']) == 'F' ? 'F' : 'M', a['nascimento']);
}

class LinhaRebanho {
  LinhaRebanho(this.categoria, this.cabecas, this.preco);
  final String categoria;
  final int cabecas;
  final double? preco;
  double get valor => (preco ?? 0) * cabecas;
}

class LinhaTerra {
  LinhaTerra(this.propriedade, this.area, this.precoHa);
  final Reg propriedade;
  final double area;
  final double? precoHa;
  double get valor => (precoHa ?? 0) * area;
}

class Patrimonio {
  Patrimonio({required this.rebanho, required this.terra, required this.bens, required this.dividas});
  final List<LinhaRebanho> rebanho;
  final List<LinhaTerra> terra;
  final List<Reg> bens;
  final double dividas;

  double get totalRebanho => rebanho.fold(0, (s, l) => s + l.valor);
  double get totalTerra => terra.fold(0, (s, l) => s + l.valor);
  double get totalBens => bens.fold(0, (s, b) => s + _n(b['valor']));
  double get bruto => totalRebanho + totalTerra + totalBens;
  double get liquido => bruto - dividas;
  int get cabecas => rebanho.fold(0, (s, l) => s + l.cabecas);

  List<String> get semPreco => [for (final l in rebanho) if (l.preco == null && l.cabecas > 0) l.categoria];
  List<String> get semValorTerra => [
        for (final t in terra)
          if (t.precoHa == null) _t(t.propriedade['nome'])
      ];
}

/// Calcula o patrimônio de todas as propriedades da conta.
Patrimonio calcularPatrimonio() {
  final cfg = configPatrimonio();
  final precos = precosCategoria(cfg);
  final cont = <String, int>{};
  for (final a in Db.registros('animais')) {
    if ((a['status'] ?? 'Ativo') != 'Ativo') continue;
    final c = categoriaDoAnimal(a);
    cont[c] = (cont[c] ?? 0) + 1;
  }
  final ordem = [...categoriasRebanho, ...cont.keys.where((c) => !categoriasRebanho.contains(c))];
  final rebanho = [
    for (final c in ordem)
      if ((cont[c] ?? 0) > 0) LinhaRebanho(c, cont[c]!, precos[c]),
  ];
  final ha = valorHectare(cfg);
  final props = [...Db.registros('propriedades')]..sort((a, b) => _t(a['nome']).compareTo(_t(b['nome'])));
  final terra = [
    for (final p in props) LinhaTerra(p, areaPropriedade(p), ha['${_int(p['id'])}']),
  ];
  var dividas = 0.0;
  for (final d in Db.registros('dividas')) {
    dividas += saldoDevedor(d);
  }
  return Patrimonio(rebanho: rebanho, terra: terra, bens: bens(cfg), dividas: dividas);
}

Future<void> salvarPatrimonio({Map<String, double>? precos, Map<String, double>? terra, List<Reg>? listaBens}) async {
  final cfg = configPatrimonio();
  await Db.salvarConfig('patrimonio', {
    'precos': precos ?? precosCategoria(cfg),
    'terra': terra ?? valorHectare(cfg),
    'bens': listaBens ?? bens(cfg),
  });
}
