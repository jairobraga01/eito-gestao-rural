// Importação de animais por planilha (CSV), com conferência linha a linha
// antes de gravar. Aceita o arquivo salvo pelo Excel (separado por ; ) ou
// por vírgula, com ou sem acentos no cabeçalho.
import '../util/formato.dart';
import 'db.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

/// Colunas reconhecidas e os nomes aceitos no cabeçalho.
const colunasImportacao = <String, List<String>>{
  'brinco': ['brinco', 'numero', 'número', 'n', 'nº', 'identificacao', 'identificação', 'animal'],
  'nome': ['nome', 'apelido'],
  'sexo': ['sexo'],
  'raca': ['raca', 'raça'],
  'categoria': ['categoria'],
  'nascimento': ['nascimento', 'data de nascimento', 'data nascimento', 'nasc'],
  'peso': ['peso', 'peso (kg)', 'peso kg', 'ultimo peso', 'último peso'],
  'data_peso': ['data do peso', 'data da pesagem', 'data pesagem'],
  'lote': ['lote'],
  'rfid': ['rfid', 'brinco eletronico', 'brinco eletrônico', 'eletronico', 'eletrônico', 'chip'],
  'sisbov': ['sisbov'],
  'mae': ['mae', 'mãe', 'brinco da mae', 'brinco da mãe'],
  'pai': ['pai', 'touro', 'semen', 'sêmen'],
  'origem': ['origem'],
  'obs': ['obs', 'observacao', 'observação', 'observacoes', 'observações'],
};

/// Modelo para o produtor baixar e preencher.
const modeloCsv = 'brinco;nome;sexo;raca;categoria;nascimento;peso;lote;rfid;sisbov;mae;pai;obs\n'
    '101;Mimosa;F;Nelore;Vaca;15/03/2021;420;Matrizes;;;;;\n'
    '102;;M;Nelore;Bezerro;10/08/2025;180;Desmama;982000123456789;;101;;\n';

String _semAcento(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const para = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b.toString();
}

String _chave(String s) => _semAcento(s.trim().toLowerCase()).replaceAll(RegExp(r'\s+'), ' ');

/// Divide o texto em linhas e colunas, respeitando aspas.
List<List<String>> lerCsv(String texto) {
  var t = texto.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (t.startsWith('﻿')) t = t.substring(1);
  final primeira = t.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final sep = ';'.allMatches(primeira).length >= ','.allMatches(primeira).length ? ';' : ',';
  final linhas = <List<String>>[];
  var campo = StringBuffer();
  var linha = <String>[];
  var aspas = false;
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (aspas) {
      if (c == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          campo.write('"');
          i++;
        } else {
          aspas = false;
        }
      } else {
        campo.write(c);
      }
    } else if (c == '"') {
      aspas = true;
    } else if (c == sep) {
      linha.add(campo.toString().trim());
      campo = StringBuffer();
    } else if (c == '\n') {
      linha.add(campo.toString().trim());
      campo = StringBuffer();
      if (linha.any((x) => x.isNotEmpty)) linhas.add(linha);
      linha = <String>[];
    } else {
      campo.write(c);
    }
  }
  linha.add(campo.toString().trim());
  if (linha.any((x) => x.isNotEmpty)) linhas.add(linha);
  return linhas;
}

/// Data em dd/mm/aaaa, dd/mm/aa ou aaaa-mm-dd → aaaa-mm-dd (null se inválida).
String? dataImportada(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
  int? a, me, d;
  if (m != null) {
    a = int.parse(m.group(1)!);
    me = int.parse(m.group(2)!);
    d = int.parse(m.group(3)!);
  } else {
    m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$').firstMatch(t);
    if (m == null) return null;
    d = int.parse(m.group(1)!);
    me = int.parse(m.group(2)!);
    a = int.parse(m.group(3)!);
    if (a < 100) a += a > 50 ? 1900 : 2000;
  }
  if (me < 1 || me > 12 || d < 1 || d > 31 || a < 1950 || a > 2100) return null;
  final dt = DateTime.utc(a, me, d);
  if (dt.month != me) return null;
  return '${a.toString().padLeft(4, '0')}-${me.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

double? _numero(String s) => lerNumero(s.toLowerCase().replaceAll('kg', ''));

String? _sexo(String s) {
  final t = _chave(s);
  if (t.isEmpty) return null;
  if (['f', 'femea', 'fem', 'vaca', 'novilha', 'bezerra'].contains(t)) return 'F';
  if (['m', 'macho', 'mac', 'boi', 'touro', 'garrote', 'bezerro'].contains(t)) return 'M';
  return null;
}

/// Uma linha da planilha já conferida.
class LinhaImportacao {
  LinhaImportacao(this.numero, this.dados);
  final int numero;
  final Map<String, String> dados;
  final erros = <String>[];
  final avisos = <String>[];
  Reg animal = {};
  double? peso;
  String? dataPeso;
  String? maeBrinco;
  bool get ok => erros.isEmpty;
  String get brinco => dados['brinco'] ?? '';
}

class ConferenciaImportacao {
  ConferenciaImportacao(this.linhas, this.colunasIgnoradas, this.erroGeral);
  final List<LinhaImportacao> linhas;
  final List<String> colunasIgnoradas;
  final String? erroGeral;
  Iterable<LinhaImportacao> get boas => linhas.where((l) => l.ok);
  Iterable<LinhaImportacao> get ruins => linhas.where((l) => !l.ok);
}

/// Confere a planilha contra o rebanho da propriedade [propriedadeId].
ConferenciaImportacao conferirImportacao(String texto, {required int propriedadeId, String? hoje}) {
  final tab = lerCsv(texto);
  if (tab.isEmpty) return ConferenciaImportacao([], [], 'A planilha está vazia.');
  final cab = tab.first;
  final mapa = <int, String>{};
  final ignoradas = <String>[];
  for (var i = 0; i < cab.length; i++) {
    final k = _chave(cab[i]);
    String? achou;
    for (final e in colunasImportacao.entries) {
      if (e.value.map(_chave).contains(k)) {
        achou = e.key;
        break;
      }
    }
    if (achou != null && !mapa.containsValue(achou)) {
      mapa[i] = achou;
    } else if (cab[i].trim().isNotEmpty) {
      ignoradas.add(cab[i].trim());
    }
  }
  if (!mapa.containsValue('brinco')) {
    return ConferenciaImportacao([], ignoradas,
        'Não achei a coluna "brinco" no cabeçalho. A primeira linha precisa ter os nomes das colunas.');
  }
  if (!mapa.containsValue('sexo')) {
    return ConferenciaImportacao([], ignoradas, 'Não achei a coluna "sexo" (F ou M) no cabeçalho.');
  }

  final ativos = [
    for (final a in Db.registros('animais'))
      if ((a['status'] ?? 'Ativo') == 'Ativo') a,
  ];
  final brincosProp = {
    for (final a in ativos)
      if (_int(a['propriedade_id']) == propriedadeId) '${a['brinco'] ?? ''}'.trim().toLowerCase(): a,
  };
  final rfids = {for (final a in ativos) if ('${a['rfid'] ?? ''}'.trim().isNotEmpty) '${a['rfid']}'.trim()};
  final sisbovs = {for (final a in ativos) if ('${a['sisbov'] ?? ''}'.trim().isNotEmpty) '${a['sisbov']}'.trim()};
  final lotes = {
    for (final l in Db.registros('lotes'))
      if (_int(l['propriedade_id']) == propriedadeId || l['propriedade_id'] == null)
        _chave('${l['nome'] ?? ''}'): _int(l['id']),
  };

  final vistosBrinco = <String>{}, vistosRfid = <String>{}, vistosSisbov = <String>{};
  final linhas = <LinhaImportacao>[];
  final dia = hoje ?? DateTime.now().toIso8601String().substring(0, 10);
  for (var r = 1; r < tab.length; r++) {
    final cel = tab[r];
    final d = <String, String>{
      for (final e in mapa.entries) e.value: e.key < cel.length ? cel[e.key].trim() : '',
    };
    final l = LinhaImportacao(r + 1, d);
    final brinco = l.brinco;
    final bk = brinco.toLowerCase();
    if (brinco.isEmpty) {
      l.erros.add('Sem brinco.');
    } else if (!vistosBrinco.add(bk)) {
      l.erros.add('Brinco $brinco repetido na planilha.');
    } else if (brincosProp.containsKey(bk)) {
      l.erros.add('Já existe um animal ativo com o brinco $brinco nesta propriedade.');
    }
    final sexo = _sexo(d['sexo'] ?? '');
    if (sexo == null) l.erros.add('Sexo "${d['sexo'] ?? ''}" não reconhecido (use F ou M).');

    String? nasc;
    if ((d['nascimento'] ?? '').isNotEmpty) {
      nasc = dataImportada(d['nascimento']!);
      if (nasc == null) {
        l.erros.add('Data de nascimento "${d['nascimento']}" inválida (use dd/mm/aaaa).');
      } else if (nasc.compareTo(dia) > 0) {
        l.erros.add('Nascimento no futuro.');
      }
    }

    final rfid = d['rfid'] ?? '';
    if (rfid.isNotEmpty && (rfids.contains(rfid) || !vistosRfid.add(rfid))) {
      l.erros.add('Brinco eletrônico $rfid já está em uso.');
    }
    final sisbov = d['sisbov'] ?? '';
    if (sisbov.isNotEmpty && (sisbovs.contains(sisbov) || !vistosSisbov.add(sisbov))) {
      l.erros.add('SISBOV $sisbov já está em uso.');
    }

    if ((d['peso'] ?? '').isNotEmpty) {
      final p = _numero(d['peso']!);
      if (p == null || p <= 0 || p > 2000) {
        l.erros.add('Peso "${d['peso']}" inválido.');
      } else {
        l.peso = p;
        final dp = (d['data_peso'] ?? '').isEmpty ? dia : dataImportada(d['data_peso']!);
        if (dp == null) {
          l.erros.add('Data do peso "${d['data_peso']}" inválida.');
        } else {
          l.dataPeso = dp;
        }
      }
    }

    int? loteId;
    final nomeLote = d['lote'] ?? '';
    if (nomeLote.isNotEmpty) {
      loteId = lotes[_chave(nomeLote)];
      if (loteId == null) l.avisos.add('Lote "$nomeLote" não existe: o animal entra sem lote.');
    }
    final mae = d['mae'] ?? '';
    if (mae.isNotEmpty) l.maeBrinco = mae;

    l.animal = {
      'brinco': brinco,
      'nome': (d['nome'] ?? '').isEmpty ? null : d['nome'],
      'sexo': sexo,
      'raca': (d['raca'] ?? '').isEmpty ? null : d['raca'],
      'categoria': (d['categoria'] ?? '').isEmpty ? null : d['categoria'],
      'nascimento': nasc,
      'lote_id': loteId,
      'rfid': rfid.isEmpty ? null : rfid,
      'sisbov': sisbov.isEmpty ? null : sisbov,
      'pai': (d['pai'] ?? '').isEmpty ? null : d['pai'],
      'origem': (d['origem'] ?? '').isEmpty ? 'Compra' : d['origem'],
      'obs': (d['obs'] ?? '').isEmpty ? null : d['obs'],
    };
    linhas.add(l);
  }

  // Mãe: precisa ser fêmea do rebanho ou da própria planilha.
  final femeasPlanilha = {for (final l in linhas) if (l.ok && l.animal['sexo'] == 'F') l.brinco.toLowerCase()};
  for (final l in linhas) {
    final m = l.maeBrinco?.toLowerCase();
    if (m == null) continue;
    final noRebanho = brincosProp[m];
    if (m == l.brinco.toLowerCase()) {
      l.erros.add('O animal não pode ser mãe dele mesmo.');
    } else if (noRebanho == null && !femeasPlanilha.contains(m)) {
      l.avisos.add('Mãe ${l.maeBrinco} não encontrada: fica só anotada.');
    } else if (noRebanho != null && noRebanho['sexo'] != 'F') {
      l.avisos.add('O animal ${l.maeBrinco} não é fêmea: a mãe fica só anotada.');
    }
  }
  return ConferenciaImportacao(linhas, ignoradas, linhas.isEmpty ? 'A planilha só tem o cabeçalho.' : null);
}

/// Grava as linhas boas. Devolve quantos animais entraram.
Future<int> gravarImportacao(ConferenciaImportacao c, {required int propriedadeId}) async {
  final boas = c.boas.toList();
  final agora = DateTime.now().toIso8601String();
  final ids = <String, int>{};
  final maes = <String, int>{
    for (final a in Db.registros('animais'))
      if ((a['status'] ?? 'Ativo') == 'Ativo' && _int(a['propriedade_id']) == propriedadeId && a['sexo'] == 'F')
        '${a['brinco'] ?? ''}'.trim().toLowerCase(): _int(a['id'])!,
  };
  // Primeiro as fêmeas, para que as crias achem a mãe.
  boas.sort((a, b) => (a.animal['sexo'] == 'F' ? 0 : 1).compareTo(b.animal['sexo'] == 'F' ? 0 : 1));
  var n = 0;
  for (final l in boas) {
    final v = <String, Object?>{
      ...l.animal,
      'status': 'Ativo',
      'propriedade_id': propriedadeId,
      'criado_em': agora,
    };
    final mae = l.maeBrinco?.toLowerCase();
    if (mae != null) {
      final id = maes[mae] ?? ids[mae];
      if (id != null) {
        v['mae_id'] = id;
      } else {
        v['mae_brinco'] = l.maeBrinco;
      }
    }
    try {
      final id = await Db.inserir('animais', v);
      ids[l.brinco.toLowerCase()] = id;
      if (v['sexo'] == 'F') maes[l.brinco.toLowerCase()] = id;
      if (l.peso != null) {
        await Db.inserir('pesagens', {
          'animal_id': id,
          'data': l.dataPeso,
          'peso': l.peso,
          'evento': v['origem'] == 'Compra' ? 'Entrada' : 'Rotina',
        });
      }
      n++;
    } on RegistroDuplicado catch (e) {
      l.erros.add(e.toString());
    }
  }
  // Segunda passada: a cria que veio antes da mãe na planilha liga agora.
  for (final l in boas) {
    final mae = l.maeBrinco?.toLowerCase();
    final cria = ids[l.brinco.toLowerCase()];
    if (mae == null || cria == null || Db.registro('animais', cria)?['mae_id'] != null) continue;
    final id = maes[mae];
    if (id != null) await Db.atualizar('animais', cria, {'mae_id': id, 'mae_brinco': null});
  }
  return n;
}
