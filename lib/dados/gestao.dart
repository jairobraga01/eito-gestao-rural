// Custos e margem, calendário sanitário, ranking de matrizes, genealogia,
// chuva e resumo semanal da propriedade aberta.
import 'db.dart';
import 'manejo.dart';
import 'resumo_periodo.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _num(Object? v) => v is num ? v.toDouble() : null;
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);
String _br(String iso) => iso.length < 10 ? '-' : '${iso.substring(8, 10)}/${iso.substring(5, 7)}';

int _dias(String de, String ate) {
  final a = DateTime.parse(de.substring(0, 10)), b = DateTime.parse(ate.substring(0, 10));
  return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

/// Idade em meses na data [hoje], ou null sem nascimento.
int? _meses(Reg a, String hoje) {
  final n = DateTime.tryParse(_dia(a['nascimento']));
  if (n == null) return null;
  final h = DateTime.parse(hoje);
  var m = (h.year - n.year) * 12 + h.month - n.month;
  if (h.day < n.day) m--;
  return m < 0 ? 0 : m;
}

Map<int?, Reg> _animaisDaProp({bool soAtivos = false}) => {
      for (final a in Db.registros('animais'))
        if (_int(a['propriedade_id']) == Db.pid && (!soAtivos || a['status'] == 'Ativo')) _int(a['id']): a,
    };

/// Peso de venda, rendimento e arroba salvos na projeção de abate.
(double rendimento, double? arroba) ajustesArroba() {
  final c = Db.registro('config', 'abate') ?? const {};
  return ((_num(c['rendimento']) ?? 52) / 100, _num(c['arroba']));
}

// ---------- Custos e margem por lote ----------

const categoriasCusto = ['Ração e sal', 'Sanidade', 'Mão de obra', 'Pastagem e arrendamento', 'Combustível e máquinas', 'Outros'];

class ContaLote {
  ContaLote(this.loteId, this.nome);
  final int? loteId;
  final String nome;
  int cabecas = 0, ativos = 0, vendidos = 0;
  double aquisicao = 0, custos = 0, semen = 0, vendas = 0, arrobasProduzidas = 0;

  /// Valor dos animais ativos pela arroba informada (null sem arroba).
  double? estoque;

  double get custoTotal => aquisicao + custos + semen;
  double get margem => vendas + (estoque ?? 0) - custoTotal;

  /// Custo de produção (sem a compra dos animais) por arroba ganha.
  double? get custoPorArroba => arrobasProduzidas <= 0 ? null : (custos + semen) / arrobasProduzidas;
}

/// Conta de cada lote: compra dos animais, custos lançados, sêmen, vendas,
/// valor do que ainda está no pasto e custo por arroba produzida.
/// O último item (loteId null) junta os animais sem lote e os custos gerais.
List<ContaLote> contasPorLote() {
  final (rend, arroba) = ajustesArroba();
  final contas = <int?, ContaLote>{
    for (final l in Db.registros('lotes'))
      if (_int(l['propriedade_id']) == Db.pid) _int(l['id']): ContaLote(_int(l['id']), _t(l['nome'])),
  };
  ContaLote conta(Object? lote) =>
      contas[_int(lote)] ?? contas.putIfAbsent(null, () => ContaLote(null, 'Sem lote e custos gerais'));

  final pesagens = <int?, List<Reg>>{};
  for (final p in Db.registros('pesagens')) {
    if (p['peso'] is num) pesagens.putIfAbsent(_int(p['animal_id']), () => []).add(p);
  }
  final animais = _animaisDaProp();
  for (final a in animais.values) {
    final c = conta(a['lote_id']);
    c.cabecas++;
    final e = Db.registro('entradas', a['entrada_id']);
    if (e != null && e['tipo'] == 'Compra' && e['valor_total'] is num && (_int(e['quantidade']) ?? 0) > 0) {
      c.aquisicao += (e['valor_total'] as num) / _int(e['quantidade'])!;
    }
    final s = Db.registro('saidas', a['saida_id']);
    if (s != null && s['tipo'] == 'Venda' && s['valor_total'] is num && (_int(s['quantidade']) ?? 0) > 0) {
      c.vendidos++;
      c.vendas += (s['valor_total'] as num) / _int(s['quantidade'])!;
    }
    final ps = [...?pesagens[_int(a['id'])]]..sort((x, y) => _dia(x['data']).compareTo(_dia(y['data'])));
    if (ps.length >= 2) {
      final ganho = (ps.last['peso'] as num) - (ps.first['peso'] as num);
      if (ganho > 0) c.arrobasProduzidas += ganho * rend / 15;
    }
    if (a['status'] == 'Ativo') {
      c.ativos++;
      if (arroba != null && ps.isNotEmpty) {
        c.estoque = (c.estoque ?? 0) + valorArroba((ps.last['peso'] as num).toDouble(), rend, arroba);
      }
    }
  }
  for (final r in Db.registros('reproducoes')) {
    final f = animais[_int(r['femea_id'])];
    if (f != null && r['custo_dose'] is num) conta(f['lote_id']).semen += r['custo_dose'] as num;
  }
  for (final c in Db.registros('custos')) {
    if (_int(c['propriedade_id']) == Db.pid && c['valor'] is num) conta(c['lote_id']).custos += c['valor'] as num;
  }
  final lista = contas.values.where((c) => c.loteId != null).toList()..sort((a, b) => a.nome.compareTo(b.nome));
  return [...lista, if (contas[null] != null) contas[null]!];
}

// ---------- Calendário sanitário ----------

class ItemCalendario {
  const ItemCalendario(this.id, this.nome, this.tipo, this.descricao, {this.padrao = true});
  final String id, nome, tipo, descricao;
  final bool padrao;
}

const calendarioSanitario = [
  ItemCalendario('brucelose', 'Brucelose', 'Vacinação', 'Fêmeas de 3 a 8 meses, dose única (obrigatória).'),
  ItemCalendario('clostridiose', 'Clostridiose', 'Vacinação',
      'A partir de 4 meses, reforço 30 dias depois e depois uma dose por ano.'),
  ItemCalendario('raiva', 'Raiva', 'Vacinação', 'Uma dose por ano a partir de 3 meses (regiões com morcego).'),
  ItemCalendario('vermifugo', 'Vermífugo estratégico', 'Antiparasitário', 'Todo o rebanho em maio, julho e setembro.'),
  ItemCalendario('aftosa', 'Aftosa', 'Vacinação', 'Maio e novembro. Ligue só se o seu estado ainda vacina.',
      padrao: false),
];

/// Itens do calendário que o produtor deixou ligados.
Set<String> calendarioLigado() {
  final c = Db.registro('config', 'calendario');
  if (c == null) return {for (final i in calendarioSanitario) if (i.padrao) i.id};
  return {for (final x in (c['ligados'] as List?) ?? const []) '$x'};
}

Future<void> ligarCalendario(String id, bool ligado) {
  final s = calendarioLigado();
  ligado ? s.add(id) : s.remove(id);
  return Db.salvarConfig('calendario', {'ligados': s.toList()});
}

/// Animais que o calendário pede hoje, por item ligado: (item, brincos).
List<(ItemCalendario, List<String>)> pendenciasCalendario(String hoje) {
  final ativos = _animaisDaProp(soAtivos: true);
  final doses = <int?, List<Reg>>{};
  for (final s in Db.registros('sanidade')) {
    if (ativos.containsKey(_int(s['animal_id']))) doses.putIfAbsent(_int(s['animal_id']), () => []).add(s);
  }
  final mes = int.parse(hoje.substring(5, 7));
  final esteMes = hoje.substring(0, 7);
  bool produto(Reg s, String chave) => _t(s['produto']).toLowerCase().contains(chave);

  final r = <(ItemCalendario, List<String>)>[];
  for (final item in calendarioSanitario) {
    if (!calendarioLigado().contains(item.id)) continue;
    final brincos = <String>[];
    for (final a in ativos.values) {
      final ds = doses[_int(a['id'])] ?? const <Reg>[];
      final idade = _meses(a, hoje);
      final bool falta;
      switch (item.id) {
        case 'brucelose':
          falta = a['sexo'] == 'F' && idade != null && idade >= 3 && idade <= 8 && !ds.any((s) => produto(s, 'brucel'));
        case 'raiva':
          falta = (idade == null || idade >= 3) &&
              !ds.any((s) => produto(s, 'raiva') && _dias(_dia(s['data']), hoje) < 365);
        case 'clostridiose':
          final cl = [for (final s in ds) if (produto(s, 'clostrid')) _dia(s['data'])]..sort();
          if (idade != null && idade < 4) {
            falta = false;
          } else if (cl.isEmpty || _dias(cl.last, hoje) >= 365) {
            falta = true;
          } else {
            // Só uma dose de jovem: falta o reforço 30 dias depois.
            falta = cl.length == 1 && (idade ?? 99) < 24 && _dias(cl.last, hoje) >= 30;
          }
        case 'vermifugo':
          falta = [5, 7, 9].contains(mes) &&
              !ds.any((s) => s['tipo'] == 'Antiparasitário' && _dia(s['data']).startsWith(esteMes));
        case 'aftosa':
          falta = [5, 11].contains(mes) && !ds.any((s) => produto(s, 'aftosa') && _dia(s['data']).startsWith(esteMes));
        default:
          falta = false;
      }
      if (falta) brincos.add(_t(a['brinco']));
    }
    if (brincos.isNotEmpty) r.add((item, brincos..sort()));
  }
  return r;
}

// ---------- Ranking de matrizes ----------

class NotaMatriz {
  NotaMatriz(this.vaca, this.partos, this.iep, this.taxaPrenhez, this.desmama, this.nota);
  final Reg vaca;
  final int partos;
  final double? iep, taxaPrenhez, desmama;

  /// 0 a 100: prenhez (40), intervalo entre partos (30) e peso das crias na desmama (30).
  final double nota;
}

double _limite(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

List<NotaMatriz> rankingMatrizes() {
  final animais = _animaisDaProp();
  // Peso de desmama de cada cria.
  final desmama = <int?, double>{};
  for (final p in Db.registros('pesagens')) {
    if (p['evento'] == 'Desmama' && p['peso'] is num) desmama[_int(p['animal_id'])] = (p['peso'] as num).toDouble();
  }
  final porMae = <int?, List<double>>{};
  for (final a in animais.values) {
    final d = desmama[_int(a['id'])];
    if (d != null && a['mae_id'] != null) porMae.putIfAbsent(_int(a['mae_id']), () => []).add(d);
  }
  final todas = [for (final l in porMae.values) ...l];
  final mediaRebanho = todas.isEmpty ? null : todas.reduce((a, b) => a + b) / todas.length;

  final diag = <int?, (int, int)>{};
  for (final r in Db.registros('reproducoes')) {
    final f = _int(r['femea_id']);
    final (p, v) = diag[f] ?? (0, 0);
    if (r['diagnostico'] == 'Prenhe') diag[f] = (p + 1, v);
    if (r['diagnostico'] == 'Vazia') diag[f] = (p, v + 1);
  }

  final r = <NotaMatriz>[];
  for (final a in animais.values) {
    if (a['status'] != 'Ativo' || a['sexo'] != 'F') continue;
    final id = _int(a['id'])!;
    final partos = partosDaVaca(id).length;
    final (p, v) = diag[id] ?? (0, 0);
    if (partos == 0 && p + v == 0) continue;
    final taxa = p + v == 0 ? null : p / (p + v);
    final iep = intervaloEntrePartos(id);
    final crias = porMae[id];
    final dm = crias == null ? null : crias.reduce((a, b) => a + b) / crias.length;
    final nota = (taxa == null ? 20 : taxa * 40) +
        (iep == null ? 15 : _limite((545 - iep) / 180) * 30) +
        (dm == null || mediaRebanho == null ? 15 : _limite(0.5 + (dm / mediaRebanho - 1) * 2.5) * 30);
    r.add(NotaMatriz(a, partos, iep, taxa, dm, nota.toDouble()));
  }
  return r..sort((a, b) => b.nota.compareTo(a.nota));
}

// ---------- Genealogia ----------

String _nomeTouro(Object? v) => _t(v).trim().toLowerCase();

/// Mãe, avó e bisavó maternas (registros) e os pais de cada uma (nome do touro).
class Genealogia {
  Genealogia(this.animal);
  final Reg animal;
  Reg? get mae => Db.registro('animais', animal['mae_id']);
  Reg? get avo => mae == null ? null : Db.registro('animais', mae!['mae_id']);
  Reg? get bisavo => avo == null ? null : Db.registro('animais', avo!['mae_id']);

  /// Touros que são pai, avô ou bisavô da fêmea: usar o sêmen deles é consanguinidade.
  Map<String, String> get tourosParentes => {
        if (_t(animal['pai']).trim().isNotEmpty) _t(animal['pai']).trim(): 'pai',
        if (_t(mae?['pai']).trim().isNotEmpty) _t(mae?['pai']).trim(): 'avô materno',
        if (_t(avo?['pai']).trim().isNotEmpty) _t(avo?['pai']).trim(): 'bisavô materno',
      };
}

/// Aviso quando [touro] é parente próximo da fêmea, ou null.
String? alertaConsanguinidade(int femeaId, Object? touro) {
  final f = Db.registro('animais', femeaId);
  final t = _nomeTouro(touro);
  if (f == null || t.isEmpty) return null;
  for (final e in Genealogia(f).tourosParentes.entries) {
    if (_nomeTouro(e.key) == t) return 'O touro ${e.key} é ${e.value} do brinco ${f['brinco']}. Cruzamento consanguíneo.';
  }
  return null;
}

// ---------- Chuva ----------

/// Total de chuva (mm) por mês do ano, de janeiro a dezembro.
List<double> chuvaPorMes(int ano) {
  final r = List<double>.filled(12, 0);
  for (final c in Db.registros('chuvas')) {
    final d = _dia(c['data']);
    if (_int(c['propriedade_id']) != Db.pid || !d.startsWith('$ano-') || c['mm'] is! num) continue;
    r[int.parse(d.substring(5, 7)) - 1] += (c['mm'] as num).toDouble();
  }
  return r;
}

double chuvaEntre(String de, String ate) {
  var t = 0.0;
  for (final c in Db.registros('chuvas')) {
    final d = _dia(c['data']);
    if (_int(c['propriedade_id']) == Db.pid && c['mm'] is num && d.compareTo(de) >= 0 && d.compareTo(ate) <= 0) {
      t += (c['mm'] as num).toDouble();
    }
  }
  return t;
}

// ---------- Resumo semanal ----------

String _n(double v, [int casas = 1]) => v.toStringAsFixed(casas).replaceAll('.', ',');

/// Texto dos últimos 7 dias (até [hoje]) para mandar pelo WhatsApp.
String resumoSemanal(String hoje) {
  final de = Db.dataEtapa(hoje, -6);
  final s = ResumoPeriodo.calcular(de, hoje);
  final ativos = _animaisDaProp(soAtivos: true).length;
  var diagP = 0, diagV = 0;
  for (final r in Db.registros('reproducoes')) {
    final d = _dia(r['data_diagnostico']);
    if (d.isEmpty || d.compareTo(de) < 0 || d.compareTo(hoje) > 0) continue;
    if (Db.registro('animais', r['femea_id'])?['propriedade_id'] != Db.pid) continue;
    if (r['diagnostico'] == 'Prenhe') diagP++;
    // Fechado sozinho pela nova IA (voltou ao cio): não houve exame.
    if (r['diagnostico'] == 'Vazia' && r['vazia_por'] != 'reinseminacao') diagV++;
  }
  final proxima = ResumoPeriodo.calcular(Db.dataEtapa(hoje, 1), Db.dataEtapa(hoje, 7));
  final fila = filaDoDia(hoje).length;
  final chuva = chuvaEntre(de, hoje);
  final g = s.gmdMedio;
  return [
    '*${_t(Db.prop.value?['nome'])}*',
    'Resumo de ${_br(de)} a ${_br(hoje)}',
    '',
    '🐄 Rebanho: $ativos cabeças',
    '🐮 Nascimentos: ${s.nascimentos}',
    '💉 Inseminações: ${s.servicos} (${s.inseminadas} vacas)',
    '🔍 Diagnósticos: $diagP prenhes, $diagV vazias',
    '💊 Vacinas e remédios: ${s.manejosSanitarios} aplicações',
    '⚖️ Pesagens: ${s.pesagens}${g == null ? '' : ' · GMD médio ${_n(g, 3)} kg/dia'}',
    if (s.entradas > 0) '🛒 Entradas: ${s.entradas} cab.${s.valorCompras > 0 ? ' · R\$ ${_n(s.valorCompras, 2)}' : ''}',
    if (s.saidas > 0) '💰 Saídas: ${s.saidas} cab.${s.valorVendas > 0 ? ' · vendas R\$ ${_n(s.valorVendas, 2)}' : ''}',
    '🌧️ Chuva: ${_n(chuva)} mm',
    '',
    '📋 Próximos 7 dias: ${proxima.partosPrevistos} partos previstos · $fila tarefas na fila de hoje',
  ].join('\n');
}
