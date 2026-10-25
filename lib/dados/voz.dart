// Lançamento por voz: entende frases como "brinco 123 peso 450",
// "brinco 45 vacina aftosa", "brinco 45 prenhe", "brinco 45 leite 18 litros",
// "vaca 12 inseminada touro Bravo", "vaca 12 pariu macho brinco 300",
// "brinco 45 morreu picada de cobra", "brinco 45 escore 3 e meio",
// "brinco 45 piquete 3", "despesa 350 reais diesel", "entrada 20 sal mineral"
// e "chuva 12 milímetros", e grava no módulo certo.
import 'db.dart';
import 'estoque.dart' show entradaEstoque;
import 'gestao.dart' show categoriasCusto;
import 'indicadores.dart' show lancarEcc;
import 'leite.dart' show lancarOrdenha;

enum TipoVoz { pesagem, sanidade, diagnostico, leite, chuva, inseminacao, parto, morte, escore, pasto, despesa, estoque }

class ComandoVoz {
  const ComandoVoz(this.tipo, {this.brinco, this.valor, this.produto, this.categoria, this.cria});

  /// Brinco da cria, no parto.
  final String? cria;
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
      TipoVoz.inseminacao => '$b${categoria == 'Monta natural' ? 'monta natural' : 'inseminação'}${produto == null ? '' : ' · touro $produto'}',
      TipoVoz.parto => '${b}pariu ${produto == 'F' ? 'fêmea' : 'macho'} · cria $cria',
      TipoVoz.morte => '${b}morte${produto == null ? '' : ': $produto'}',
      TipoVoz.escore => '${b}escore ${n(valor!)}',
      TipoVoz.pasto => '${b}para o piquete $produto',
      TipoVoz.despesa => 'Despesa R\$ ${n(valor!)} · $produto ($categoria)',
      TipoVoz.estoque => 'Entrada no estoque: ${n(valor!)} $produto',
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
      .replaceAll(RegExp(r',(?!\d)'), ' ') // "brinco 45, peso 450"
      .replaceAll(RegExp(r'[^a-z0-9,\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  final r = <String>[];
  var i = 0;
  while (i < palavras.length) {
    final p = palavras[i];
    if (_unidades.containsKey(p) || p == 'mil') {
      var total = 0, parcial = 0, ultimo = 0;
      while (i < palavras.length) {
        final w = palavras[i];
        if (_unidades.containsKey(w)) {
          final v = _unidades[w]!;
          // Só soma o que compõe um número ("cento e vinte e cinco"); "um dois três" são três números.
          final compoe = parcial == 0 ||
              (ultimo >= 100 && ultimo % 100 == 0 && v < 100) ||
              (ultimo >= 20 && ultimo < 100 && ultimo % 10 == 0 && v < 10);
          if (!compoe) break;
          parcial += v;
          ultimo = v;
        } else if (w == 'mil') {
          total += (parcial == 0 ? 1 : parcial) * 1000;
          parcial = 0;
          ultimo = 0;
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

  // Despesa: "despesa 350 reais diesel", "gastei 120 com sal".
  final iDesp = t.indexWhere((w) => const {'despesa', 'gastei', 'gasto', 'paguei'}.contains(w));
  if (iDesp >= 0) {
    final v = _numeroDepois(t, iDesp) ?? _numeroAntes(t, {'reais', 'real'});
    if (v == null) return null;
    final desc = t
        .sublist(iDesp + 1)
        .where((w) => _num(w) == null && !const {'reais', 'real', 'de', 'com', 'em', 'no', 'na', 'o', 'a'}.contains(w))
        .join(' ');
    if (desc.isEmpty) return null;
    return ComandoVoz(TipoVoz.despesa, valor: v, produto: _capitalizar(desc), categoria: _categoriaDespesa(desc));
  }

  // Entrada no estoque: "entrada 20 sal mineral", "chegou 10 vacina aftosa".
  final iEst = t.indexWhere((w) => const {'entrada', 'chegou', 'comprei'}.contains(w));
  if (iEst >= 0 && !t.contains('brinco')) {
    final q = _numeroDepois(t, iEst);
    if (q == null) return null;
    final nome = t
        .sublist(iEst + 1)
        .where((w) => _num(w) == null && !const {'de', 'do', 'da', 'no', 'estoque', 'sacos', 'saco', 'quilos', 'kg', 'doses', 'litros', 'frascos'}.contains(w))
        .join(' ');
    final insumo = insumos.where((i) => nome.isNotEmpty && (semAcento(i).startsWith(nome) || nome.startsWith(semAcento(i)))).firstOrNull;
    if (insumo == null) return null;
    return ComandoVoz(TipoVoz.estoque, valor: q, produto: insumo);
  }

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
    var k = ib + 1;
    while (k + 1 < t.length && const {'brinco', 'numero', 'animal'}.contains(t[k])) {
      k++; // "brinco número 45"
    }
    brinco = t[k];
    fim = k + 1;
    // Número falado dígito a dígito: "brinco 1 2 3" = 123.
    if (RegExp(r'^\d$').hasMatch(brinco)) {
      final sb = StringBuffer(brinco);
      while (fim < t.length && RegExp(r'^\d$').hasMatch(t[fim])) {
        sb.write(t[fim]);
        fim++;
      }
      brinco = sb.toString();
    }
  } else if (_num(t.first) != null) {
    brinco = t.first;
    fim = 1;
  }
  if (brinco == null) return null;
  if (brinco.endsWith('.0')) brinco = brinco.substring(0, brinco.length - 2);
  final resto = t.sublist(fim);
  String? palavra(Set<String> chaves) => resto.where(chaves.contains).firstOrNull;

  // Parto: "vaca 12 pariu macho brinco 300".
  if (palavra({'pariu', 'parto', 'nasceu', 'pario'}) != null) {
    final sexo = palavra({'femea', 'bezerra', 'novilha'}) != null ? 'F' : palavra({'macho', 'bezerro'}) != null ? 'M' : null;
    final ic = resto.indexWhere((w) => w == 'brinco' || w == 'cria');
    final cria = ic >= 0 && ic + 1 < resto.length ? resto[ic + 1].replaceAll(RegExp(r'\.0$'), '') : null;
    if (sexo == null || cria == null) return null;
    return ComandoVoz(TipoVoz.parto, brinco: brinco, produto: sexo, cria: cria);
  }
  // Inseminação ou monta: "vaca 12 inseminada touro Bravo".
  final iIa = resto.indexWhere((w) => const {'inseminada', 'inseminei', 'inseminacao', 'inseminar', 'ia', 'iatf', 'monta', 'cobertura', 'coberta'}.contains(w));
  if (iIa >= 0) {
    final it = resto.indexWhere((w) => w == 'touro' || w == 'semen');
    final touro = it >= 0 ? resto.sublist(it + 1).join(' ').trim() : '';
    final tipo = const {'monta', 'cobertura', 'coberta'}.contains(resto[iIa])
        ? 'Monta natural'
        : resto[iIa] == 'iatf'
            ? 'IATF'
            : 'IA';
    return ComandoVoz(TipoVoz.inseminacao, brinco: brinco, categoria: tipo, produto: touro.isEmpty ? null : _capitalizar(touro));
  }
  // Morte: "brinco 45 morreu picada de cobra".
  final iMorte = resto.indexWhere((w) => const {'morreu', 'morte', 'morto', 'morta'}.contains(w));
  if (iMorte >= 0) {
    final causa = resto.sublist(iMorte + 1).where((w) => !const {'de', 'por', 'com'}.contains(w)).join(' ').trim();
    return ComandoVoz(TipoVoz.morte, brinco: brinco, produto: causa.isEmpty ? null : _capitalizar(causa));
  }
  // Escore de condição corporal: "brinco 45 escore 3 e meio".
  final iEcc = resto.indexWhere((w) => w == 'escore' || w == 'ecc' || w == 'condicao');
  if (iEcc >= 0) {
    final v = _numeroDepois(resto, iEcc);
    return v == null ? null : ComandoVoz(TipoVoz.escore, brinco: brinco, valor: v);
  }
  // Mudar de pasto: "brinco 45 piquete 3", "brinco 45 pasto da grota".
  final iPasto = resto.indexWhere((w) => w == 'piquete' || w == 'pasto' || w == 'invernada');
  if (iPasto >= 0 && iPasto + 1 < resto.length) {
    final nome = resto.sublist(iPasto + 1).where((w) => !const {'da', 'do', 'de'}.contains(w)).join(' ');
    if (nome.isNotEmpty) return ComandoVoz(TipoVoz.pasto, brinco: brinco, produto: nome);
  }

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

String _categoriaDespesa(String d) {
  bool tem(List<String> ps) => ps.any(d.contains);
  final c = tem(['diesel', 'gasolina', 'oleo', 'trator', 'maquina', 'pneu', 'combustivel'])
      ? 'Combustível e máquinas'
      : tem(['sal', 'racao', 'milho', 'soja', 'farelo', 'silagem', 'proteinado'])
          ? 'Ração e sal'
          : tem(['vacina', 'remedio', 'vermifugo', 'veterinario', 'medicamento'])
              ? 'Sanidade'
              : tem(['salario', 'diaria', 'diarista', 'peao', 'empreita'])
                  ? 'Mão de obra'
                  : tem(['arrendamento', 'pasto', 'adubo', 'semente', 'calcario', 'cerca'])
                      ? 'Pastagem e arrendamento'
                      : 'Outros';
  assert(categoriasCusto.contains(c));
  return c;
}

/// Grava o comando. Retorna o texto do que foi feito ou lança [StateError] com o motivo.
Future<String> executarVoz(ComandoVoz c, {required String data}) async {
  if (c.tipo == TipoVoz.chuva) {
    await Db.inserir('chuvas', {'propriedade_id': Db.pid, 'data': data, 'mm': c.valor});
    return c.descricao;
  }
  if (c.tipo == TipoVoz.despesa) {
    if (Db.ehCampo) throw StateError('Seu acesso não lança despesas. Peça ao dono ou ao gerente.');
    if (c.valor == null || c.valor! <= 0) throw StateError('Valor da despesa não entendido.');
    await Db.inserir('custos', {
      'propriedade_id': Db.pid,
      'categoria': c.categoria,
      'descricao': c.produto,
      'valor': c.valor,
      'data': data,
    });
    return c.descricao;
  }
  if (c.tipo == TipoVoz.estoque) {
    final i = Db.registros('insumos').where((x) => x['propriedade_id'] == Db.pid && x['nome'] == c.produto).firstOrNull;
    if (i == null) throw StateError('Insumo ${c.produto} não encontrado.');
    if (c.valor == null || c.valor! <= 0) throw StateError('Quantidade não entendida.');
    await entradaEstoque(i['id'] as int, c.valor!, data: data, obs: 'Lançado por voz');
    return '${c.descricao} ${i['unidade'] ?? ''}'.trim();
  }
  final a = await Db.buscarPorCodigo(c.brinco!, soDestaFazenda: true);
  if (a == null || a['status'] != 'Ativo') throw StateError('Brinco ${c.brinco} não encontrado entre os ativos desta fazenda.');
  final id = a['id'] as int;
  if (c.tipo == TipoVoz.pesagem && (c.valor == null || c.valor! <= 0 || c.valor! > 2000)) {
    throw StateError('Peso ${c.valor} kg fora do normal. Fale de novo.');
  }
  if (c.tipo == TipoVoz.leite && (c.valor == null || c.valor! <= 0 || c.valor! > 100)) {
    throw StateError('${c.valor} litros fora do normal. Fale de novo.');
  }
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
    case TipoVoz.inseminacao:
      if (a['sexo'] != 'F') throw StateError('O brinco ${c.brinco} não é fêmea.');
      try {
        await Db.registrarInseminacao(femeaId: id, data: data, tipo: c.categoria ?? 'IA', touro: c.produto);
      } on RegistroDuplicado catch (e) {
        throw StateError(e.mensagem);
      }
    case TipoVoz.parto:
      if (a['sexo'] != 'F') throw StateError('O brinco ${c.brinco} não é fêmea.');
      try {
        await Db.registrarNascimento(maeId: id, data: data, brinco: c.cria!, sexo: c.produto!);
      } on RegistroDuplicado catch (e) {
        throw StateError(e.mensagem);
      }
    case TipoVoz.morte:
      if (Db.ehCampo || Db.ehContador) throw StateError('Seu acesso não registra morte. Avise o dono ou o gerente.');
      await Db.registrarSaida({'tipo': 'Morte', 'data': data, 'causa': c.produto}, [id]);
    case TipoVoz.escore:
      if (c.valor == null || c.valor! < 1 || c.valor! > 5) throw StateError('Escore vai de 1 a 5.');
      await lancarEcc(id, data, c.valor!);
    case TipoVoz.pasto:
      final nome = semAcento(c.produto!);
      final piquetes = [for (final p in Db.registros('piquetes')) if (p['propriedade_id'] == Db.pid) p];
      final p = piquetes.where((p) => semAcento('${p['nome'] ?? ''}') == nome).firstOrNull ??
          piquetes.where((p) => semAcento('${p['nome'] ?? ''}').endsWith(' $nome')).firstOrNull ??
          piquetes.where((p) => semAcento('${p['nome'] ?? ''}').contains(nome)).firstOrNull;
      if (p == null) throw StateError('Piquete "${c.produto}" não encontrado.');
      await Db.moverAnimais([a], {'piquete_id': p['id']}, data);
      return '${c.brinco} · para o piquete ${p['nome']}';
    case TipoVoz.chuva:
    case TipoVoz.despesa:
    case TipoVoz.estoque:
      break;
  }
  return c.descricao;
}

/// Uma mensagem colada do WhatsApp, já interpretada.
class MensagemWhatsApp {
  MensagemWhatsApp(this.texto, this.data, this.autor, this.comando);
  final String texto;

  /// Data da mensagem (aaaa-mm-dd) quando veio no cabeçalho do WhatsApp.
  final String? data;
  final String? autor;
  final ComandoVoz? comando;
}

/// Lê mensagens copiadas ou exportadas do WhatsApp. Aceita as linhas
/// "[25/10/2026 14:20] Zé: brinco 45 peso 450", "25/10/2026 14:20 - Zé: ..."
/// e frases soltas, uma por linha.
List<MensagemWhatsApp> lerConversaWhatsApp(String conversa, {List<String> insumos = const []}) {
  final cab = RegExp(r'^\[?(\d{1,2})/(\d{1,2})/(\d{2,4})[ ,]+\d{1,2}:\d{2}(?::\d{2})?\]?\s*-?\s*(?:([^:]{1,40}):\s*)?');
  final r = <MensagemWhatsApp>[];
  for (var linha in conversa.split(RegExp(r'\r?\n'))) {
    linha = linha.replaceAll('‎', '').trim();
    if (linha.isEmpty) continue;
    String? data, autor;
    final m = cab.firstMatch(linha);
    if (m != null) {
      var ano = int.parse(m[3]!);
      if (ano < 100) ano += 2000;
      data = '$ano-${m[2]!.padLeft(2, '0')}-${m[1]!.padLeft(2, '0')}';
      autor = m[4]?.trim();
      linha = linha.substring(m.end).trim();
    }
    if (linha.isEmpty || linha.startsWith('<')) continue; // "<Mídia oculta>"
    r.add(MensagemWhatsApp(linha, data, autor, interpretarVoz(linha, insumos: insumos)));
  }
  return r;
}
