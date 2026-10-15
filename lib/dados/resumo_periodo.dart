// Números de um período (mês ou ano) da propriedade aberta, para os relatórios.
import 'db.dart';

const nomesMeses = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String _t(Object? v) => v == null ? '' : '$v';
String _dois(int n) => n.toString().padLeft(2, '0');

class ResumoPeriodo {
  ResumoPeriodo._(this.de, this.ate);

  /// Datas ISO (yyyy-mm-dd), incluídas.
  final String de, ate;

  int nascimentos = 0, nascMachos = 0, nascFemeas = 0;

  /// Serviços (IA, IATF, TE e monta) feitos no período e o diagnóstico de cada um.
  int servicos = 0, prenhes = 0, vazias = 0, pendentes = 0;

  /// Fêmeas diferentes que receberam IA, IATF ou TE no período.
  int inseminadas = 0;

  /// Prenhes ainda sem parto com parto previsto dentro do período.
  int partosPrevistos = 0;

  /// Soma do preço das doses usadas no período e prenhes vindas dessas doses.
  double custoSemen = 0;
  int prenhesComCusto = 0;

  int vacinacoes = 0, manejosSanitarios = 0;
  final vacinasPorProduto = <String, int>{};

  int pesagens = 0;

  /// GMD de cada animal com duas ou mais pesagens no período.
  final gmds = <double>[];

  int saidas = 0;
  final saidasPorTipo = <String, int>{};
  double valorVendas = 0;
  int cabecasVendidas = 0;

  double? get taxaPrenhez => prenhes + vazias == 0 ? null : prenhes / (prenhes + vazias);
  double? get custoPorPrenhez => prenhesComCusto == 0 ? null : custoSemen / prenhesComCusto;
  double? get gmdMedio => gmds.isEmpty ? null : gmds.reduce((a, b) => a + b) / gmds.length;

  bool _dentro(Object? data) {
    final d = _t(data);
    if (d.length < 10) return false;
    final dia = d.substring(0, 10);
    return dia.compareTo(de) >= 0 && dia.compareTo(ate) <= 0;
  }

  static ResumoPeriodo mes(int ano, int mes) {
    final ultimo = DateTime(ano, mes + 1, 0).day;
    return calcular('$ano-${_dois(mes)}-01', '$ano-${_dois(mes)}-${_dois(ultimo)}');
  }

  static ResumoPeriodo ano(int ano) => calcular('$ano-01-01', '$ano-12-31');

  static List<ResumoPeriodo> mesesDoAno(int ano) => [for (var m = 1; m <= 12; m++) mes(ano, m)];

  static ResumoPeriodo calcular(String de, String ate) {
    final r = ResumoPeriodo._(de, ate);
    final pid = Db.pid;
    final animais = {
      for (final a in Db.registros('animais'))
        if (_int(a['propriedade_id']) == pid) _int(a['id']): a,
    };

    for (final a in animais.values) {
      if (a['origem'] != 'Nascimento' || !r._dentro(a['nascimento'])) continue;
      r.nascimentos++;
      a['sexo'] == 'F' ? r.nascFemeas++ : r.nascMachos++;
    }

    final femeasIa = <int?>{};
    for (final x in Db.registros('reproducoes')) {
      if (!animais.containsKey(_int(x['femea_id']))) continue;
      if (x['diagnostico'] == 'Prenhe' && x['parto_data'] == null && r._dentro(x['parto_previsto'])) {
        r.partosPrevistos++;
      }
      if (!r._dentro(x['data'])) continue;
      r.servicos++;
      if (x['tipo'] != 'Monta natural') femeasIa.add(_int(x['femea_id']));
      final prenhe = x['diagnostico'] == 'Prenhe';
      switch (x['diagnostico']) {
        case 'Prenhe':
          r.prenhes++;
        case 'Vazia':
          r.vazias++;
        default:
          r.pendentes++;
      }
      final custo = x['custo_dose'];
      if (custo is num) {
        r.custoSemen += custo;
        if (prenhe) r.prenhesComCusto++;
      }
    }
    r.inseminadas = femeasIa.length;

    for (final s in Db.registros('sanidade')) {
      if (!animais.containsKey(_int(s['animal_id'])) || !r._dentro(s['data'])) continue;
      r.manejosSanitarios++;
      if (s['tipo'] == 'Vacinação') {
        r.vacinacoes++;
        final p = _t(s['produto']).isEmpty ? 'Sem nome' : _t(s['produto']);
        r.vacinasPorProduto[p] = (r.vacinasPorProduto[p] ?? 0) + 1;
      }
    }

    final porAnimal = <int?, List<Reg>>{};
    for (final p in Db.registros('pesagens')) {
      final a = _int(p['animal_id']);
      if (!animais.containsKey(a) || !r._dentro(p['data']) || p['peso'] is! num) continue;
      r.pesagens++;
      porAnimal.putIfAbsent(a, () => []).add(p);
    }
    for (final l in porAnimal.values) {
      if (l.length < 2) continue;
      l.sort((a, b) {
        final c = _t(a['data']).compareTo(_t(b['data']));
        return c != 0 ? c : (_int(a['id']) ?? 0).compareTo(_int(b['id']) ?? 0);
      });
      final d0 = DateTime.parse(_t(l.first['data']).substring(0, 10));
      final d1 = DateTime.parse(_t(l.last['data']).substring(0, 10));
      final dias = DateTime.utc(d1.year, d1.month, d1.day).difference(DateTime.utc(d0.year, d0.month, d0.day)).inDays;
      if (dias <= 0) continue;
      r.gmds.add(((l.last['peso'] as num) - (l.first['peso'] as num)) / dias);
    }

    for (final s in Db.registros('saidas')) {
      if (_int(s['propriedade_id']) != pid || !r._dentro(s['data'])) continue;
      final qtd = _int(s['quantidade']) ?? 0;
      final tipo = _t(s['tipo']).isEmpty ? 'Outra' : _t(s['tipo']);
      r.saidas += qtd;
      r.saidasPorTipo[tipo] = (r.saidasPorTipo[tipo] ?? 0) + qtd;
      if (tipo == 'Venda') {
        r.cabecasVendidas += qtd;
        if (s['valor_total'] is num) r.valorVendas += s['valor_total'] as num;
      }
    }
    return r;
  }
}
