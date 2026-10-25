import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/voz.dart';
import '../tema.dart';
import '../util/util.dart';
import 'lancamento_voz.dart' show exemplosVoz;

/// Cola as mensagens do WhatsApp (o peão escreve "brinco 45 peso 450" no grupo)
/// e o app lança tudo de uma vez, depois de conferir.
class LancarWhatsAppPage extends StatefulWidget {
  const LancarWhatsAppPage({super.key});

  @override
  State<LancarWhatsAppPage> createState() => _LancarWhatsAppPageState();
}

class _LancarWhatsAppPageState extends State<LancarWhatsAppPage> {
  final conversa = TextEditingController();
  String data = hojeIso();
  List<MensagemWhatsApp> mensagens = [];
  final marcadas = <int>{};
  final resultado = <int, String>{}; // índice → "ok: ..." ou o erro
  bool lancando = false;

  @override
  void dispose() {
    conversa.dispose();
    super.dispose();
  }

  void _conferir() {
    final nomes = [for (final i in Db.registros('insumos')) if (i['propriedade_id'] == Db.pid) txt(i['nome'])];
    setState(() {
      mensagens = lerConversaWhatsApp(conversa.text, insumos: nomes);
      resultado.clear();
      marcadas
        ..clear()
        ..addAll([for (final (i, m) in mensagens.indexed) if (m.comando != null) i]);
    });
  }

  Future<void> _lancar() async {
    setState(() => lancando = true);
    var ok = 0;
    for (final i in marcadas.toList()..sort()) {
      final m = mensagens[i];
      try {
        final feito = await executarVoz(m.comando!, data: m.data ?? data);
        resultado[i] = 'ok: $feito';
        ok++;
      } on StateError catch (e) {
        resultado[i] = e.message;
      } catch (e) {
        resultado[i] = 'Não deu para lançar: $e';
      }
    }
    if (!mounted) return;
    setState(() {
      lancando = false;
      marcadas.removeWhere((i) => resultado[i]?.startsWith('ok') ?? false);
    });
    avisar(context, '$ok lançamento(s) feito(s).');
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Lançar do WhatsApp')),
      bottomNavigationBar: marcadas.isEmpty
          ? null
          : BotaoSalvar(onPressed: lancando ? null : _lancar, texto: 'Lançar ${marcadas.length}'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('No WhatsApp, segure as mensagens, toque em Copiar e cole aqui. '
            'Também serve a conversa exportada (Mais › Exportar conversa › sem mídia).'),
        const SizedBox(height: 12),
        TextField(
          controller: conversa,
          minLines: 5,
          maxLines: 12,
          decoration: const InputDecoration(labelText: 'Mensagens', alignLabelWithHint: true),
        ),
        const SizedBox(height: 12),
        DateField(
          label: 'Data (quando a mensagem não traz a data)',
          value: data,
          obrigatorio: true,
          onChanged: (v) => setState(() => data = v!),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(icon: const Icon(Icons.fact_check_outlined), label: const Text('CONFERIR'), onPressed: _conferir),
        if (mensagens.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('${mensagens.where((m) => m.comando != null).length} de ${mensagens.length} mensagem(ns) entendida(s)',
              style: tema.titleSmall),
          for (final (i, m) in mensagens.indexed) _linha(i, m),
        ],
        const SizedBox(height: 16),
        Text('O que o app entende', style: tema.titleSmall),
        const Text(exemplosVoz),
      ]),
    );
  }

  Widget _linha(int i, MensagemWhatsApp m) {
    final r = resultado[i];
    final feito = r != null && r.startsWith('ok');
    final quando = [if (m.autor != null) m.autor!, br(m.data ?? data)].join(' · ');
    if (m.comando == null) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.help_outline, color: Colors.grey),
        title: Text(m.texto, style: const TextStyle(color: Colors.grey)),
        subtitle: const Text('Não entendi esta mensagem'),
      );
    }
    return CheckboxListTile(
      value: feito || marcadas.contains(i),
      onChanged: feito || lancando ? null : (v) => setState(() => v! ? marcadas.add(i) : marcadas.remove(i)),
      title: Text(m.comando!.descricao),
      subtitle: Text(r == null ? quando : (feito ? 'Lançado' : r),
          style: TextStyle(color: r == null ? null : (feito ? Cores.sucesso : Cores.alerta))),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
