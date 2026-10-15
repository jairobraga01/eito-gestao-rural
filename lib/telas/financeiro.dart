// Contas a pagar e a receber e exportações (contador, LCDPR e GTA).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dados/db.dart';
import '../dados/financeiro.dart';
import '../dados/indicadores.dart' show colunasSidago;
import '../dispositivos/arquivo_stub.dart' if (dart.library.js_interop) '../dispositivos/arquivo_web.dart';
import '../util/util.dart';
import 'base.dart';

/// Baixa o arquivo; se o navegador não deixar, copia o texto.
Future<void> entregarArquivo(BuildContext context, String nome, String conteudo, {String tipo = 'text/csv'}) async {
  if (baixarArquivo(nome, conteudo, tipo: tipo)) {
    avisar(context, 'Arquivo $nome baixado.');
    return;
  }
  await Clipboard.setData(ClipboardData(text: conteudo));
  if (context.mounted) avisar(context, 'Não deu para baixar; o conteúdo foi copiado.');
}

// ======================= Contas a pagar e receber =======================

class ContasPage extends StatefulWidget {
  const ContasPage({super.key});

  @override
  State<ContasPage> createState() => _ContasPageState();
}

class _ContasPageState extends State<ContasPage> {
  String filtro = 'pagar'; // pagar, receber, pagas

  Future<void> _trazer() async {
    final ano = DateTime.now().year;
    final ok = await confirmar(
      context,
      'Trazer vendas, compras e custos?',
      'Cria contas já pagas com as vendas de gado, compras de gado e custos lançados em $ano que ainda não estão aqui. '
          'O consumo de ração tirado do estoque não entra (a compra do insumo é que é o gasto).',
      ok: 'Trazer',
    );
    if (!ok) return;
    final n = await trazerDoRebanho(ano);
    if (mounted) avisar(context, n == 0 ? 'Nada novo para trazer.' : '$n conta(s) criada(s).');
  }

  @override
  Widget build(BuildContext context) {
    final hoje = hojeIso();
    return Pagina(
      titulo: 'Contas a pagar e receber',
      acoes: [
        IconButton(tooltip: 'Trazer vendas, compras e custos', icon: const Icon(Icons.download_outlined), onPressed: _trazer),
        IconButton(
          tooltip: 'Exportações (contador, LCDPR, GTA)',
          icon: const Icon(Icons.ios_share),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportacoesPage())),
        ),
      ],
      fab: FloatingActionButton(
        heroTag: null,
        tooltip: 'Nova conta',
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ContaFormPage(receita: filtro == 'receber'))),
        child: const Icon(Icons.add),
      ),
      corpo: AoMudar<(List<Reg>, double, double)>(
        carregar: () async {
          final lista = switch (filtro) {
            'pagar' => contas(receita: false, pagas: false),
            'receber' => contas(receita: true, pagas: false),
            _ => contas(pagas: true).reversed.toList(),
          };
          double soma(List<Reg> l) => l.fold(0.0, (s, c) => s + ((c['valor'] as num?)?.toDouble() ?? 0));
          return (lista, soma(contas(receita: false, pagas: false)), soma(contas(receita: true, pagas: false)));
        },
        builder: (context, d) {
          final (lista, aPagar, aReceber) = d;
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(children: [
                Expanded(child: SizedBox(height: 90, child: Kpi('A pagar', moeda(aPagar), icone: Icons.call_made, cor: Colors.red))),
                Expanded(
                    child: SizedBox(height: 90, child: Kpi('A receber', moeda(aReceber), icone: Icons.call_received, cor: Colors.green))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'pagar', label: Text('A pagar')),
                  ButtonSegment(value: 'receber', label: Text('A receber')),
                  ButtonSegment(value: 'pagas', label: Text('Pagas')),
                ],
                selected: {filtro},
                onSelectionChanged: (s) => setState(() => filtro = s.first),
              ),
            ),
            if (lista.isEmpty) const Vazio('Nenhuma conta aqui.', icone: Icons.receipt_long_outlined),
            for (final c in lista)
              ListTile(
                leading: Icon(c['tipo'] == 'Receita' ? Icons.call_received : Icons.call_made,
                    color: c['tipo'] == 'Receita' ? Colors.green : Colors.red),
                title: Text(txt(c['descricao']).isEmpty ? txt(c['categoria']) : txt(c['descricao'])),
                subtitle: Text([
                  c['pago'] == true ? 'Pago em ${br(c['pago_em'])}' : 'Vence ${br(c['vencimento'])}',
                  if (atrasada(c, hoje)) 'ATRASADA',
                  if (txt(c['participante']).isNotEmpty) txt(c['participante']),
                ].join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(moeda(c['valor'] as num?), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Checkbox(
                    value: c['pago'] == true,
                    onChanged: (v) => pagarConta(c['id'] as int, v ?? false, hoje),
                  ),
                ]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContaFormPage(conta: c))),
              ),
          ]);
        },
      ),
    );
  }
}

class ContaFormPage extends StatefulWidget {
  const ContaFormPage({super.key, this.conta, this.receita = false});
  final Reg? conta;
  final bool receita;

  @override
  State<ContaFormPage> createState() => _ContaFormPageState();
}

class _ContaFormPageState extends State<ContaFormPage> {
  late final c = widget.conta;
  late bool receita = c == null ? widget.receita : c!['tipo'] == 'Receita';
  late String? categoria = c?['categoria'] as String?;
  late final descricao = TextEditingController(text: txt(c?['descricao']));
  late final valor = TextEditingController(text: c?['valor'] is num ? numeroBr((c!['valor'] as num).toDouble(), casas: 2) : '');
  late final participante = TextEditingController(text: txt(c?['participante']));
  late final doc = TextEditingController(text: txt(c?['participante_doc']));
  late final numDoc = TextEditingController(text: txt(c?['num_doc']));
  late String vencimento = (c?['vencimento'] as String?) ?? hojeIso();
  late bool pago = c?['pago'] == true;
  late String? pagoEm = c?['pago_em'] as String?;
  late int tipoDoc = (c?['tipo_doc'] as int?) ?? 1;
  late int contaBanco = (c?['conta_banco'] as int?) ?? 0;

  @override
  void dispose() {
    for (final x in [descricao, valor, participante, doc, numDoc]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> salvar() async {
    final v = lerNumero(valor.text);
    if (v == null || v <= 0) {
      avisar(context, 'Informe o valor.');
      return;
    }
    await salvarConta({
      'tipo': receita ? 'Receita' : 'Despesa',
      'categoria': categoria ?? (receita ? categoriasReceita.last : categoriasDespesa.last),
      'descricao': nulo(descricao.text),
      'valor': v,
      'vencimento': vencimento,
      'pago': pago,
      'pago_em': pago ? (pagoEm ?? hojeIso()) : null,
      'participante': nulo(participante.text),
      'participante_doc': nulo(doc.text),
      'num_doc': nulo(numDoc.text),
      'tipo_doc': tipoDoc,
      'conta_banco': contaBanco,
    }, id: c?['id'] as int?);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cats = receita ? categoriasReceita : categoriasDespesa;
    final bancos = contasBancarias();
    return Scaffold(
      appBar: AppBar(title: Text(c == null ? 'Nova conta' : 'Conta'), actions: [
        if (c != null)
          IconButton(
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirmar(context, 'Excluir conta?', 'Ela sai também do livro caixa.', ok: 'Excluir')) return;
              await Db.excluir('contas', c!['id'] as int);
              if (context.mounted) Navigator.pop(context);
            },
          ),
      ]),
      bottomNavigationBar: BotaoSalvar(onPressed: salvar),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Despesa (a pagar)'), icon: Icon(Icons.call_made)),
            ButtonSegment(value: true, label: Text('Receita (a receber)'), icon: Icon(Icons.call_received)),
          ],
          selected: {receita},
          onSelectionChanged: (s) => setState(() {
            receita = s.first;
            categoria = null;
          }),
        ),
        gap,
        escolha('Categoria', cats.contains(categoria) ? categoria : null, cats, (v) => setState(() => categoria = v)),
        gap,
        campoTexto(descricao, 'Descrição (histórico)'),
        gap,
        TextField(
          controller: valor,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Valor *', prefixText: r'R$ '),
        ),
        gap,
        DateField(label: 'Vencimento', value: vencimento, obrigatorio: true, onChanged: (x) => setState(() => vencimento = x!)),
        gap,
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(receita ? 'Recebido' : 'Pago'),
          value: pago,
          onChanged: (v) => setState(() {
            pago = v;
            pagoEm ??= hojeIso();
          }),
        ),
        if (pago)
          DateField(label: receita ? 'Recebido em' : 'Pago em', value: pagoEm, obrigatorio: true, onChanged: (x) => setState(() => pagoEm = x)),
        const Secao('Para o livro caixa (LCDPR)'),
        campoTexto(participante, receita ? 'Comprador / pagador' : 'Fornecedor / recebedor'),
        gap,
        campoTexto(doc, 'CPF ou CNPJ dele', numero: true),
        gap,
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: tipoDoc,
              decoration: const InputDecoration(labelText: 'Documento'),
              items: [for (final e in tiposDocumento.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => tipoDoc = v ?? 6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: campoTexto(numDoc, 'Número')),
        ]),
        gap,
        DropdownButtonFormField<int>(
          initialValue: bancos.any((b) => b['codigo'] == contaBanco) ? contaBanco : 0,
          decoration: const InputDecoration(labelText: 'Pago por'),
          items: [
            const DropdownMenuItem(value: 0, child: Text('Dinheiro (espécie)')),
            for (final b in bancos)
              DropdownMenuItem(value: b['codigo'] as int, child: Text('${b['nome_banco']} · ag. ${b['agencia']} c/c ${b['numero']}')),
          ],
          onChanged: (v) => setState(() => contaBanco = v ?? 0),
        ),
      ]),
    );
  }
}

// ======================= Exportações =======================

class ExportacoesPage extends StatefulWidget {
  const ExportacoesPage({super.key, this.doMenu = false});

  /// Aberta pelo menu lateral (com o menu), ou por cima de outra tela.
  final bool doMenu;

  @override
  State<ExportacoesPage> createState() => _ExportacoesPageState();
}

class _ExportacoesPageState extends State<ExportacoesPage> {
  int ano = DateTime.now().year;

  Future<void> _lcdpr() async {
    final a = gerarLcdpr(ano);
    if (a.avisos.isNotEmpty) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Confira antes de mandar'),
          content: SingleChildScrollView(child: Text(a.avisos.map((x) => '• $x').join('\n'))),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(c, false);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DadosLcdprPage()));
              },
              child: const Text('Completar dados'),
            ),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Baixar assim')),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }
    final cpf = txt(dadosLcdpr()['cpf']).replaceAll(RegExp(r'\D'), '');
    await entregarArquivo(context, 'LCDPR_${cpf.isEmpty ? 'produtor' : cpf}_$ano.txt', a.texto, tipo: 'text/plain');
  }

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icone, String titulo, String sub, VoidCallback onTap) => ListTile(
          leading: Icon(icone),
          title: Text(titulo),
          subtitle: Text(sub),
          trailing: const Icon(Icons.download_outlined),
          onTap: onTap,
        );
    final corpo = ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => ano--)),
          Text('$ano', style: Theme.of(context).textTheme.titleLarge),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => ano++)),
        ]),
        const Secao('Para o contador'),
        item(Icons.menu_book_outlined, 'Livro caixa (planilha)', 'Contas pagas e recebidas no ano, com o saldo',
            () => entregarArquivo(context, 'livro_caixa_$ano.csv', planilhaLivroCaixa(ano))),
        item(Icons.receipt_long_outlined, 'Contas a pagar e receber (planilha)', 'Todas as contas do ano, pagas ou em aberto',
            () => entregarArquivo(context, 'contas_$ano.csv', planilhaContas(ano))),
        item(Icons.pets_outlined, 'Rebanho (planilha)', 'Animais ativos com SISBOV, faixa do SIDAGO e último peso',
            () => entregarArquivo(context, 'rebanho_${hojeIso()}.csv', planilhaRebanho(hojeIso()))),
        const Secao('Receita Federal'),
        item(Icons.description_outlined, 'LCDPR (arquivo da Receita)', 'Livro Caixa Digital do Produtor Rural, leiaute 1.3', _lcdpr),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Dados do produtor, imóvel e contas bancárias'),
          subtitle: const Text('CPF, CAEPF, NIRF/CIB e endereço que o LCDPR pede'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DadosLcdprPage())),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Confira o arquivo no programa do LCDPR da Receita antes de transmitir. '
              'O livro usa as contas marcadas como pagas ou recebidas.'),
        ),
        const Secao('GTA e SISBOV'),
        ListTile(
          leading: const Icon(Icons.local_shipping_outlined),
          title: const Text('Animais para a GTA'),
          subtitle: const Text('Escolha os animais: quantidade por faixa do SIDAGO e planilha com os números'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GtaPage())),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('A GTA continua sendo emitida no SIDAGO (Agrodefesa). O Eito prepara os números para digitar lá.'),
        ),
      ]);
    return widget.doMenu
        ? Pagina(titulo: 'Exportações', corpo: corpo)
        : Scaffold(appBar: AppBar(title: const Text('Exportações')), body: corpo);
  }
}

// ======================= GTA =======================

class GtaPage extends StatefulWidget {
  const GtaPage({super.key});

  @override
  State<GtaPage> createState() => _GtaPageState();
}

class _GtaPageState extends State<GtaPage> {
  List<Reg> animais = [];

  @override
  Widget build(BuildContext context) {
    final hoje = hojeIso();
    final r = resumoGta(animais, hoje);
    return Scaffold(
      appBar: AppBar(title: const Text('Animais para a GTA')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.checklist),
          label: Text(animais.isEmpty ? 'Escolher animais' : '${animais.length} animal(is) – alterar'),
          onPressed: () async {
            final x = await pickAnimais(context, iniciais: [for (final a in animais) a['id'] as int]);
            if (x != null) setState(() => animais = x);
          },
        ),
        if (animais.isNotEmpty) ...[
          const Secao('Quantidade por faixa (como no SIDAGO)'),
          for (final c in colunasSidago)
            if ((r[c] ?? 0) > 0) Info(c, '${r[c]}'),
          Info('Total', '${animais.length}'),
          gap,
          FilledButton.icon(
            icon: const Icon(Icons.download_outlined),
            label: const Text('Baixar planilha dos animais'),
            onPressed: () => entregarArquivo(context, 'gta_$hoje.csv', planilhaRebanho(hoje, animais: animais)),
          ),
          gap,
          OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copiar resumo'),
            onPressed: () async {
              final texto = [
                'Animais para a GTA (${br(hoje)})',
                for (final c in colunasSidago)
                  if ((r[c] ?? 0) > 0) '$c: ${r[c]}',
                'Total: ${animais.length}',
                'Brincos: ${animais.map((a) => txt(a['sisbov']).isEmpty ? a['brinco'] : '${a['brinco']} (${a['sisbov']})').join(', ')}',
              ].join('\n');
              await Clipboard.setData(ClipboardData(text: texto));
              if (context.mounted) avisar(context, 'Resumo copiado.');
            },
          ),
        ],
      ]),
    );
  }
}

// ======================= Dados do LCDPR =======================

class DadosLcdprPage extends StatefulWidget {
  const DadosLcdprPage({super.key});

  @override
  State<DadosLcdprPage> createState() => _DadosLcdprPageState();
}

class _DadosLcdprPageState extends State<DadosLcdprPage> {
  static const _produtor = [
    ('cpf', 'CPF do produtor *'),
    ('nome', 'Nome completo *'),
    ('endereco', 'Endereço *'),
    ('num', 'Número'),
    ('compl', 'Complemento'),
    ('bairro', 'Bairro *'),
    ('uf', 'UF *'),
    ('cod_mun', 'Código IBGE do município *'),
    ('cep', 'CEP *'),
    ('telefone', 'Telefone com DDD'),
    ('email', 'E-mail *'),
    ('contador_nome', 'Contador: nome'),
    ('contador_doc', 'Contador: CPF ou CNPJ'),
    ('contador_crc', 'Contador: CRC'),
    ('contador_email', 'Contador: e-mail'),
    ('contador_fone', 'Contador: telefone'),
  ];
  static const _imovel = [
    ('lcdpr_cod_itr', 'NIRF / CIB do imóvel (Receita)'),
    ('lcdpr_caepf', 'CAEPF'),
    ('lcdpr_ie', 'Inscrição estadual'),
    ('lcdpr_endereco', 'Endereço do imóvel'),
    ('lcdpr_num', 'Número'),
    ('lcdpr_bairro', 'Bairro / localidade'),
    ('lcdpr_uf', 'UF'),
    ('lcdpr_cod_mun', 'Código IBGE do município'),
    ('lcdpr_cep', 'CEP'),
    ('lcdpr_participacao', 'Participação (%)'),
  ];
  static const _exploracoes = {1: 'Própria (individual)', 2: 'Condomínio', 3: 'Arrendada', 4: 'Parceria', 5: 'Comodato', 6: 'Outros'};

  late final Reg d = dadosLcdpr();
  late final Reg p = Db.prop.value ?? const {};
  late final campos = {for (final (k, _) in _produtor) k: TextEditingController(text: txt(d[k]))};
  late final imovel = {
    for (final (k, _) in _imovel)
      k: TextEditingController(text: k == 'lcdpr_participacao' && p[k] == null ? '100' : txt(p[k]))
  };
  late int forma = (d['forma_apur'] as int?) ?? 1;
  late int exploracao = (p['lcdpr_exploracao'] as int?) ?? 1;
  // Código de cada conta (fica igual ao apagar outra) e os campos dela.
  late final bancos = [
    for (final b in contasBancarias())
      (
        (b['codigo'] as int?) ?? 1,
        {for (final k in ['banco', 'nome_banco', 'agencia', 'numero']) k: TextEditingController(text: txt(b[k]))},
      ),
  ];

  @override
  void dispose() {
    for (final c in [...campos.values, ...imovel.values, for (final (_, b) in bancos) ...b.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> salvar() async {
    await salvarDadosLcdpr({
      for (final e in campos.entries) e.key: nulo(e.value.text),
      'forma_apur': forma,
      'contas': [
        for (final (codigo, b) in bancos) {'codigo': codigo, for (final e in b.entries) e.key: nulo(e.value.text)},
      ],
    });
    if (p['id'] != null) {
      await Db.atualizar('propriedades', p['id'] as int, {
        for (final e in imovel.entries)
          e.key: e.key == 'lcdpr_participacao' ? lerNumero(e.value.text) : nulo(e.value.text),
        'lcdpr_exploracao': exploracao,
      });
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dados para o LCDPR')),
      bottomNavigationBar: BotaoSalvar(onPressed: salvar),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Os campos com * são obrigatórios no arquivo da Receita.'),
        const Secao('Produtor'),
        for (final (k, rotulo) in _produtor.take(11)) ...[campoTexto(campos[k]!, rotulo), gap],
        DropdownButtonFormField<int>(
          initialValue: forma,
          decoration: const InputDecoration(labelText: 'Forma de apuração'),
          items: const [
            DropdownMenuItem(value: 1, child: Text('Livro caixa')),
            DropdownMenuItem(value: 2, child: Text('Lucro presumido (20% da receita)')),
          ],
          onChanged: (v) => setState(() => forma = v ?? 1),
        ),
        Secao('Imóvel: ${txt(p['nome'])}'),
        const Text('Preencha em cada propriedade (troque a propriedade no topo do app).'),
        gap,
        for (final (k, rotulo) in _imovel) ...[campoTexto(imovel[k]!, rotulo, numero: k == 'lcdpr_participacao'), gap],
        DropdownButtonFormField<int>(
          initialValue: exploracao,
          decoration: const InputDecoration(labelText: 'Tipo de exploração'),
          items: [for (final e in _exploracoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => exploracao = v ?? 1),
        ),
        Secao('Contas bancárias',
            acao: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Conta'),
              onPressed: () => setState(() => bancos.add((
                    bancos.fold(0, (m, b) => b.$1 > m ? b.$1 : m) + 1,
                    {for (final k in ['banco', 'nome_banco', 'agencia', 'numero']) k: TextEditingController()},
                  ))),
            )),
        for (final (i, (codigo, b)) in bancos.indexed)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Text('Conta $codigo', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => bancos.removeAt(i)),
                  ),
                ]),
                Row(children: [
                  SizedBox(width: 90, child: campoTexto(b['banco']!, 'Cód. banco', numero: true)),
                  const SizedBox(width: 8),
                  Expanded(child: campoTexto(b['nome_banco']!, 'Banco')),
                ]),
                gap,
                Row(children: [
                  SizedBox(width: 110, child: campoTexto(b['agencia']!, 'Agência', numero: true)),
                  const SizedBox(width: 8),
                  Expanded(child: campoTexto(b['numero']!, 'Conta com dígito')),
                ]),
              ]),
            ),
          ),
        const Secao('Contador (opcional)'),
        for (final (k, rotulo) in _produtor.skip(11)) ...[campoTexto(campos[k]!, rotulo), gap],
      ]),
    );
  }
}
