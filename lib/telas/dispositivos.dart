import 'package:flutter/material.dart';

import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';

/// Como conectar o bastão de brinco eletrônico e a balança, e um teste rápido.
class TelaDispositivos extends StatefulWidget {
  const TelaDispositivos({super.key});

  @override
  State<TelaDispositivos> createState() => _TelaDispositivosState();
}

class _TelaDispositivosState extends State<TelaDispositivos> {
  final List<String> _leituras = [];
  VoidCallback? _cancelar;

  @override
  void initState() {
    super.initState();
    // Enquanto esta tela estiver aberta, as leituras vêm para cá (teste).
    _cancelar = LeitorTeclado.instancia.assinar((t) => setState(() => _leituras.insert(0, t)));
  }

  @override
  void dispose() {
    _cancelar?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const corpo = TextStyle(fontSize: 18, height: 1.35);
    Widget passo(String n, String texto) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
                radius: 16,
                backgroundColor: Cores.azul,
                child: Text(n, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            const SizedBox(width: 12),
            Expanded(child: Text(texto, style: corpo)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Bastão e balança')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Conectar por Bluetooth', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        passo('1', 'No bastão ou no indicador da balança, ative o modo "teclado" (HID / Keyboard). '
            'O nome muda conforme a marca; está no manual do aparelho.'),
        passo('2', 'No celular ou computador, abra Ajustes › Bluetooth e pareie o aparelho como um teclado.'),
        passo('3', 'Volte ao Eito e faça uma leitura. Ela aparece logo abaixo.'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: const Text(
            'Por que modo teclado? É o único jeito que funciona no iPhone pelo navegador, '
            'e também funciona no Android e no computador, sem instalar nada. '
            'Com o aparelho pareado, o teclado da tela do iPhone some; isso é normal.',
            style: TextStyle(fontSize: 16, height: 1.35),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Teste de leitura', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_leituras.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Cores.olivaEscuro, borderRadius: BorderRadius.circular(16)),
            child: const Column(children: [
              Icon(Icons.contactless_outlined, size: 64, color: Cores.laranja),
              SizedBox(height: 8),
              Text('Faça uma leitura com o bastão ou a balança.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 20)),
            ]),
          )
        else
          for (final l in _leituras.take(10))
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Cores.sucesso, size: 30),
                title: Text(l, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ),
      ]),
    );
  }
}
