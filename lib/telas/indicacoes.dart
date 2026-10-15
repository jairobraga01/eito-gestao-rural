// Códigos de indicação: cadastro e adesões por código (só o administrador).
import 'package:flutter/material.dart';

import '../dados/indicacoes.dart';
import '../tema.dart';
import '../util/util.dart';

class IndicacoesPage extends StatefulWidget {
  const IndicacoesPage({super.key});

  @override
  State<IndicacoesPage> createState() => _IndicacoesPageState();
}

class _IndicacoesPageState extends State<IndicacoesPage> {
  late Future<List<(Indicacao, int)>> _lista = _carregar();

  Future<List<(Indicacao, int)>> _carregar() async {
    final codigos = await Indicacoes.todas();
    return [for (final i in codigos) (i, await Indicacoes.adesoes(i.codigo))];
  }

  void _recarregar() => setState(() => _lista = _carregar());

  Future<void> _editar([Indicacao? atual]) async {
    final codigo = TextEditingController(text: atual?.codigo);
    final nome = TextEditingController(text: atual?.nome);
    var tipo = atual?.tipo ?? tiposIndicacao.keys.first;
    var ativo = atual?.ativo ?? true;
    final salvar = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(atual == null ? 'Novo código' : 'Código ${atual.codigo}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (atual == null)
                TextField(
                  controller: codigo,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Código', hintText: 'Ex.: carolnutroeste'),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: nome,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome de quem indica'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final t in tiposIndicacao.entries) DropdownMenuItem(value: t.key, child: Text(t.value)),
                ],
                onChanged: (v) => set(() => tipo = v ?? tipo),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ativo'),
                value: ativo,
                onChanged: (v) => set(() => ativo = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (salvar != true || !mounted) return;
    final cod = atual?.codigo ?? codigoIndicacao(codigo.text);
    if (cod.isEmpty || cod.contains('/')) {
      avisar(context, 'Digite um código sem barras.');
      return;
    }
    try {
      final ok = await Indicacoes.salvar(
        Indicacao(codigo: cod, nome: nome.text.trim(), tipo: tipo, ativo: ativo),
        novo: atual == null,
      );
      if (!mounted) return;
      avisar(context, ok ? 'Código $cod salvo.' : 'O código $cod já existe.');
      if (ok) _recarregar();
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível salvar: $e');
    }
  }

  Future<void> _apagar(Indicacao i) async {
    if (!await confirmar(context, 'Apagar o código ${i.codigo}?',
        'Quem já entrou com ele continua contando nas adesões. Para só parar de aceitar, desative.',
        ok: 'Apagar')) {
      return;
    }
    await Indicacoes.apagar(i.codigo);
    _recarregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Códigos de indicação')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Novo código'),
      ),
      body: FutureBuilder<List<(Indicacao, int)>>(
        future: _lista,
        builder: (c, s) {
          if (s.hasError) return Vazio('Não foi possível abrir os códigos: ${s.error}');
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final l = s.data!;
          if (l.isEmpty) return const Vazio('Nenhum código ainda. Toque em "Novo código".');
          final total = l.fold<int>(0, (t, e) => t + e.$2);
          return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('$total adesão(ões) com código. Desconto de $descontoIndicacao% na assinatura.',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final (i, n) in l)
              ListTile(
                leading: Icon(Icons.card_giftcard_outlined, color: i.ativo ? Cores.oliva : Colors.grey),
                title: Text(i.codigo, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([i.nome, i.tipoNome, if (!i.ativo) 'desativado'].where((t) => t.isNotEmpty).join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('$n', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  IconButton(
                    tooltip: 'Apagar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _apagar(i),
                  ),
                ]),
                onTap: () => _editar(i),
              ),
          ]);
        },
      ),
    );
  }
}
