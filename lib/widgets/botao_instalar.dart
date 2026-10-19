import 'package:flutter/material.dart';

import '../dispositivos/instalar_stub.dart' if (dart.library.js_interop) '../dispositivos/instalar_web.dart';
import '../tema.dart';

/// "Instalar app": põe o ícone do Eito na tela do celular. Só aparece quando dá para instalar.
class BotaoInstalar extends StatefulWidget {
  const BotaoInstalar({super.key, this.claro = false});

  /// Texto claro, para fundos escuros (tela de login).
  final bool claro;

  @override
  State<BotaoInstalar> createState() => _BotaoInstalarState();
}

class _BotaoInstalarState extends State<BotaoInstalar> {
  @override
  void initState() {
    super.initState();
    aoMudarInstalacao(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _tocar() async {
    if (instalacaoIos) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Instalar no iPhone'),
          content: const Text('1. Toque no botão Compartilhar (o quadrado com a seta para cima), na barra do Safari.\n\n'
              '2. Escolha "Adicionar à Tela de Início".\n\n'
              '3. Toque em "Adicionar". O ícone do Eito aparece na tela do celular.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Entendi'))],
        ),
      );
      return;
    }
    await instalarApp();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!instalacaoDisponivel) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: widget.claro ? Cores.laranja : Cores.olivaEscuro,
          foregroundColor: widget.claro ? Cores.azul : Colors.white,
        ),
        onPressed: _tocar,
        icon: const Icon(Icons.install_mobile),
        label: const Text('Instalar app'),
      ),
    );
  }
}
