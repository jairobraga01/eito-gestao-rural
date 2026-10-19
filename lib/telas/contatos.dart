// Fornecedores e compradores: cadastro e histórico de negócios.
import 'package:flutter/material.dart';

import '../dados/contatos.dart';
import '../dados/db.dart';
import '../util/util.dart';
import 'base.dart';

class ContatosPage extends StatelessWidget {
  const ContatosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Fornecedores e compradores',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Novo contato'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContatoFormPage())),
      ),
      corpo: AoMudar<List<Reg>>(
        carregar: () async => contatos(),
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio(
                'Nenhum contato.\nCadastre quem vende e quem compra gado de você. '
                'Nas compras e vendas dá para escolher o nome na lista.',
                icone: Icons.contacts_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final k = lista[i];
              final h = historicoDoContato(k);
              return ListTile(
                leading: Icon(k['tipo'] == 'Comprador' ? Icons.arrow_circle_up_outlined : Icons.arrow_circle_down_outlined,
                    color: k['tipo'] == 'Comprador' ? Colors.red : Colors.green),
                title: Text(txt(k['nome'])),
                subtitle: Text([
                  txt(k['tipo']),
                  if (txt(k['telefone']).isNotEmpty) txt(k['telefone']),
                  if (h.compras > 0) '${h.cabecasCompradas} cab. compradas',
                  if (h.vendas > 0) '${h.cabecasVendidas} cab. vendidas',
                ].join(' · ')),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContatoFormPage(contato: k))),
              );
            },
          );
        },
      ),
    );
  }
}

class ContatoFormPage extends StatefulWidget {
  const ContatoFormPage({super.key, this.contato, this.tipo = 'Os dois'});
  final Reg? contato;
  final String tipo;

  @override
  State<ContatoFormPage> createState() => _ContatoFormPageState();
}

class _ContatoFormPageState extends State<ContatoFormPage> {
  late final c = widget.contato;
  late final nome = TextEditingController(text: txt(c?['nome']));
  late final doc = TextEditingController(text: txt(c?['documento']));
  late final telefone = TextEditingController(text: txt(c?['telefone']));
  late final cidade = TextEditingController(text: txt(c?['cidade']));
  late final obs = TextEditingController(text: txt(c?['obs']));
  late String? tipo = txt(c?['tipo']).isEmpty ? widget.tipo : txt(c?['tipo']);

  @override
  void dispose() {
    for (final x in [nome, doc, telefone, cidade, obs]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> salvar() async {
    if (nome.text.trim().isEmpty) {
      avisar(context, 'Informe o nome.');
      return;
    }
    final v = {
      'nome': nome.text.trim(),
      'tipo': tipo,
      'documento': nulo(doc.text),
      'telefone': nulo(telefone.text),
      'cidade': nulo(cidade.text),
      'obs': nulo(obs.text),
    };
    if (c == null) {
      await Db.inserir('contatos', {...v, 'propriedade_id': Db.pid});
    } else {
      await Db.atualizar('contatos', c!['id'] as int, v);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> excluir() async {
    if (!await confirmar(context, 'Excluir contato?',
        'As compras e vendas já lançadas continuam, só o cadastro some.',
        ok: 'Excluir')) {
      return;
    }
    await Db.excluir('contatos', c!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final h = c == null ? null : historicoDoContato(c!);
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'NOVO CONTATO' : 'CONTATO'),
        actions: [
          if (c != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: excluir),
        ],
      ),
      bottomNavigationBar: BotaoSalvar(onPressed: salvar),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          campoTexto(nome, 'Nome *'),
          gap,
          escolha('É', tipo, tiposContato, (v) => setState(() => tipo = v)),
          gap,
          campoTexto(doc, 'CPF ou CNPJ'),
          gap,
          campoTexto(telefone, 'Telefone / WhatsApp'),
          gap,
          campoTexto(cidade, 'Cidade / UF'),
          gap,
          campoTexto(obs, 'Observações', linhas: 3),
          if (h != null) ...[
            const Secao('Histórico de negócios'),
            Info('Compras', h.compras == 0 ? 'Nenhuma' : '${h.compras} · ${h.cabecasCompradas} cab. · ${moeda(h.totalComprado)}'),
            if (h.precoMedioCompra != null) Info('Preço médio pago por cabeça', moeda(h.precoMedioCompra!)),
            Info('Vendas', h.vendas == 0 ? 'Nenhuma' : '${h.vendas} · ${h.cabecasVendidas} cab. · ${moeda(h.totalVendido)}'),
            if (h.precoMedioVenda != null) Info('Preço médio recebido por cabeça', moeda(h.precoMedioVenda!)),
            if (h.contasAbertas > 0) Info('Contas em aberto', moeda(h.contasAbertas)),
            if (h.ultimo != null) Info('Último negócio', br(h.ultimo)),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('O histórico junta as compras e vendas em que o nome do vendedor ou do comprador é igual ao deste cadastro.'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Campo de texto do vendedor/comprador com botão para escolher do cadastro.
class CampoContato extends StatelessWidget {
  const CampoContato({super.key, required this.controller, required this.label, required this.tipo});
  final TextEditingController controller;
  final String label;

  /// 'Fornecedor' ou 'Comprador'.
  final String tipo;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: 'Escolher do cadastro',
          icon: const Icon(Icons.contacts_outlined),
          onPressed: () async {
            final lista = contatosPara(tipo);
            final escolhido = await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              builder: (c) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
                  if (lista.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nenhum contato cadastrado. Cadastre em Financeiro > Fornecedores e compradores.'),
                    ),
                  for (final k in lista)
                    ListTile(
                      title: Text(txt(k['nome'])),
                      subtitle: txt(k['cidade']).isEmpty ? null : Text(txt(k['cidade'])),
                      onTap: () => Navigator.pop(c, txt(k['nome'])),
                    ),
                ]),
              ),
            );
            if (escolhido != null) controller.text = escolhido;
          },
        ),
      ),
    );
  }
}
