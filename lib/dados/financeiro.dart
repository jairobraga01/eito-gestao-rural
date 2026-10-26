// Contas a pagar e a receber, livro caixa, LCDPR (Livro Caixa Digital do
// Produtor Rural, leiaute 1.3 da Receita Federal) e planilhas para o
// contador e para a GTA.
import 'db.dart';
import 'dividas.dart' show dividas, saldoDevedor, parcelasAVencer;
import 'indicadores.dart' show faixaSidago;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _n(Object? v) => v is num ? v.toDouble() : 0;
String _t(Object? v) => v == null ? '' : '$v';
String _dia(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);
String _so(Object? v) => _t(v).replaceAll(RegExp(r'\D'), '');

// ---------- Contas a pagar e a receber ----------

const categoriasReceita = ['Venda de gado', 'Venda de leite', 'Venda de produtos', 'Arrendamento recebido', 'Outra receita'];
const categoriasDespesa = [
  'Compra de gado',
  'Ração, sal e suplemento',
  'Medicamentos e vacinas',
  'Sêmen e reprodução',
  'Mão de obra',
  'Combustível e manutenção',
  'Pastagem e adubo',
  'Arrendamento pago',
  'Impostos e taxas',
  'Investimento (máquinas, cercas, benfeitorias)',
  'Outra despesa',
];

/// Tipo de documento do LCDPR (campo TIPO_DOC).
const tiposDocumento = {1: 'Nota fiscal', 2: 'Fatura', 3: 'Recibo', 4: 'Contrato', 5: 'Folha de pagamento', 6: 'Outros'};

List<Reg> contas({bool? receita, bool? pagas, int? ano, bool todasPropriedades = false}) {
  final r = <Reg>[];
  for (final c in Db.registros('contas')) {
    if (!todasPropriedades && _int(c['propriedade_id']) != Db.pid) continue;
    if (receita != null && (c['tipo'] == 'Receita') != receita) continue;
    if (pagas != null && (c['pago'] == true) != pagas) continue;
    if (ano != null) {
      final d = c['pago'] == true ? _dia(c['pago_em']) : _dia(c['vencimento']);
      if (!d.startsWith('$ano-')) continue;
    }
    r.add(c);
  }
  String data(Reg c) => c['pago'] == true ? _dia(c['pago_em']) : _dia(c['vencimento']);
  return r..sort((a, b) => data(a).compareTo(data(b)));
}

Future<int> salvarConta(Reg v, {int? id}) async {
  if (id != null) {
    await Db.atualizar('contas', id, v);
    return id;
  }
  return Db.inserir('contas', {'pago': false, ...v, 'propriedade_id': Db.pid});
}

Future<void> pagarConta(int id, bool pago, String data) =>
    Db.atualizar('contas', id, {'pago': pago, 'pago_em': pago ? data : null});

/// Em aberto vencidas até [hoje] (atrasadas).
bool atrasada(Reg c, String hoje) => c['pago'] != true && _dia(c['vencimento']).compareTo(hoje) < 0;

/// Vendas, compras de gado e custos lançados no ano que ainda não estão nas
/// contas, no formato de conta paga (com a 'origem'). Não inclui o consumo de
/// ração tirado do estoque (a compra do insumo é que é o gasto).
List<Reg> _doRebanho(int ano, {bool todas = false}) {
  bool fora(Reg x) => !todas && _int(x['propriedade_id']) != Db.pid;
  final ja = {for (final c in Db.registros('contas')) _t(c['origem'])}..remove('');
  final doEstoque = {for (final e in Db.registros('estoque')) _t(e['grupo'])};
  final r = <Reg>[];
  bool doAno(Object? d) => _dia(d).startsWith('$ano-');
  void criar(String origem, Reg v) {
    if (!ja.contains(origem)) r.add({'pago': true, 'tipo_doc': 1, 'origem': origem, ...v});
  }

  for (final s in Db.registros('saidas')) {
    if (fora(s) || s['tipo'] != 'Venda' || _n(s['valor_total']) <= 0 || !doAno(s['data'])) continue;
    criar('saida:${s['id']}', {
      'tipo': 'Receita',
      'categoria': 'Venda de gado',
      'descricao': 'Venda de gado${_t(s['destino']).isEmpty ? '' : ' para ${s['destino']}'}',
      'participante': s['destino'],
      'valor': _n(s['valor_total']),
      'vencimento': _dia(s['data']),
      'pago_em': _dia(s['data']),
    });
    // A receita entra pelo valor bruto: o que foi descontado (Funrural, frete...)
    // volta como receita e sai como despesa. O caixa não muda.
    final descontos = [
      for (final (k, nome, cat) in const [
        ('funrural', 'Funrural', 'Impostos e taxas'),
        ('fundepec', 'Fundepec', 'Impostos e taxas'),
        ('nota', 'Nota fiscal', 'Impostos e taxas'),
        ('frete', 'Frete', 'Outra despesa'),
        ('outros', 'Outros descontos', 'Outra despesa'),
      ])
        if (_n(s[k]) > 0) (k, nome, cat, _n(s[k])),
    ];
    final soma = descontos.fold<double>(0, (t, d) => t + d.$4);
    if (_n(s['bruto']) > 0 && soma > 0) {
      criar('saida:${s['id']}:descontos', {
        'tipo': 'Receita',
        'categoria': 'Venda de gado',
        'descricao': 'Descontos da venda de gado (bruto ${_n(s['bruto']).toStringAsFixed(2)})',
        'participante': s['destino'],
        'valor': double.parse(soma.toStringAsFixed(2)),
        'vencimento': _dia(s['data']),
        'pago_em': _dia(s['data']),
      });
      for (final (k, nome, cat, v) in descontos) {
        criar('saida:${s['id']}:$k', {
          'tipo': 'Despesa',
          'categoria': cat,
          'descricao': '$nome da venda de gado',
          'participante': s['destino'],
          'valor': double.parse(v.toStringAsFixed(2)),
          'vencimento': _dia(s['data']),
          'pago_em': _dia(s['data']),
        });
      }
    }
  }
  for (final e in Db.registros('entradas')) {
    if (fora(e) || e['tipo'] != 'Compra' || _n(e['valor_total']) <= 0 || !doAno(e['data'])) continue;
    criar('entrada:${e['id']}', {
      'tipo': 'Despesa',
      'categoria': 'Compra de gado',
      'descricao': 'Compra de ${e['quantidade'] ?? ''} cab.${_t(e['origem']).isEmpty ? '' : ' de ${e['origem']}'}',
      'participante': e['origem'],
      'num_doc': e['gta'],
      'valor': _n(e['valor_total']),
      'vencimento': _dia(e['data']),
      'pago_em': _dia(e['data']),
    });
  }
  for (final c in Db.registros('custos')) {
    if (fora(c) || _n(c['valor']) <= 0 || !doAno(c['data'])) continue;
    if (doEstoque.contains(_t(c['id']))) continue; // consumo do estoque, não é pagamento
    criar('custo:${c['id']}', {
      'tipo': 'Despesa',
      'categoria': switch (c['categoria']) {
        'Ração e sal' => 'Ração, sal e suplemento',
        'Sanidade' => 'Medicamentos e vacinas',
        'Mão de obra' => 'Mão de obra',
        'Pastagem e arrendamento' => 'Pastagem e adubo',
        'Combustível e máquinas' => 'Combustível e manutenção',
        _ => 'Outra despesa',
      },
      'descricao': _t(c['descricao']).isEmpty ? _t(c['categoria']) : _t(c['descricao']),
      'valor': _n(c['valor']),
      'vencimento': _dia(c['data']),
      'pago_em': _dia(c['data']),
    });
  }
  return r;
}

/// Traz para as contas (já pagas) as vendas, compras de gado e custos lançados
/// no ano que ainda não estão lá. Retorna quantas contas criou.
Future<int> trazerDoRebanho(int ano) async {
  final novas = _doRebanho(ano);
  for (final v in novas) {
    await Db.inserir('contas', {'propriedade_id': Db.pid, ...v});
  }
  return novas.length;
}

// ---------- Relatório financeiro geral (só o dono) ----------

class RelatorioFinanceiro {
  RelatorioFinanceiro(this.ano, this.movimentos);
  final int ano;

  /// Contas pagas no ano e o que foi lançado no rebanho e ainda não virou conta.
  final List<Reg> movimentos;

  Iterable<Reg> get _receitas => movimentos.where((m) => m['tipo'] == 'Receita');
  Iterable<Reg> get _despesas => movimentos.where((m) => m['tipo'] != 'Receita');
  double get receitas => _receitas.fold(0, (s, m) => s + _n(m['valor']));
  double get despesas => _despesas.fold(0, (s, m) => s + _n(m['valor']));
  double get resultado => receitas - despesas;

  Map<String, double> _porCategoria(Iterable<Reg> l) {
    final r = <String, double>{};
    for (final m in l) {
      final c = _t(m['categoria']).isEmpty ? 'Sem categoria' : _t(m['categoria']);
      r[c] = (r[c] ?? 0) + _n(m['valor']);
    }
    return Map.fromEntries(r.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  Map<String, double> get receitasPorCategoria => _porCategoria(_receitas);
  Map<String, double> get despesasPorCategoria => _porCategoria(_despesas);

  /// Receitas e despesas de cada mês (índice 0 = janeiro).
  List<(double, double)> get porMes => [
        for (var m = 1; m <= 12; m++)
          () {
            final mes = '$ano-${m.toString().padLeft(2, '0')}';
            final doMes = movimentos.where((x) => _dia(x['pago_em']).startsWith(mes));
            return (
              doMes.where((x) => x['tipo'] == 'Receita').fold(0.0, (s, x) => s + _n(x['valor'])),
              doMes.where((x) => x['tipo'] != 'Receita').fold(0.0, (s, x) => s + _n(x['valor'])),
            );
          }(),
      ];
}

RelatorioFinanceiro relatorioFinanceiro(int ano, {bool todasPropriedades = false}) => RelatorioFinanceiro(ano, [
      ...contas(pagas: true, ano: ano, todasPropriedades: todasPropriedades),
      ..._doRebanho(ano, todas: todasPropriedades),
    ]..sort((a, b) => _dia(a['pago_em']).compareTo(_dia(b['pago_em']))));

// ---------- Livro caixa ----------

class LinhaCaixa {
  LinhaCaixa(this.conta, this.entrada, this.saida, this.saldo);
  final Reg conta;
  final double entrada, saida, saldo;
}

/// Contas pagas no ano, em ordem de data, com o saldo acumulado.
List<LinhaCaixa> livroCaixa(int ano, {bool todasPropriedades = false}) {
  var saldo = 0.0;
  return [
    for (final c in contas(pagas: true, ano: ano, todasPropriedades: todasPropriedades))
      () {
        final receita = c['tipo'] == 'Receita';
        saldo += receita ? _n(c['valor']) : -_n(c['valor']);
        return LinhaCaixa(c, receita ? _n(c['valor']) : 0, receita ? 0 : _n(c['valor']), saldo);
      }(),
  ];
}

// ---------- Planilhas (CSV para Excel em português) ----------

String _celula(Object? v) {
  final s = v is double ? v.toStringAsFixed(2).replaceAll('.', ',') : _t(v);
  return s.contains(RegExp(r'[;"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// CSV com ";" e vírgula decimal, que o Excel em português abre direto.
String csv(List<String> cabecalho, List<List<Object?>> linhas) =>
    '﻿${[cabecalho, ...linhas].map((l) => l.map(_celula).join(';')).join('\r\n')}\r\n';

String _br(Object? iso) {
  final d = _dia(iso);
  return d.length < 10 ? '' : '${d.substring(8, 10)}/${d.substring(5, 7)}/${d.substring(0, 4)}';
}

String _prop(Object? id) => _t(Db.registro('propriedades', id)?['nome']);

const _meses = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

String _reais(double v) {
  final neg = v < 0;
  final partes = v.abs().toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${neg ? '-' : ''}R\$ $inteiro,${partes[1]}';
}

/// Contas em aberto, dívidas e reprodução para o relatório financeiro.
class PosicaoFinanceira {
  PosicaoFinanceira(String hoje)
      : aReceber = contas(receita: true, pagas: false).fold(0.0, (s, c) => s + _n(c['valor'])),
        aPagar = contas(receita: false, pagas: false).fold(0.0, (s, c) => s + _n(c['valor'])),
        atrasadas = contas(pagas: false).where((c) => atrasada(c, hoje)).length,
        saldoDividas = dividas().fold(0.0, (s, d) => s + saldoDevedor(d)),
        parcelas12meses = parcelasAVencer(hoje, dias: 365).fold(0.0, (s, p) => s + p.valor);
  final double aReceber, aPagar, saldoDividas, parcelas12meses;
  final int atrasadas;
}

/// Relatório financeiro geral em texto (para o WhatsApp).
String textoRelatorioFinanceiro(int ano, String hoje) {
  final r = relatorioFinanceiro(ano);
  final p = PosicaoFinanceira(hoje);
  final b = StringBuffer()
    ..writeln('*Relatório financeiro $ano · ${_prop(Db.pid)}*')
    ..writeln()
    ..writeln('Receitas: ${_reais(r.receitas)}')
    ..writeln('Despesas: ${_reais(r.despesas)}')
    ..writeln('*Resultado: ${_reais(r.resultado)}*');
  if (r.receitasPorCategoria.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Receitas por categoria:');
    r.receitasPorCategoria.forEach((k, v) => b.writeln('  $k: ${_reais(v)}'));
  }
  if (r.despesasPorCategoria.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Despesas por categoria:');
    r.despesasPorCategoria.forEach((k, v) => b.writeln('  $k: ${_reais(v)}'));
  }
  b
    ..writeln()
    ..writeln('Em aberto: a receber ${_reais(p.aReceber)} · a pagar ${_reais(p.aPagar)}'
        '${p.atrasadas > 0 ? ' · ${p.atrasadas} atrasada(s)' : ''}')
    ..writeln('Dívidas: saldo devedor ${_reais(p.saldoDividas)} · vence em 12 meses ${_reais(p.parcelas12meses)}');
  return b.toString().trimRight();
}

/// Relatório financeiro geral em CSV: mês a mês e os lançamentos do ano.
String planilhaRelatorioFinanceiro(int ano) {
  final r = relatorioFinanceiro(ano);
  final pm = r.porMes;
  return csv(['Mês / Data', 'Tipo', 'Categoria', 'Histórico', 'Receitas', 'Despesas', 'Resultado'], [
    for (var i = 0; i < 12; i++) ['${_meses[i]}/$ano', 'Resumo do mês', '', '', pm[i].$1, pm[i].$2, pm[i].$1 - pm[i].$2],
    ['Total $ano', 'Resumo do ano', '', '', r.receitas, r.despesas, r.resultado],
    for (final m in r.movimentos)
      [
        _br(m['pago_em']),
        m['tipo'],
        m['categoria'],
        m['descricao'],
        m['tipo'] == 'Receita' ? _n(m['valor']) : '',
        m['tipo'] == 'Receita' ? '' : _n(m['valor']),
        '',
      ],
  ]);
}

String planilhaLivroCaixa(int ano) => csv(
      ['Data', 'Propriedade', 'Tipo', 'Categoria', 'Histórico', 'Participante', 'CPF/CNPJ', 'Documento', 'Entrada', 'Saída', 'Saldo'],
      [
        for (final l in livroCaixa(ano, todasPropriedades: true))
          [
            _br(l.conta['pago_em']),
            _prop(l.conta['propriedade_id']),
            l.conta['tipo'],
            l.conta['categoria'],
            l.conta['descricao'],
            l.conta['participante'],
            l.conta['participante_doc'],
            l.conta['num_doc'],
            l.entrada,
            l.saida,
            l.saldo,
          ],
      ],
    );

String planilhaContas(int ano) => csv(
      ['Vencimento', 'Propriedade', 'Tipo', 'Categoria', 'Descrição', 'Participante', 'CPF/CNPJ', 'Valor', 'Situação', 'Pago em'],
      [
        for (final c in contas(ano: ano, todasPropriedades: true))
          [
            _br(c['vencimento']),
            _prop(c['propriedade_id']),
            c['tipo'],
            c['categoria'],
            c['descricao'],
            c['participante'],
            c['participante_doc'],
            _n(c['valor']),
            c['pago'] == true ? 'Pago' : 'Em aberto',
            _br(c['pago_em']),
          ],
      ],
    );

/// Animais (ativos ou todos) da propriedade aberta, com a faixa do SIDAGO.
String planilhaRebanho(String data, {List<Reg>? animais}) {
  final lista = animais ??
      [
        for (final a in Db.registros('animais'))
          if (_int(a['propriedade_id']) == Db.pid && a['status'] == 'Ativo') a,
      ]
    ..sort((a, b) => _t(a['brinco']).compareTo(_t(b['brinco'])));
  final pesos = <int?, (String, double)>{};
  for (final p in Db.registros('pesagens')) {
    final id = _int(p['animal_id']);
    if (p['peso'] is! num) continue;
    if (pesos[id] == null || _dia(p['data']).compareTo(pesos[id]!.$1) >= 0) pesos[id] = (_dia(p['data']), _n(p['peso']));
  }
  return csv(
    ['Brinco', 'SISBOV / PNIB', 'Brinco eletrônico', 'Nome', 'Sexo', 'Nascimento', 'Faixa (SIDAGO)', 'Categoria', 'Raça', 'Lote', 'Último peso (kg)', 'Pesado em'],
    [
      for (final a in lista)
        [
          a['brinco'],
          a['sisbov'],
          a['rfid'],
          a['nome'],
          a['sexo'] == 'M' ? 'Macho' : 'Fêmea',
          _br(a['nascimento']),
          faixaSidago(a, data),
          a['categoria'],
          a['raca'],
          Db.registro('lotes', a['lote_id'])?['nome'],
          pesos[_int(a['id'])]?.$2,
          _br(pesos[_int(a['id'])]?.$1),
        ],
    ],
  );
}

// ---------- LCDPR ----------

/// Cadastro do produtor para o LCDPR (config "lcdpr"): cpf, nome, endereço,
/// num, compl, bairro, uf, cod_mun, cep, telefone, email, forma_apur,
/// contador_nome, contador_doc, contador_crc, contador_email, contador_fone
/// e "contas" (lista de {codigo, banco, nome_banco, agencia, numero}).
/// Cada propriedade guarda o seu imóvel: lcdpr_cod_itr, lcdpr_caepf, lcdpr_ie,
/// lcdpr_endereco, lcdpr_num, lcdpr_bairro, lcdpr_uf, lcdpr_cod_mun, lcdpr_cep,
/// lcdpr_exploracao (1 a 6) e lcdpr_participacao (%).
Reg dadosLcdpr() => Db.registro('config', 'lcdpr') ?? const {};

Future<void> salvarDadosLcdpr(Reg v) => Db.salvarConfig('lcdpr', v);

List<Reg> contasBancarias() => [
      for (final c in (dadosLcdpr()['contas'] as List?) ?? const []) Map<String, Object?>.from(c as Map),
    ];

String _data8(Object? iso) {
  final d = _dia(iso);
  return '${d.substring(8, 10)}${d.substring(5, 7)}${d.substring(0, 4)}';
}

String _valor(double v) => (v.abs() * 100).round().toString();
String _campo(Object? v) => _t(v).replaceAll('|', '/').replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();

class ArquivoLcdpr {
  ArquivoLcdpr(this.texto, this.avisos);
  final String texto;

  /// O que falta ou foi preenchido com um valor provisório.
  final List<String> avisos;
}

/// Gera o arquivo do LCDPR do ano com as contas pagas de todas as propriedades.
ArquivoLcdpr gerarLcdpr(int ano) {
  final d = dadosLcdpr();
  final avisos = <String>[];
  final linhas = <List<Object?>>[];
  final cpf = _so(d['cpf']);
  if (cpf.length != 11) avisos.add('CPF do produtor não informado ou incompleto.');
  for (final (campo, nome) in [
    ('nome', 'nome do produtor'),
    ('endereco', 'endereço do produtor'),
    ('bairro', 'bairro do produtor'),
    ('uf', 'UF do produtor'),
    ('cod_mun', 'código IBGE do município do produtor'),
    ('cep', 'CEP do produtor'),
    ('email', 'e-mail do produtor'),
  ]) {
    if (_t(d[campo]).trim().isEmpty) avisos.add('Falta o $nome.');
  }

  linhas.add(['0000', 'LCDPR', '0013', cpf, _campo(d['nome']), '0', '0', '', '0101$ano', '3112$ano']);
  linhas.add(['0010', _int(d['forma_apur']) ?? 1]);
  linhas.add([
    '0030',
    _campo(d['endereco']),
    _campo(d['num']).isEmpty ? 'SN' : _campo(d['num']),
    _campo(d['compl']),
    _campo(d['bairro']),
    _campo(d['uf']).toUpperCase(),
    _so(d['cod_mun']),
    _so(d['cep']),
    _so(d['telefone']),
    _campo(d['email']),
  ]);

  // Imóveis: as propriedades que têm lançamento no ano (ou todas, se nenhuma tiver).
  final lanc = contas(pagas: true, ano: ano, todasPropriedades: true);
  final props = Db.registros('propriedades').toList()..sort((a, b) => (_int(a['id']) ?? 0).compareTo(_int(b['id']) ?? 0));
  final comLanc = {for (final c in lanc) _int(c['propriedade_id'])};
  final usadas = props.where((p) => comLanc.contains(_int(p['id']))).toList();
  final imoveis = usadas.isEmpty ? props : usadas;
  final codImovel = <int?, String>{};
  for (final (i, p) in imoveis.indexed) {
    final cod = (i + 1).toString().padLeft(3, '0');
    codImovel[_int(p['id'])] = cod;
    final nome = _campo(p['nome']);
    if (_so(p['lcdpr_cod_itr']).isEmpty) avisos.add('$nome: falta o número do imóvel na Receita (NIRF/CIB).');
    if (_so(p['lcdpr_caepf']).isEmpty) avisos.add('$nome: falta o CAEPF.');
    if (_t(p['lcdpr_cod_mun']).isEmpty || _t(p['lcdpr_cep']).isEmpty) avisos.add('$nome: falta o endereço do imóvel (município e CEP).');
    final part = p['lcdpr_participacao'] is num ? (p['lcdpr_participacao'] as num).toDouble() : 100.0;
    final exploracao = _int(p['lcdpr_exploracao']) ?? 1;
    if (part < 100 || exploracao != 1) {
      avisos.add('$nome: exploração em conjunto ou arrendada pede o registro dos terceiros (0045); confira com o contador.');
    }
    linhas.add([
      '0040',
      cod,
      'BR',
      'BRL',
      _so(p['lcdpr_cod_itr']),
      _so(p['lcdpr_caepf']),
      _so(p['lcdpr_ie']),
      nome,
      _campo(p['lcdpr_endereco']),
      _campo(p['lcdpr_num']),
      '',
      _campo(p['lcdpr_bairro']),
      _campo(p['lcdpr_uf']).toUpperCase(),
      _so(p['lcdpr_cod_mun']),
      _so(p['lcdpr_cep']),
      exploracao,
      (part * 100).round().toString().padLeft(5, '0'),
    ]);
  }

  final bancos = contasBancarias();
  if (bancos.isEmpty) avisos.add('Cadastre pelo menos uma conta bancária.');
  for (final b in bancos) {
    linhas.add([
      '0050',
      (_int(b['codigo']) ?? 1).toString().padLeft(3, '0'),
      'BR',
      _so(b['banco']).padLeft(3, '0'),
      _campo(b['nome_banco']),
      _so(b['agencia']),
      _so(b['numero']),
    ]);
  }

  var saldo = 0.0;
  var semDoc = 0;
  final porMes = <int, (double, double)>{};
  for (final c in lanc) {
    final receita = c['tipo'] == 'Receita';
    final v = _n(c['valor']);
    saldo += receita ? v : -v;
    var partic = _so(c['participante_doc']);
    if (partic.length != 11 && partic.length != 14) {
      semDoc++;
      partic = cpf;
    }
    final mes = int.parse(_dia(c['pago_em']).substring(5, 7));
    final (e, s) = porMes[mes] ?? (0.0, 0.0);
    porMes[mes] = (e + (receita ? v : 0), s + (receita ? 0 : v));
    linhas.add([
      'Q100',
      _data8(c['pago_em']),
      codImovel[_int(c['propriedade_id'])] ?? '001',
      (_int(c['conta_banco']) ?? 0).toString().padLeft(3, '0'),
      _campo(c['num_doc']),
      _int(c['tipo_doc']) ?? 6,
      _campo(_t(c['descricao']).isEmpty ? c['categoria'] : c['descricao']),
      partic,
      receita ? 1 : 2,
      _valor(receita ? v : 0),
      _valor(receita ? 0 : v),
      _valor(saldo),
      saldo < 0 ? 'N' : 'P',
    ]);
  }
  if (lanc.isEmpty) avisos.add('Nenhuma conta paga no ano.');
  final faltam = _doRebanho(ano, todas: true).length;
  if (faltam > 0) {
    avisos.add('$faltam lançamento(s) do rebanho (vendas, compras, custos) ainda não estão nas contas: '
        'use "Trazer do rebanho" antes de gerar o LCDPR.');
  }
  if (semDoc > 0) avisos.add('$semDoc lançamento(s) sem CPF/CNPJ do participante: saíram com o CPF do produtor.');

  var acumulado = 0.0;
  for (var m = 1; m <= 12; m++) {
    final (e, s) = porMes[m] ?? (0.0, 0.0);
    acumulado += e - s;
    linhas.add(['Q200', '${m.toString().padLeft(2, '0')}$ano', _valor(e), _valor(s), _valor(acumulado), acumulado < 0 ? 'N' : 'P']);
  }

  linhas.add([
    '9999',
    _campo(d['contador_nome']),
    _so(d['contador_doc']),
    _campo(d['contador_crc']),
    _campo(d['contador_email']),
    _so(d['contador_fone']),
    '${linhas.length + 1}',
  ]);
  return ArquivoLcdpr('${linhas.map((l) => l.join('|')).join('\r\n')}\r\n', avisos);
}

// ---------- GTA ----------

/// Contagem por faixa do SIDAGO dos animais escolhidos para a GTA.
Map<String, int> resumoGta(List<Reg> animais, String data) {
  final r = <String, int>{};
  for (final a in animais) {
    final k = faixaSidago(a, data);
    r[k] = (r[k] ?? 0) + 1;
  }
  return r;
}
