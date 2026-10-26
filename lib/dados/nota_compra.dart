// Leitura de nota de compra (XML da NF-e, ou texto lido do PDF e da foto) para
// lançar insumos e medicamentos com quantidade e preço.
import 'db.dart';
import 'estoque.dart';
import 'proteinado.dart' show insumos, lancarPrecoInsumo;

class ItemNota {
  ItemNota({
    required this.descricao,
    required this.qtd,
    required this.valorUnit,
    this.unidadeNota = '',
    this.categoria = 'Ração e ingredientes',
    this.unidade = 'kg',
    this.embalagem = 1,
    this.usar = true,
  });

  String descricao;

  /// Quantidade comprada, na unidade da nota (sacos, frascos, kg).
  double qtd;

  /// Preço de cada unidade da nota.
  double valorUnit;
  String unidadeNota;
  String categoria;

  /// Unidade de controle do estoque (kg, dose, ml, un).
  String unidade;

  /// Quanto cabe em cada unidade da nota, na unidade do estoque (saco de 25 kg = 25).
  double embalagem;
  bool usar;

  double get total => qtd * valorUnit;

  /// Quantidade que entra no estoque, na unidade de controle.
  double get qtdEstoque => qtd * embalagem;
}

class NotaCompra {
  NotaCompra({required this.itens, this.fornecedor = '', this.data});
  final List<ItemNota> itens;
  final String fornecedor;

  /// Data da nota em AAAA-MM-DD.
  final String? data;
}

String _semAcento(String s) {
  const de = 'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇç';
  const para = 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b.toString();
}

/// Número no formato da nota: "1.234,56" (texto) ou "1234.56" (XML).
double? lerValor(String s) {
  var t = s.trim().replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    t = t.replaceAll('.', '');
  }
  return double.tryParse(t);
}

String? _dataIso(String s) {
  final m = RegExp(r'(\d{2})/(\d{2})/(\d{4})').firstMatch(s);
  if (m != null) return '${m[3]}-${m[2]}-${m[1]}';
  final x = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  return x == null ? null : x[0];
}

/// Categoria provável pelo nome do produto.
String categoriaPorNome(String descricao) {
  final d = _semAcento(descricao).toUpperCase();
  if (RegExp(r'VACINA|AFTOSA|BRUCELOSE|CLOSTRID|RAIVA|IBR|BVD|LEPTOSP').hasMatch(d)) return 'Vacina';
  if (RegExp(r'IVERMECTINA|VERMIFUGO|ANTIBIOTIC|OXITETRA|PENICILINA|ANTI-?INFLAM|CARRAPATICIDA|MOSQUICIDA|'
          r'BERNICIDA|VITAMINA|ADE\b|INJETAVEL|FLUNIXIN|DIPIRONA|CICATRIZ|PULVERIZ|SERINGA|AGULHA|HORMONIO|PROGESTERONA|BENZOATO')
      .hasMatch(d)) {
    return 'Medicamento e vermífugo';
  }
  if (RegExp(r'SAL MINERAL|SAL PROTEIN|MINERAL|NUCLEO|SAL BRANCO|SAL COMUM').hasMatch(d)) return 'Sal mineral';
  if (RegExp(r'MILHO|SORGO|FARELO|SOJA|ALGODAO|CALCARIO|UREIA|RACAO|CAROCO|POLPA|SILAGEM|FARINHA|PROTEINADO|CASCA')
      .hasMatch(d)) {
    return 'Ração e ingredientes';
  }
  return 'Outros';
}

String _unidadeDaNota(String u) => switch (u.toUpperCase().replaceAll('.', '')) {
      'KG' || 'QUILO' => 'KG',
      'G' => 'G',
      'L' || 'LT' || 'LITRO' => 'L',
      'ML' => 'ML',
      'DS' || 'DOSE' || 'DOSES' => 'DOSE',
      'SC' || 'SACO' || 'SACA' => 'SC',
      _ => u.toUpperCase(),
    };

/// Define unidade de controle e tamanho da embalagem pela unidade da nota e pelo nome ("SAL 25KG", "VACINA 50 DOSES").
void _ajustarEmbalagem(ItemNota i) {
  final un = _unidadeDaNota(i.unidadeNota);
  final d = _semAcento(i.descricao).toUpperCase();
  final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(KG|G|ML|L|LT|DOSES?|DS)\b').firstMatch(d);
  final tam = m == null ? null : lerValor(m[1]!);
  final u = m == null ? '' : _unidadeDaNota(m[2]!);
  if (un == 'KG') {
    i.unidade = 'kg';
    i.embalagem = 1;
  } else if (un == 'L') {
    i.unidade = 'ml';
    i.embalagem = 1000;
  } else if (un == 'ML') {
    i.unidade = 'ml';
    i.embalagem = 1;
  } else if (un == 'DOSE') {
    i.unidade = 'dose';
    i.embalagem = 1;
  } else if (tam != null && tam > 0) {
    switch (u) {
      case 'KG':
        i.unidade = 'kg';
        i.embalagem = tam;
      case 'G':
        i.unidade = 'kg';
        i.embalagem = tam / 1000;
      case 'L':
        i.unidade = 'ml';
        i.embalagem = tam * 1000;
      case 'ML':
        i.unidade = 'ml';
        i.embalagem = tam;
      case 'DOSE':
        i.unidade = 'dose';
        i.embalagem = tam;
    }
  } else {
    i.unidade = i.categoria == 'Vacina' ? 'dose' : (i.categoria == 'Medicamento e vermífugo' ? 'ml' : 'un');
    i.embalagem = 1;
    if (i.categoria == 'Sal mineral' || i.categoria == 'Ração e ingredientes') i.unidade = 'kg';
    // Saco sem o peso no nome: não dá para saber quantos kg; a pessoa informa na tela.
    if (un == 'SC' && i.unidade == 'kg') i.embalagem = 0;
  }
}

ItemNota _item(String descricao, double qtd, double valorUnit, String unidadeNota) {
  final i = ItemNota(
    descricao: descricao.trim(),
    qtd: qtd,
    valorUnit: valorUnit,
    unidadeNota: unidadeNota,
    categoria: categoriaPorNome(descricao),
  );
  _ajustarEmbalagem(i);
  return i;
}

String? _tag(String bloco, String tag) {
  final m = RegExp('<$tag>([^<]*)</$tag>').firstMatch(bloco);
  return m?[1]?.trim();
}

String _desfazerEntidades(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");

/// Lê o XML da NF-e: dados exatos, sem adivinhar nada.
NotaCompra? lerNotaXml(String xml) {
  final blocos = RegExp(r'<det\b[^>]*>(.*?)</det>', dotAll: true).allMatches(xml).toList();
  if (blocos.isEmpty) return null;
  final itens = <ItemNota>[];
  for (final b in blocos) {
    final t = b[1]!;
    final nome = _tag(t, 'xProd');
    // No XML o ponto é sempre decimal ("2.500" = 2,5).
    final q = double.tryParse((_tag(t, 'qCom') ?? '').trim());
    final v = double.tryParse((_tag(t, 'vUnCom') ?? '').trim());
    if (nome == null || q == null || v == null || q <= 0) continue;
    itens.add(_item(_desfazerEntidades(nome), q, v, _tag(t, 'uCom') ?? ''));
  }
  if (itens.isEmpty) return null;
  final emit = RegExp(r'<emit>(.*?)</emit>', dotAll: true).firstMatch(xml)?[1] ?? '';
  final data = _tag(xml, 'dhEmi') ?? _tag(xml, 'dEmi');
  return NotaCompra(itens: itens, fornecedor: _desfazerEntidades(_tag(emit, 'xNome') ?? ''), data: data == null ? null : _dataIso(data));
}

const _unidades = r'KG|UN|UND|UNID|PC|PÇ|SC|SACO|SACA|L|LT|ML|DS|DOSE|DOSES|FR|FRASCO|CX|CAIXA|G|PCT|BD|GL';
const _numero = r'\d{1,3}(?:\.\d{3})*,\d{2,4}|\d+,\d{2,4}|\d+(?:\.\d{2,4})?';

/// Lê o texto de um PDF ou foto (DANFE, nota de balcão, recibo): uma linha por item,
/// com descrição, quantidade, unidade, preço e total. Confira sempre antes de lançar.
NotaCompra lerNotaTexto(String texto) {
  final linhas = texto.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final itens = <ItemNota>[];
  // 1) descrição, quantidade, unidade, valor unitário, valor total.
  final comUnidade = RegExp(
      '^(?:\\d{1,3}\\s+)?(?:\\d{4,14}\\s+)?(.+?)\\s+(\\d+(?:[.,]\\d+)?)\\s*($_unidades)\\.?\\s+(?:R\\\$\\s*)?($_numero)\\s+(?:R\\\$\\s*)?($_numero)\\s*\$',
      caseSensitive: false);
  // 2) descrição, quantidade, valor unitário, valor total (sem unidade).
  final semUnidade = RegExp(
      '^(?:\\d{1,3}\\s+)?(?:\\d{4,14}\\s+)?([A-Za-zÀ-ú].+?)\\s+(\\d+(?:[.,]\\d+)?)\\s+(?:R\\\$\\s*)?($_numero)\\s+(?:R\\\$\\s*)?($_numero)\\s*\$');
  for (final l in linhas) {
    final a = comUnidade.firstMatch(l);
    if (a != null) {
      final q = lerValor(a[2]!), v = lerValor(a[4]!), t = lerValor(a[5]!);
      if (q != null && v != null && q > 0 && _coerente(q, v, t)) {
        itens.add(_item(a[1]!, q, v, a[3]!));
        continue;
      }
    }
    final b = semUnidade.firstMatch(l);
    if (b != null) {
      final q = lerValor(b[2]!), v = lerValor(b[3]!), t = lerValor(b[4]!);
      if (q != null && v != null && q > 0 && _coerente(q, v, t) && RegExp(r'[A-Za-zÀ-ú]{3}').hasMatch(b[1]!)) {
        itens.add(_item(b[1]!, q, v, ''));
      }
    }
  }
  final data = _dataIso(texto);
  final forn = RegExp(r'^[A-ZÀ-Ú0-9 .&\-]{6,}(LTDA|S/?A|ME|EPP|EIRELI)\b.*$', multiLine: true).firstMatch(texto)?[0]?.trim() ?? '';
  return NotaCompra(itens: itens, fornecedor: forn, data: data);
}

/// Confere se quantidade × preço bate com o total da linha (tolerando arredondamento).
bool _coerente(double q, double v, double? t) => t != null && ((q * v) - t).abs() <= 0.06 + t * 0.01;

/// Insumo já cadastrado com nome igual ou parecido (e, se informada, na mesma
/// [unidade] de controle). Parecido = um nome começa pelo outro, palavra inteira,
/// e só um insumo serve; "FARELO DE MILHO" não soma no "MILHO".
Reg? insumoParecido(String descricao, {String? unidade}) {
  String norm(String s) => _semAcento(s).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final alvo = norm(descricao);
  if (alvo.isEmpty) return null;
  final parciais = <Reg>[];
  for (final i in insumos()) {
    if (unidade != null && unidadeInsumo(i) != unidade) continue;
    final n = norm('${i['nome'] ?? ''}');
    if (n.isEmpty) continue;
    if (n == alvo) return i;
    if (alvo.startsWith('$n ') || n.startsWith('$alvo ')) parciais.add(i);
  }
  return parciais.length == 1 ? parciais.single : null;
}

/// Lança a nota: cria o insumo que ainda não existe, dá entrada no estoque e registra o preço.
/// Devolve quantos itens foram lançados.
Future<int> lancarNota(NotaCompra nota, {required String data}) async {
  var n = 0;
  final semTamanho = [for (final i in nota.itens) if (i.usar && i.qtd > 0 && i.embalagem <= 0) i.descricao];
  if (semTamanho.isNotEmpty) {
    throw 'informe quanto tem cada embalagem (toque em Corrigir): ${semTamanho.join(', ')}';
  }
  for (final i in nota.itens.where((x) => x.usar && x.qtd > 0)) {
    final nome = i.descricao.trim();
    if (nome.isEmpty) continue;
    final existente = insumoParecido(nome, unidade: i.unidade);
    final int id;
    if (existente != null) {
      id = existente['id'] as int;
    } else {
      id = await Db.inserir('insumos', {
        'propriedade_id': Db.pid,
        'nome': nome,
        'categoria': i.categoria,
        'unidade': i.unidade,
        'preco_saco': i.valorUnit,
        'kg_saco': i.embalagem,
      });
    }
    await entradaEstoque(id, i.qtdEstoque,
        data: data, obs: nota.fornecedor.isEmpty ? 'Nota de compra' : 'Nota de compra: ${nota.fornecedor}');
    if (i.valorUnit > 0 && i.embalagem > 0) {
      await lancarPrecoInsumo(id, data: data, precoEmbalagem: i.valorUnit, kgEmbalagem: i.embalagem);
    }
    n++;
  }
  return n;
}

/// Valor total do documento (nota, cupom ou recibo). Procura "valor total da nota",
/// "total a pagar", "a quantia de" etc. Sem rótulo, soma os itens lidos.
double? totalDoDocumento(String texto, {NotaCompra? nota}) {
  final xml = RegExp(r'<vNF>\s*([\d.]+)\s*</vNF>').firstMatch(texto);
  if (xml != null) return double.tryParse(xml[1]!);
  final linhas = texto.split(RegExp(r'[\r\n]+')).map((l) => _semAcento(l).toUpperCase()).toList();
  final valor = RegExp(r'\d{1,3}(?:\.\d{3})+,\d{2}|\d+,\d{2}');
  double? ultimo(String l) {
    final ms = valor.allMatches(l).toList();
    return ms.isEmpty ? null : lerValor(ms.last[0]!);
  }

  const rotulos = [
    'VALOR TOTAL DA NOTA', 'V. TOTAL DA NOTA', 'TOTAL DA NOTA', 'TOTAL A PAGAR', 'VALOR A PAGAR',
    'VALOR PAGO', 'TOTAL GERAL', 'QUANTIA DE', 'IMPORTANCIA DE', 'VALOR TOTAL', 'TOTAL',
  ];
  for (final r in rotulos) {
    for (var i = 0; i < linhas.length; i++) {
      final k = linhas[i].indexOf(r);
      if (k < 0) continue;
      // Valor na mesma linha, depois do rótulo; senão na linha de baixo (DANFE).
      final v = ultimo(linhas[i].substring(k)) ?? (i + 1 < linhas.length ? ultimo(linhas[i + 1]) : null);
      if (v != null && v > 0) return v;
    }
  }
  final soma = nota?.itens.fold<double>(0, (s, i) => s + i.total) ?? 0;
  return soma > 0 ? double.parse(soma.toStringAsFixed(2)) : null;
}
