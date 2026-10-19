// Anexo da Atividade Rural da declaração do Imposto de Renda (IRPF), no
// formato do programa da Receita Federal: imóveis explorados, receitas e
// despesas mês a mês, apuração do resultado (real ou 20% da receita bruta),
// movimentação do rebanho, bens e dívidas vinculadas à atividade rural.
// Junta todas as propriedades da conta, porque a declaração é do produtor.
import 'db.dart';
import 'dividas.dart' show parcelas;
import 'financeiro.dart' show csv, dadosLcdpr, relatorioFinanceiro;
import 'patrimonio.dart' show areaPropriedade, bens;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _n(Object? v) => v is num ? v.toDouble() : 0;
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);

/// Categoria de despesa que a Receita trata como investimento.
const categoriaInvestimento = 'Investimento (máquinas, cercas, benfeitorias)';

/// Condição de exploração do imóvel no programa do IRPF (mesmos códigos do LCDPR).
const condicoesExploracao = {
  1: 'Proprietário',
  2: 'Arrendatário',
  3: 'Parceiro',
  4: 'Comodatário',
  5: 'Ocupante',
  6: 'Condômino',
};

class MesIr {
  MesIr(this.mes, this.receita, this.custeio, this.investimento);
  final int mes;
  final double receita, custeio, investimento;
  double get despesas => custeio + investimento;
}

/// Movimentação do rebanho bovino no ano, em cabeças.
class RebanhoIr {
  int estoqueInicial = 0, aquisicoes = 0, nascimentos = 0, outrasEntradas = 0;
  int vendas = 0, mortes = 0, consumo = 0, outrasSaidas = 0;

  /// Consumo e perdas, como o programa da Receita pede (mortes, consumo e outras baixas).
  int get consumoPerdas => mortes + consumo + outrasSaidas;
  int get estoqueFinal => estoqueInicial + aquisicoes + nascimentos + outrasEntradas - vendas - consumoPerdas;
}

class DividaIr {
  DividaIr(this.divida, this.saldoAnterior, this.saldoAtual, this.pagoNoAno);
  final Reg divida;
  final double saldoAnterior, saldoAtual, pagoNoAno;
  String get discriminacao {
    final credor = _t(divida['credor']);
    final contrato = _t(divida['contrato']);
    return [
      _t(divida['tipo']).isEmpty ? 'Dívida' : _t(divida['tipo']),
      if (credor.isNotEmpty) 'com $credor',
      if (contrato.isNotEmpty) 'contrato $contrato',
      if (_t(divida['data']).length >= 10) 'de ${_br(divida['data'])}',
    ].join(' ');
  }
}

class AtividadeRuralIr {
  AtividadeRuralIr(this.ano, this.imoveis, this.meses, this.rebanho, this.bens, this.dividas, this.avisos);
  final int ano;
  final List<Reg> imoveis;
  final List<MesIr> meses;
  final RebanhoIr rebanho;
  final List<Reg> bens;
  final List<DividaIr> dividas;

  /// O que falta para o contador preencher ou conferir.
  final List<String> avisos;

  double get receitaBruta => meses.fold(0, (s, m) => s + m.receita);
  double get despesas => meses.fold(0, (s, m) => s + m.despesas);
  double get custeio => meses.fold(0, (s, m) => s + m.custeio);
  double get investimento => meses.fold(0, (s, m) => s + m.investimento);

  /// Resultado I: receita bruta menos as despesas de custeio e investimento.
  double get resultadoReal => receitaBruta - despesas;

  /// Opção pelo arbitramento: 20% da receita bruta.
  double get resultadoArbitrado => receitaBruta * 0.2;

  /// O arbitramento só compensa quando o lucro real passa de 20% da receita
  /// (e com ele se perde o prejuízo a compensar).
  bool get compensaArbitrar => resultadoReal > resultadoArbitrado;
}

String _br(Object? iso) {
  final d = _dia(iso);
  return d.length < 10 ? '' : '${d.substring(8, 10)}/${d.substring(5, 7)}/${d.substring(0, 4)}';
}

/// Saldo da dívida no fim do dia [data]: parcelas ainda não pagas até lá.
double _saldoEm(Reg d, String data) {
  if (_t(d['data']).length >= 10 && _dia(d['data']).compareTo(data) > 0) return 0; // contratada depois
  return parcelas(d).where((p) {
    if (p['pago'] != true) return true;
    final pago = _dia(p['pago_em']);
    return pago.isNotEmpty && pago.compareTo(data) > 0;
  }).fold(0.0, (s, p) => s + _n(p['valor']));
}

/// Data de chegada do animal ao rebanho e como chegou.
(String, String) _chegada(Reg a, Map<int, Reg> entradas) {
  final e = entradas[_int(a['entrada_id'])];
  if (e != null) return (_dia(e['data']), e['tipo'] == 'Compra' ? 'Compra' : 'Outra');
  if (a['origem'] == 'Nascimento') return (_dia(a['nascimento']), 'Nascimento');
  if (a['origem'] == 'Compra') return (_dia(a['data_entrada'] ?? a['criado_em']), 'Compra');
  // Cadastrado sem entrada: nascido na fazenda se a data de nascimento for a do cadastro ou depois.
  final nasc = _dia(a['nascimento']);
  final cad = _dia(a['criado_em']);
  if (nasc.isNotEmpty && (cad.isEmpty || nasc.compareTo(cad) >= 0)) return (nasc, 'Nascimento');
  return (cad, 'Outra');
}

RebanhoIr movimentacaoRebanho(int ano) {
  final r = RebanhoIr();
  final inicio = '$ano-01-01', fim = '$ano-12-31';
  final entradas = {for (final e in Db.registros('entradas')) _int(e['id'])!: e};
  final saidas = {for (final s in Db.registros('saidas')) _int(s['id'])!: s};
  for (final a in Db.registros('animais')) {
    final (chegou, como) = _chegada(a, entradas);
    final s = saidas[_int(a['saida_id'])];
    // Baixa sem registro de saída (status mudado à mão): sem data, não entra na conta.
    if (s == null && (a['status'] ?? 'Ativo') != 'Ativo') continue;
    final saiu = s == null ? '' : _dia(s['data']);
    if (chegou.isNotEmpty && chegou.compareTo(fim) > 0) continue;
    if (saiu.isNotEmpty && saiu.compareTo(inicio) < 0) continue;
    if (chegou.isEmpty || chegou.compareTo(inicio) < 0) {
      r.estoqueInicial++;
    } else {
      switch (como) {
        case 'Compra':
          r.aquisicoes++;
        case 'Nascimento':
          r.nascimentos++;
        default:
          r.outrasEntradas++;
      }
    }
    if (saiu.isNotEmpty && saiu.compareTo(fim) <= 0) {
      switch (s!['tipo']) {
        case 'Venda':
          r.vendas++;
        case 'Morte':
          r.mortes++;
        case 'Consumo':
          r.consumo++;
        default:
          r.outrasSaidas++;
      }
    }
  }
  return r;
}

AtividadeRuralIr atividadeRural(int ano) {
  final avisos = <String>[];
  final fin = relatorioFinanceiro(ano, todasPropriedades: true);
  final meses = [
    for (var m = 1; m <= 12; m++)
      () {
        final mes = '$ano-${m.toString().padLeft(2, '0')}';
        final doMes = fin.movimentos.where((x) => _dia(x['pago_em']).startsWith(mes));
        double soma(bool Function(Reg) f) => doMes.where(f).fold(0.0, (s, x) => s + _n(x['valor']));
        return MesIr(
          m,
          soma((x) => x['tipo'] == 'Receita'),
          soma((x) => x['tipo'] != 'Receita' && x['categoria'] != categoriaInvestimento),
          soma((x) => x['tipo'] != 'Receita' && x['categoria'] == categoriaInvestimento),
        );
      }(),
  ];

  final imoveis = [...Db.registros('propriedades')]..sort((a, b) => _t(a['nome']).compareTo(_t(b['nome'])));
  for (final p in imoveis) {
    final nome = _t(p['nome']);
    if (_t(p['lcdpr_cod_itr']).trim().isEmpty) avisos.add('$nome: falta o NIRF/CIB do imóvel.');
    if (areaPropriedade(p) <= 0) avisos.add('$nome: falta a área em hectares.');
  }
  if (_t(dadosLcdpr()['cpf']).trim().isEmpty) avisos.add('Falta o CPF do produtor (Dados do produtor).');

  final anterior = '${ano - 1}-12-31', fim = '$ano-12-31';
  final dividas = <DividaIr>[];
  for (final d in Db.registros('dividas')) {
    final pago = parcelas(d)
        .where((p) => p['pago'] == true && _dia(p['pago_em']).startsWith('$ano-'))
        .fold(0.0, (s, p) => s + _n(p['valor']));
    final x = DividaIr(d, _saldoEm(d, anterior), _saldoEm(d, fim), pago);
    if (x.saldoAnterior > 0 || x.saldoAtual > 0 || x.pagoNoAno > 0) dividas.add(x);
  }
  if (dividas.any((d) => parcelas(d.divida).any((p) => p['pago'] == true && _dia(p['pago_em']).isEmpty))) {
    avisos.add('Há parcelas de dívida pagas sem a data do pagamento; o saldo pode sair errado.');
  }

  final rebanho = movimentacaoRebanho(ano);
  final semData = Db.registros('animais').where((a) => (a['status'] ?? 'Ativo') != 'Ativo' && a['saida_id'] == null).length;
  if (semData > 0) avisos.add('$semData animal(is) baixado(s) sem registro de saída não entram na movimentação.');

  final listaBens = bens();
  if (listaBens.isNotEmpty) {
    avisos.add('Os bens estão pelo valor informado no Patrimônio. No IR vale o custo de aquisição; confira.');
  }
  return AtividadeRuralIr(ano, imoveis, meses, rebanho, listaBens, dividas, avisos);
}

/// Planilha com todos os quadros do anexo, na ordem do programa da Receita.
String planilhaAtividadeRural(int ano) {
  final a = atividadeRural(ano);
  final d = dadosLcdpr();
  final r = a.rebanho;
  final l = <List<Object?>>[
    ['Atividade rural · IRPF $ano (ano-calendário)', '', '', '', ''],
    ['Produtor', _t(d['nome']), 'CPF', _t(d['cpf']), ''],
    [],
    ['DADOS E IDENTIFICAÇÃO DO IMÓVEL', '', '', '', ''],
    ['Nome', 'NIRF/CIB', 'Área (ha)', 'Participação (%)', 'Condição de exploração'],
    for (final p in a.imoveis)
      [
        _t(p['nome']),
        _t(p['lcdpr_cod_itr']),
        areaPropriedade(p),
        p['lcdpr_participacao'] is num ? (p['lcdpr_participacao'] as num).toDouble() : 100.0,
        condicoesExploracao[_int(p['lcdpr_exploracao']) ?? 1],
      ],
    [],
    ['RECEITAS E DESPESAS', '', '', '', ''],
    ['Mês', 'Receita bruta', 'Despesas de custeio', 'Investimentos', 'Despesas (custeio + investimento)'],
    for (final m in a.meses) [nomeMes(m.mes), m.receita, m.custeio, m.investimento, m.despesas],
    ['Total', a.receitaBruta, a.custeio, a.investimento, a.despesas],
    [],
    ['APURAÇÃO DO RESULTADO', '', '', '', ''],
    ['Receita bruta total', a.receitaBruta, '', '', ''],
    ['Despesas de custeio e investimentos', a.despesas, '', '', ''],
    ['Resultado I (receita menos despesas)', a.resultadoReal, '', '', ''],
    ['20% da receita bruta (opção pelo arbitramento)', a.resultadoArbitrado, '', '', ''],
    ['Opção que dá menos imposto', a.compensaArbitrar ? '20% da receita bruta' : 'Resultado real', '', '', ''],
    [],
    ['MOVIMENTAÇÃO DO REBANHO (BOVINOS)', '', '', '', ''],
    ['Estoque inicial (31/12/${ano - 1})', r.estoqueInicial, '', '', ''],
    ['Aquisições no ano', r.aquisicoes, '', '', ''],
    ['Nascidos no ano', r.nascimentos, '', '', ''],
    if (r.outrasEntradas > 0) ['Outras entradas (doação, transferência)', r.outrasEntradas, '', '', ''],
    ['Consumo e perdas no ano', r.consumoPerdas, 'mortes ${r.mortes}', 'consumo ${r.consumo}', 'outras ${r.outrasSaidas}'],
    ['Vendas no ano', r.vendas, '', '', ''],
    ['Estoque final (31/12/$ano)', r.estoqueFinal, '', '', ''],
    [],
    ['BENS DA ATIVIDADE RURAL', '', '', '', ''],
    ['Discriminação', 'Tipo', 'Valor informado', '', ''],
    for (final b in a.bens) [_t(b['nome']), _t(b['tipo']), _n(b['valor']), '', ''],
    [],
    ['DÍVIDAS VINCULADAS À ATIVIDADE RURAL', '', '', '', ''],
    ['Discriminação', 'Situação em 31/12/${ano - 1}', 'Situação em 31/12/$ano', 'Valor pago em $ano', ''],
    for (final x in a.dividas) [x.discriminacao, x.saldoAnterior, x.saldoAtual, x.pagoNoAno, ''],
    if (a.avisos.isNotEmpty) ...[
      [],
      ['CONFERIR', '', '', '', ''],
      for (final x in a.avisos) [x, '', '', '', ''],
    ],
  ];
  return csv(l.first.map(_t).toList(), [for (final x in l.skip(1)) x.isEmpty ? ['', '', '', '', ''] : x]);
}

const _nomesMeses = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];
String nomeMes(int m) => _nomesMeses[m - 1];
