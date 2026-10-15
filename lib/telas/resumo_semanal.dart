import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/gestao.dart';
import '../util/util.dart';

/// Resumo dos últimos 7 dias, pronto para mandar pelo WhatsApp.
class ResumoSemanalPage extends StatelessWidget {
  const ResumoSemanalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resumo da semana')),
      body: AoMudar<String>(
        carregar: () async => resumoSemanal(hojeIso()),
        builder: (context, texto) => ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(texto, style: const TextStyle(fontSize: 16, height: 1.4)),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), minimumSize: const Size.fromHeight(56)),
            onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texto)}'),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.send),
            label: const Text('ENVIAR PELO WHATSAPP'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: texto));
              if (context.mounted) avisar(context, 'Resumo copiado.');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar texto'),
          ),
        ]),
      ),
    );
  }
}
