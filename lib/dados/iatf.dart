// IATF: ficha da vaca na inseminação, resultado por protocolo, ressincronização,
// taxa de concepção por fator e relatórios do protocolo (WhatsApp e planilha).
import 'db.dart';
import 'financeiro.dart' show csv;
import 'indicadores.dart' show eccEm, faixasEcc, lancarEcc;
import 'manejo.dart' show partosDaVaca;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);

int _dias(String de, String ate) {
  final a = DateTime.parse(_dia(de)), b = DateTime.parse(_dia(ate));
  return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

String _br(Object? iso) {
  final d = _dia(iso);
  return d.length < 10 ? '-' : '${d.substring(8, 10)}/${d.substring(5, 7)}/${d.substring(0, 4)}';
}

String _num(num v, [int casas = 1]) => v.toStringAsFixed(casas).replaceAll('.', ',');

// ---------- Opções da ficha ----------

const categoriasIa = ['Novilha', 'Primípara', 'Multípara'];
const escoresCio = ['1 · Sem manifestação', '2 · Pouca manifestação', '3 · Boa manifestação'];
const statusImplante = ['Retirado normal', 'Perda antecipada', 'Não retirado', 'Desconhecido'];
const opcoesCiclicidade = ['Sim', 'Não', 'Não avaliado'];
const saidasBrete = ['Andando', 'Trotando', 'Correndo'];
const tratamentosIa = ['Suplemento P4', 'Vacina reprodutiva', 'Suplemento vitamínico', 'Suplemento de gordura',
  'Descongelador de sêmen'];

/// Tipo de diagnóstico de gestação e com quantos dias após a IA ele é feito.
const tiposDg = {'Ultrassom': 30, 'Palpação': 50};

/// Dias após a IA para o 2º diagnóstico (confirmação da prenhez).
const diasConfirmacao = 60;

/// Partos da vaca antes de [data].
List<String> _partosAntes(int vacaId, String data) =>
    [for (final p in partosDaVaca(vacaId)) if (p.compareTo(_dia(data)) < 0) p];

/// Novilha (nunca pariu), primípara (1 parto) ou multípara.
String categoriaReprodutiva(int vacaId, String data) {
  final n = _partosAntes(vacaId, data).length;
  return n == 0 ? 'Novilha' : (n == 1 ? 'Primípara' : 'Multípara');
}

/// Dias desde o último parto até [data], ou null se nunca pariu.
int? diasDeParida(int vacaId, String data) {
  final p = _partosAntes(vacaId, data);
  return p.isEmpty ? null : _dias(p.last, data);
}

/// Ordem do serviço desde o último parto: 1 = primeira IA da estação.
int ordemServico(int vacaId, String data) {
  final p = _partosAntes(vacaId, data);
  final desde = p.isEmpty ? '' : p.last;
  return 1 +
      Db.registros('reproducoes').where((r) {
        final d = _dia(r['data']);
        return _int(r['femea_id']) == vacaId && d.compareTo(desde) > 0 && d.compareTo(_dia(data)) < 0;
      }).length;
}

/// Dados que o app preenche sozinho na ficha (categoria, dias de parida, ordem e ECC recente).
Reg fichaAutomatica(int vacaId, String data) => {
      'categoria_ia': categoriaReprodutiva(vacaId, data),
      'dias_parida': diasDeParida(vacaId, data),
      'ordem': ordemServico(vacaId, data),
      'ecc': eccEm(vacaId, data),
    };

/// Registra a inseminação com a ficha da vaca. O ECC informado também vai
/// para o histórico de escores do animal.
Future<int> inseminarComFicha({
  required int femeaId,
  required String data,
  required String tipo,
  int? semenId,
  String? inseminador,
  String? protocolo,
  Reg ficha = const {},
}) async {
  final auto = fichaAutomatica(femeaId, data);
  final f = <String, Object?>{
    ...auto,
    for (final e in ficha.entries)
      if (e.value != null && e.value != '' && !(e.value is List && (e.value as List).isEmpty)) e.key: e.value,
  };
  final id = await Db.registrarInseminacao(
    femeaId: femeaId,
    data: data,
    tipo: tipo,
    semenId: semenId,
    inseminador: inseminador,
    protocolo: protocolo,
    obs: f.remove('obs') as String?,
    ficha: f,
  );
  final ecc = ficha['ecc'];
  if (ecc is num && ecc != auto['ecc']) await lancarEcc(femeaId, data, ecc.toDouble());
  return id;
}

// ---------- Resultado do protocolo ----------

/// Situação da vaca no protocolo.
enum SituacaoIatf { semIa, aguardando, prenhe, vazia, perda, descartada }

const rotuloSituacao = {
  SituacaoIatf.semIa: 'Sem IA',
  SituacaoIatf.aguardando: 'Aguardando DG',
  SituacaoIatf.prenhe: 'P+',
  SituacaoIatf.vazia: 'V−',
  SituacaoIatf.perda: 'Perda',
  SituacaoIatf.descartada: 'Descarte',
};

class VacaIatf {
  VacaIatf(this.animal, this.servico, this.situacao);
  final Reg animal;
  final Reg? servico;
  final SituacaoIatf situacao;
  bool get confirmada => servico?['confirmado'] == true;
}

class ResultadoIatf {
  ResultadoIatf(this.protocolo, this.vacas);
  final Reg protocolo;
  final List<VacaIatf> vacas;

  int _n(SituacaoIatf s) => vacas.where((v) => v.situacao == s).length;
  int get prenhes => _n(SituacaoIatf.prenhe);
  int get vazias => _n(SituacaoIatf.vazia);
  int get perdas => _n(SituacaoIatf.perda);
  int get aguardando => _n(SituacaoIatf.aguardando);
  int get semIa => _n(SituacaoIatf.semIa);
  int get descartadas => _n(SituacaoIatf.descartada);
  int get inseminadas => prenhes + vazias + perdas + aguardando;
  int get diagnosticadas => prenhes + vazias + perdas;

  /// Prenhes ÷ diagnosticadas (perda conta como vazia), ou null sem diagnóstico.
  double? get taxaPrenhez => diagnosticadas == 0 ? null : prenhes / diagnosticadas;

  /// Perdas ÷ prenhes no 1º diagnóstico.
  double? get taxaPerda => prenhes + perdas == 0 ? null : perdas / (prenhes + perdas);

  /// Data (ISO) da IA: a última etapa do protocolo.
  String? get dataIa => dataIaProtocolo(protocolo);
  int get dgDias => _int(protocolo['dg_dias']) ?? 30;
  String? get dgPrevisto => dataIa == null ? null : Db.dataEtapa(dataIa, dgDias);
  String? get confirmacaoPrevista => dataIa == null ? null : Db.dataEtapa(dataIa, diasConfirmacao);
  String? get partoPrevisto => dataIa == null ? null : Db.partoPrevisto(dataIa);
}

List<Map<String, Object?>> etapasDe(Reg p) =>
    [for (final e in (p['etapas'] as List?) ?? const []) Map<String, Object?>.from(e as Map)];

String? dataIaProtocolo(Reg p) {
  final e = etapasDe(p);
  if (e.isEmpty || p['inicio'] == null) return null;
  return Db.dataEtapa(p['inicio'], e.last['dia']);
}

/// Serviço da vaca neste protocolo: o ligado a ele ou, nos antigos, a IA até 5 dias da data prevista.
Reg? servicoNoProtocolo(Reg p, int femeaId) {
  final ia = dataIaProtocolo(p);
  Reg? achado;
  for (final r in Db.registros('reproducoes')) {
    if (_int(r['femea_id']) != femeaId || r['tipo'] == 'Monta natural') continue;
    final ligado = _int(r['protocolo_id']);
    if (ligado == _int(p['id']) ||
        (ligado == null && ia != null && _t(r['data']).isNotEmpty && _dias(ia, _t(r['data'])).abs() <= 5)) {
      if (achado == null || _dia(r['data']).compareTo(_dia(achado['data'])) > 0) achado = r;
    }
  }
  return achado;
}

SituacaoIatf situacaoServico(Reg? r) {
  if (r == null) return SituacaoIatf.semIa;
  if (r['perda'] == true) return SituacaoIatf.perda;
  if (r['parto_data'] != null || r['diagnostico'] == 'Prenhe') return SituacaoIatf.prenhe;
  if (r['diagnostico'] == 'Vazia') return SituacaoIatf.vazia;
  return SituacaoIatf.aguardando;
}

ResultadoIatf resultadoProtocolo(Reg p) {
  final descartes = {for (final d in (p['descartes'] as List?) ?? const []) _int(d)};
  final vacas = <VacaIatf>[];
  for (final f in (p['femeas'] as List?) ?? const []) {
    final a = Db.registro('animais', f);
    if (a == null) continue;
    final s = servicoNoProtocolo(p, _int(f)!);
    final sit = situacaoServico(s);
    vacas.add(VacaIatf(a, s,
        sit == SituacaoIatf.semIa && descartes.contains(_int(f)) ? SituacaoIatf.descartada : sit));
  }
  vacas.sort((a, b) => _t(a.animal['brinco']).compareTo(_t(b.animal['brinco'])));
  return ResultadoIatf(p, vacas);
}

/// Tira a vaca do protocolo para descarte (refugo) e marca o animal.
Future<void> descartarDoProtocolo(int protocoloId, int vacaId, {String? motivo}) async {
  final p = Db.registro('protocolos', protocoloId);
  if (p == null) return;
  final descartes = {for (final d in (p['descartes'] as List?) ?? const []) _int(d)}..add(vacaId);
  await Db.atualizar('protocolos', protocoloId, {'descartes': descartes.toList()});
  await Db.atualizar('animais', vacaId, {'descarte': true, if (motivo != null) 'descarte_motivo': motivo});
}

/// Vacas vazias ou com perda do protocolo, ainda ativas e não descartadas.
List<int> vaziasParaRessinc(Reg p) => [
      for (final v in resultadoProtocolo(p).vacas)
        if ((v.situacao == SituacaoIatf.vazia || v.situacao == SituacaoIatf.perda) &&
            v.animal['status'] == 'Ativo' &&
            v.animal['descarte'] != true)
          _int(v.animal['id'])!,
    ];

/// Novo protocolo com as vazias, com as mesmas etapas, começando em [inicio].
Future<int?> ressincronizar(Reg p, String inicio) async {
  final vazias = vaziasParaRessinc(p);
  if (vazias.isEmpty) return null;
  final rodada = (_int(p['rodada']) ?? 1) + 1;
  final base = _t(p['nome']).replaceAll(RegExp(r' · ressinc\. \d+$'), '');
  return Db.salvarProtocolo(
    nome: '$base · ressinc. $rodada',
    inicio: inicio,
    etapas: etapasDe(p),
    femeas: vazias,
    extras: {
      'origem_id': p['id'],
      'rodada': rodada,
      'dg_dias': p['dg_dias'],
      'veterinario': p['veterinario'],
    },
  );
}

// ---------- Concepção por fator ----------

class LinhaConcepcao {
  LinhaConcepcao(this.valor);
  final String valor;
  int prenhes = 0, total = 0;
  double get taxa => total == 0 ? 0 : prenhes / total;
}

String _faixaEcc(Object? ecc) {
  if (ecc is! num) return 'Sem ECC';
  return ecc <= 2.5 ? faixasEcc[0] : (ecc < 3.5 ? faixasEcc[1] : faixasEcc[2]);
}

String _ordem(Object? o) {
  final n = _int(o);
  if (n == null) return 'Não informado';
  return n >= 3 ? '3º serviço ou mais' : '$nº serviço';
}

String _simNao(Object? v) => v == true ? 'Sim' : (v == false ? 'Não' : 'Não informado');

/// Fatores para comparar a concepção. Cada um tira o valor do serviço (com a vaca).
final fatoresConcepcao = <String, String Function(Reg servico, Reg? vaca)>{
  'Inseminador': (r, _) => _t(r['inseminador']),
  'Touro': (r, _) => _t(r['touro']),
  'Touro e partida': (r, _) => [_t(r['touro']), if (_t(r['partida']).isNotEmpty) 'partida ${r['partida']}'].join(' · '),
  'Raça da vaca': (_, a) => _t(a?['raca']),
  'Categoria': (r, _) => _t(r['categoria_ia']),
  'ECC': (r, a) => _faixaEcc(r['ecc'] ?? (a == null ? null : eccEm(_int(a['id'])!, _dia(r['data'])))),
  'Ordem do serviço': (r, _) => _ordem(r['ordem']),
  'Bezerro ao pé': (r, _) => _simNao(r['bezerro']),
  'Implante': (r, _) => _t(r['implante']),
  'Escore de cio': (r, _) => _t(r['escore_cio']),
  'Ciclicidade': (r, _) => _t(r['ciclicidade']),
  'Técnico': (r, _) => _t(r['tecnico']),
  'Protocolo': (r, _) => _t(r['protocolo']),
  'Tipo de serviço': (r, _) => _t(r['tipo']),
};

/// Taxa de concepção (prenhes ÷ diagnosticadas) pelo [fator], nos serviços
/// desta propriedade com diagnóstico. [protocoloId] limita a um lote; [ano] a um ano.
List<LinhaConcepcao> concepcaoPorFator(String fator, {int? protocoloId, int? ano}) {
  final valor = fatoresConcepcao[fator]!;
  final linhas = <String, LinhaConcepcao>{};
  final p = protocoloId == null ? null : Db.registro('protocolos', protocoloId);
  final servicos = p != null
      ? [for (final v in resultadoProtocolo(p).vacas) if (v.servico != null) v.servico!]
      : Db.registros('reproducoes');
  for (final r in servicos) {
    if (r['tipo'] == 'Monta natural') continue;
    final a = Db.registro('animais', r['femea_id']);
    if (a == null || _int(a['propriedade_id']) != Db.pid) continue;
    if (ano != null && !_t(r['data']).startsWith('$ano')) continue;
    final sit = situacaoServico(r);
    if (sit == SituacaoIatf.aguardando) continue;
    var v = valor(r, a).trim();
    if (v.isEmpty) v = 'Não informado';
    final l = linhas.putIfAbsent(v, () => LinhaConcepcao(v));
    l.total++;
    if (sit == SituacaoIatf.prenhe) l.prenhes++;
  }
  return linhas.values.toList()
    ..sort((a, b) {
      final c = b.total.compareTo(a.total);
      return c != 0 ? c : a.valor.compareTo(b.valor);
    });
}

// ---------- Relatórios do protocolo ----------

String _pct(double? v) => v == null ? '-' : '${_num(v * 100, 0)}%';

String _linhaFicha(Reg? s) {
  if (s == null) return '';
  return [
    if (_t(s['categoria_ia']).isNotEmpty) _t(s['categoria_ia']),
    if (s['dias_parida'] != null) '${s['dias_parida']} d parida',
    if (s['ecc'] is num) 'ECC ${_num(s['ecc'] as num)}',
    if (_t(s['escore_cio']).isNotEmpty) 'cio ${_t(s['escore_cio']).split(' ').first}',
    if (_t(s['implante']).isNotEmpty && s['implante'] != 'Retirado normal') 'implante: ${s['implante']}',
    if (s['bezerro'] == true) 'bezerro ao pé',
    if (_t(s['ciclicidade']).isNotEmpty) 'cíclica: ${s['ciclicidade']}',
    if (_t(s['inseminador']).isNotEmpty) 'insem. ${s['inseminador']}',
  ].join(' · ');
}

/// Texto do resultado do protocolo para o WhatsApp. [completo]: versão do
/// veterinário (ficha de cada vaca e concepção por touro e inseminador).
String relatorioProtocolo(Reg p, {bool completo = false}) {
  final r = resultadoProtocolo(p);
  final prop = Db.registro('propriedades', Db.pid);
  final b = StringBuffer()
    ..writeln('*Resultado da IATF · ${p['nome']}*')
    ..writeln('Fazenda: ${_t(prop?['nome'])}${completo && _t(prop?['uf']).isNotEmpty ? ' (${prop!['uf']})' : ''}');
  if (completo && _t(p['veterinario']).isNotEmpty) b.writeln('Veterinário: ${p['veterinario']}');
  b.writeln('D0: ${_br(p['inicio'])} · IA: ${_br(r.dataIa)}');
  if (completo) {
    for (final e in etapasDe(p)) {
      b.writeln('  D${e['dia']} ${_br(Db.dataEtapa(p['inicio'], e['dia']))}${_t(e['hora']).isEmpty ? '' : ' ${e['hora']}'}: ${e['nome']}');
    }
    b.writeln('DG (${tiposDg.entries.firstWhere((e) => e.value == r.dgDias, orElse: () => MapEntry('${r.dgDias} dias', 0)).key}): '
        '${_br(r.dgPrevisto)} · confirmação: ${_br(r.confirmacaoPrevista)}');
  }
  b
    ..writeln()
    ..writeln('${r.inseminadas} inseminadas · ${r.prenhes} prenhes · ${r.vazias} vazias'
        '${r.perdas > 0 ? ' · ${r.perdas} perdas' : ''}${r.aguardando > 0 ? ' · ${r.aguardando} aguardando DG' : ''}')
    ..writeln('*Taxa de prenhez: ${_pct(r.taxaPrenhez)}*');
  if (r.perdas > 0) b.writeln('Perda embrionária: ${_pct(r.taxaPerda)}');
  if (r.prenhes > 0) b.writeln('Partos previstos a partir de ${_br(r.partoPrevisto)}');
  b
    ..writeln()
    ..writeln('Brinco · Touro · Resultado');
  for (final v in r.vacas) {
    final s = v.servico;
    b.writeln([
      _t(v.animal['brinco']),
      if (_t(s?['touro']).isNotEmpty) _t(s!['touro']),
      rotuloSituacao[v.situacao]! + (v.confirmada ? ' (confirmada)' : ''),
      if (completo && _linhaFicha(s).isNotEmpty) _linhaFicha(s),
      if (_t(s?['obs']).isNotEmpty) 'obs: ${s!['obs']}',
    ].join(' · '));
  }
  if (completo && r.diagnosticadas > 0) {
    for (final f in ['Touro', 'Inseminador']) {
      final linhas = concepcaoPorFator(f, protocoloId: _int(p['id']));
      if (linhas.length < 2) continue;
      b
        ..writeln()
        ..writeln('Concepção por ${f.toLowerCase()}:');
      for (final l in linhas) {
        b.writeln('  ${l.valor}: ${l.prenhes}/${l.total} (${_pct(l.taxa)})');
      }
    }
  }
  return b.toString().trimRight();
}

/// Ficha do lote em CSV (abre no Excel), uma linha por vaca.
String planilhaProtocolo(Reg p) {
  final r = resultadoProtocolo(p);
  String n(Object? v) => v is num ? _num(v, v is int ? 0 : 1) : _t(v);
  return csv([
    'Brinco', 'Nome', 'Raça', 'Categoria', 'Dias de parida', 'ECC', 'Ordem', 'Touro', 'Partida', 'Inseminador',
    'Técnico', 'Data IA', 'Hora', 'Escore de cio', 'Implante', 'Bezerro ao pé', 'Ciclicidade', 'Saída do brete',
    'Tratamentos', 'Peso (kg)', 'Temperatura', 'Folículo D (mm)', 'Folículo E (mm)', 'Resultado', 'Data DG',
    'Confirmação', 'Parto previsto', 'Observação',
  ], [
    for (final v in r.vacas)
      [
        v.animal['brinco'], v.animal['nome'], v.animal['raca'],
        v.servico?['categoria_ia'], n(v.servico?['dias_parida']), n(v.servico?['ecc']), n(v.servico?['ordem']),
        v.servico?['touro'], v.servico?['partida'], v.servico?['inseminador'], v.servico?['tecnico'],
        v.servico == null ? '' : _br(v.servico!['data']), v.servico?['hora'], v.servico?['escore_cio'],
        v.servico?['implante'], v.servico?['bezerro'] == null ? '' : _simNao(v.servico!['bezerro']),
        v.servico?['ciclicidade'], v.servico?['saida_brete'],
        ((v.servico?['tratamentos'] as List?) ?? const []).join(', '),
        n(v.servico?['peso']), n(v.servico?['temperatura']), n(v.servico?['foliculo_d']), n(v.servico?['foliculo_e']),
        rotuloSituacao[v.situacao], v.servico?['data_diagnostico'] == null ? '' : _br(v.servico!['data_diagnostico']),
        v.servico?['data_confirmacao'] == null ? '' : '${_br(v.servico!['data_confirmacao'])} ${v.confirmada ? 'P+' : 'V−'}',
        v.servico?['parto_previsto'] == null ? '' : _br(v.servico!['parto_previsto']),
        v.servico?['obs'],
      ],
  ]);
}
