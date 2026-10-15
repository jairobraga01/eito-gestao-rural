import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/gestao.dart';
import '../util/util.dart';
import 'base.dart';

/// Custos lançados e a conta de cada lote: compra, custos, sêmen, vendas e margem.
class CustosPage extends StatelessWidget {
  const CustosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Custos e margem',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Lançar custo'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustoFormPage())),
      ),
      corpo: AoMudar<(List<ContaLote>, List<Reg>)>(
        carregar: () async => (contasPorLote(), Db.registros('custos').where((c) => c['propriedade_id'] == Db.pid).toList()
          ..sort((a, b) => txt(b['data']).compareTo(txt(a['data'])))),
        builder: (context, d) {
          final (contas, custos) = d;
          final (_, arroba) = ajustesArroba();
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            if (arroba == null)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text('Lance a arroba em Cotação da arroba para somar o valor do gado no pasto.'),
              ),
            if (contas.isEmpty) const Vazio('Nenhum lote ainda.', icone: Icons.attach_money),
            for (final c in contas) _ContaCard(c),
            Secao('Custos lançados (${custos.length})'),
            if (custos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Lance ração, sal, mão de obra e outros gastos. Sem lote, entram como custo geral.'),
              ),
            for (final c in custos)
              ListTile(
                dense: true,
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text('${c['categoria']}${txt(c['descricao']).isEmpty ? '' : ' · ${c['descricao']}'}'),
                subtitle: Text('${br(c['data'])} · ${txt(Db.registro('lotes', c['lote_id'])?['nome']).isEmpty ? 'Geral' : Db.registro('lotes', c['lote_id'])!['nome']}'),
                trailing: Text(moeda(c['valor'] as num?)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustoFormPage(custo: c))),
              ),
          ]);
        },
      ),
    );
  }
}

class _ContaCard extends StatelessWidget {
  const _ContaCard(this.c);
  final ContaLote c;

  @override
  Widget build(BuildContext context) {
    final cpa = c.custoPorArroba;
    final positivo = c.margem >= 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(c.nome, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(moeda(c.margem),
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: positivo ? Colors.green.shade700 : Colors.red)),
          ]),
          Text('${c.cabecas} cab. · ${c.ativos} no pasto · ${c.vendidos} vendidas',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Info('Compra dos animais', moeda(c.aquisicao)),
          Info('Custos lançados', moeda(c.custos)),
          Info('Sêmen', moeda(c.semen)),
          Info('Vendas', moeda(c.vendas)),
          Info('Gado no pasto', c.estoque == null ? '' : moeda(c.estoque)),
          Info('Arrobas produzidas', c.arrobasProduzidas <= 0 ? '' : '${num1(c.arrobasProduzidas)} @'),
          Info('Custo por arroba', cpa == null ? '' : moeda(cpa)),
        ]),
      ),
    );
  }
}

class CustoFormPage extends StatefulWidget {
  const CustoFormPage({super.key, this.custo});
  final Reg? custo;

  @override
  State<CustoFormPage> createState() => _CustoFormPageState();
}

class _CustoFormPageState extends State<CustoFormPage> {
  late final c = widget.custo;
  late String data = (c?['data'] as String?) ?? hojeIso();
  late String? categoria = (c?['categoria'] as String?) ?? categoriasCusto.first;
  late int? loteId = c?['lote_id'] as int?;
  late final descricao = TextEditingController(text: txt(c?['descricao']));
  late final valor = TextEditingController(
      text: c?['valor'] is num ? numeroBr((c!['valor'] as num).toDouble(), casas: 2) : '');

  @override
  void dispose() {
    descricao.dispose();
    valor.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final v = lerNumero(valor.text);
    if (v == null || v <= 0) {
      avisar(context, 'Informe o valor.');
      return;
    }
    final dados = {
      'data': data,
      'categoria': categoria,
      'lote_id': loteId,
      'descricao': nulo(descricao.text),
      'valor': v,
    };
    if (c == null) {
      await Db.inserir('custos', {...dados, 'propriedade_id': Db.pid});
    } else {
      await Db.atualizar('custos', c!['id'] as int, dados);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    if (await confirmar(context, 'Excluir custo?', 'O lançamento será apagado.', ok: 'Excluir')) {
      await Db.excluir('custos', c!['id'] as int);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Lançar custo' : 'Editar custo'),
        actions: [
          if (c != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      bottomNavigationBar: BotaoSalvar(onPressed: _salvar),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v!)),
        gap,
        escolha('Categoria', categoria, categoriasCusto, (v) => setState(() => categoria = v)),
        gap,
        AoMudar<List<Reg>>(
          carregar: () => Db.lotes(),
          builder: (context, lotes) =>
              escolhaId('Lote', loteId, lotes, (v) => setState(() => loteId = v), vazio: 'Geral (todos os lotes)'),
        ),
        gap,
        campoTexto(descricao, 'Descrição'),
        gap,
        TextField(
          controller: valor,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Valor *', prefixText: r'R$ '),
        ),
      ]),
    );
  }
}
