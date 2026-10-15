// Lançamento por voz no curral: entende frases como "brinco 123 peso 450",
// "brinco 45 vacina aftosa", "brinco 45 prenhe", "brinco 45 leite 18 litros"
// e "chuva 12 milímetros", e grava no módulo certo.
import 'db.dart';
import 'leite.dart' show lancarOrdenha;

enum TipoVoz { pesagem, sanidade, diagnostico, leite, chuva }

class ComandoVoz {
  const ComandoVoz(this.tipo, {this.brinco, this.valor, this.produto, this.categoria});
  final TipoVoz tipo;
  final String? brinco;
  final double? valor;

  /// Produto da sanidade ou resultado do diagnóstico (Prenhe/Vazia).
  final String? produto;

  /// Categoria da sanidade: Vacinação, Antiparasitário ou Tratamento.
  final String? categoria;

  String get descricao {
    final b = brinco == null ? '' : 'Brinco $brinco · ';
    String n(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString().replaceAll('.', ',');
    return switch (tipo) {
      TipoVoz.pesagem => '${b}peso ${n(valor!)} kg',
      TipoVoz.sanidade => '$b${categoria!.toLowerCase()}: $produto',
      TipoVoz.diagnostico => '${b}diagnóstico: $produto',
      TipoVoz.leite => '${b}leite ${n(valor!)} L',
      TipoVoz.chuva => 'Chuva ${n(valor!)} mm',
    };
  }
}

const _acentos = {'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e', 'í': 'i', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ü': 'u', 'ç': 'c'};
String semAcento(String s) => s.toLowerCase().split('').map((c) => _acentos[c] ?? c).join();

const _unidades = {
  'zero': 0, 'um': 1, 'uma': 1, 'dois': 2, 'duas': 2, 'tres': 3, 'quatro': 4, 'cinco': 5, 'seis': 6, 'sete': 7,
  'oito': 8, 'nove': 9, 'dez': 10, 'onze': 11, 'doze': 12, 'treze': 13, 'quatorze': 14, 'catorze': 14,
  'quinze': 15, 'dezesseis': 16, 'dezessete': 17, 'dezoito': 18, 'dezenove': 19, 'vinte': 20, 'trinta': 30,
  'quarenta': 40, 'cinquenta': 50, 'sessenta': 60, 'setenta': 70, 'oitenta': 80, 'noventa': 90, 'cem': 100,
  'cento': 100, 'duzentos': 200, 'duzentas': 200, 'trezentos': 300, 'quatrocentos': 400, 'quinhentos': 500,
  'seiscentos': 600, 'setecentos': 700, 'oitocentos': 800, 'novecentos': 900,
};

/// Troca números falados por extenso ("quatrocentos e cinquenta") por dígitos
/// e junta decimais ("18 vírgula 5" ou "18,5").
List<String> _tokens(String frase) {
  final palavras = semAcento(frase)
      .replaceAllMapped(RegExp(r'(\d)\.(\d{3})\b'), (m) => '${m[1]}${m[2]}') // 1.200
      .replaceAll(RegExp(r'[^a-z0-9,\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  final r = <String>[];
  var i = 0;
  while (i < palavras.length) {
    final p = palavras[i];
    if (_unidades.containsKey(p) || (p == 'mil' && r.isEmpty)) {
      var total = 0, parcial = 0;
      while (i < palavras.length) {
        final w = palavras[i];
        if (_unidades.containsKey(w)) {
          parcial += _unidades[w]!;
        } else if (w == 'mil') {
          total += (parcial == 0 ? 1 : parcial) * 1000;
          parcial = 0;
        } else if (w == 'e' && i + 1 < palavras.length && _unidades.containsKey(palavras[i + 1])) {
          // "quatrocentos e cinquenta"
        } else {
          break;
        }
        i++;
      }
      r.add('${total + parcial}');
    } else {
      r.add(p);
      i++;
    }
  }
  // Decimais: "18 virgula 5" e "18,5".
  final d = <String>[];
  for (var k = 0; k < r.length; k++) {
    if ((r[k] == 'virgula' || r[k] == 'ponto') && d.isNotEmpty && _num(d.last) != null && k + 1 < r.length && _num(r[k + 1]) != null) {
      d.last = '${d.last}.${r[k + 1]}';
      k++;
    } else if (r[k] == 'meio' && d.length >= 2 && d.last == 'e' && _num(d[d.length - 2]) != null) {
      d.removeLast();
      d.last = '${_num(d.last)! + 0.5}';
    } else {
      d.add(r[k].replaceAll(',', '.'));
    }
  }
  return d;
}

double? _num(String s) => double.tryParse(s);

double? _numeroDepois(List<String> t, int i) {
  for (var k = i + 1; k < t.length && k <= i + 2; k++) {
    final n = _num(t[k]);
    if (n != null) return n;
  }
  return null;
}

/// Número antes de uma unidade ("450 quilos", "18 litros").
double? _numeroAntes(List<String> t, Set<String> unidades) {
  for (var k = 1; k < t.length; k++) {
    if (unidades.contains(t[k]) && _num(t[k - 1]) != null) return _num(t[k - 1]);
  }
  return null;
}

const _produtos = <String, List<String>>{
  'Vacinação': ['Aftosa', 'Antitetânica', 'Botulismo', 'Brucelose', 'Clostridiose', 'Leptospirose', 'Raiva'],
  'Antiparasitário': ['Abamectina', 'Albendazol', 'Doramectina', 'Eprinomectina', 'Ivermectina'],
  'Tratamento': ['Antibiótico', 'Anti-inflamatório', 'Analgésico', 'Complexo vitamínico e mineral'],
};

String _capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Lê a frase falada. Retorna null quando não entendeu.
ComandoVoz? interpretarVoz(String frase, {List<String> insumos = const []}) {
  final t = _tokens(frase);
  if (t.isEmpty) return null;

  if (t.contains('chuva') || t.contains('choveu')) {
    final mm = _numeroDepois(t, t.indexWhere((w) => w == 'chuva' || w == 'choveu')) ??
        _numeroAntes(t, {'milimetros', 'milimetro', 'mm'});
    return mm == null ? null : ComandoVoz(TipoVoz.chuva, valor: mm);
  }

  // Brinco: depois de "brinco/animal/vaca/boi/numero" ou a primeira palavra, se for número.
  String? brinco;
  var fim = 0;
  final ib = t.indexWhere((w) => const {'brinco', 'animal', 'vaca', 'boi', 'novilha', 'bezerro', 'numero'}.contains(w));
  if (ib >= 0 && ib + 1 < t.length) {
    brinco = t[ib + 1];
    fim = ib + 2;
  } else if (_num(t.first) != null) {
    brinco = t.first;
    fim = 1;
  }
  if (brinco == null) return null;
  if (brinco.endsWith('.0')) brinco = brinco.substring(0, brinco.length - 2);
  final resto = t.sublist(fim);
  String? palavra(Set<String> chaves) => resto.where(chaves.contains).firstOrNull;

  if (palavra({'prenhe', 'prenha', 'prenhes', 'positivo', 'positiva', 'cheia'}) != null) {
    return ComandoVoz(TipoVoz.diagnostico, brinco: brinco, produto: 'Prenhe');
  }
  if (palavra({'vazia', 'vazio', 'negativo', 'negativa'}) != null) {
    return ComandoVoz(TipoVoz.diagnostico, brinco: brinco, produto: 'Vazia');
  }

  final iPeso = resto.indexWhere((w) => w == 'peso' || w == 'pesou' || w == 'pesando');
  final peso = iPeso >= 0 ? _numeroDepois(resto, iPeso) : _numeroAntes(resto, {'quilos', 'quilo', 'kg', 'kilos'});
  if (peso != null) return ComandoVoz(TipoVoz.pesagem, brinco: brinco, valor: peso);

  final iLeite = resto.indexWhere((w) => w == 'leite' || w == 'ordenha' || w == 'deu');
  final litros = iLeite >= 0 ? _numeroDepois(resto, iLeite) : _numeroAntes(resto, {'litros', 'litro'});
  if (litros != null) return ComandoVoz(TipoVoz.leite, brinco: brinco, valor: litros);

  // Sanidade: "vacina aftosa", "vermifugo ivermectina", "remedio antibiotico".
  final iSan = resto.indexWhere((w) => const {
        'vacina', 'vacinou', 'vacinado', 'vacinada', 'vermifugo', 'vermifugou', 'remedio', 'medicamento', 'aplicou', 'tratamento',
      }.contains(w));
  if (iSan < 0) return null;
  final chave = resto[iSan];
  final nome = resto.sublist(iSan + 1).where((w) => !const {'de', 'da', 'do', 'contra', 'com'}.contains(w)).join(' ').trim();
  var categoria = chave.startsWith('vacin')
      ? 'Vacinação'
      : chave.startsWith('vermif')
          ? 'Antiparasitário'
          : 'Tratamento';
  String? produto;
  for (final e in _produtos.entries) {
    final p = e.value.where((p) => nome.isNotEmpty && (semAcento(p).startsWith(nome) || nome.startsWith(semAcento(p)))).firstOrNull;
    if (p != null) {
      produto = p;
      categoria = e.key;
      break;
    }
  }
  produto ??= insumos.where((i) => nome.isNotEmpty && semAcento(i).startsWith(nome)).firstOrNull;
  produto ??= nome.isEmpty ? (categoria == 'Antiparasitário' ? 'Vermífugo' : null) : _capitalizar(nome);
  if (produto == null) return null;
  return ComandoVoz(TipoVoz.sanidade, brinco: brinco, produto: produto, categoria: categoria);
}

/// Grava o comando. Retorna o texto do que foi feito ou lança [StateError] com o motivo.
Future<String> executarVoz(ComandoVoz c, {required String data}) async {
  if (c.tipo == TipoVoz.chuva) {
    await Db.inserir('chuvas', {'propriedade_id': Db.pid, 'data': data, 'mm': c.valor});
    return c.descricao;
  }
  final a = await Db.buscarPorCodigo(c.brinco!);
  if (a == null || a['status'] != 'Ativo') throw StateError('Brinco ${c.brinco} não encontrado entre os ativos.');
  final id = a['id'] as int;
  switch (c.tipo) {
    case TipoVoz.pesagem:
      await Db.registrarPesagem(id, c.valor!, data: data);
    case TipoVoz.sanidade:
      await Db.lancarSanidade([id], {'data': data, 'tipo': c.categoria, 'produto': c.produto});
    case TipoVoz.diagnostico:
      if (a['sexo'] != 'F') throw StateError('O brinco ${c.brinco} não é fêmea.');
      final pendente = [
        for (final r in Db.registros('reproducoes'))
          if (r['femea_id'] == id && r['diagnostico'] == 'Pendente') r,
      ]..sort((x, y) => '${y['data']}'.compareTo('${x['data']}'));
      if (pendente.isEmpty) throw StateError('O brinco ${c.brinco} não tem serviço esperando diagnóstico.');
      await Db.lancarDiagnostico(pendente.first['id'] as int, c.produto!, data);
    case TipoVoz.leite:
      if (a['sexo'] != 'F') throw StateError('O brinco ${c.brinco} não é fêmea.');
      await lancarOrdenha(id, data, c.valor);
    case TipoVoz.chuva:
      break;
  }
  return c.descricao;
}
