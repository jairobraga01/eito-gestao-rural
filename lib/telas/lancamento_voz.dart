import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/voz.dart';
import '../dispositivos/voz_stub.dart' if (dart.library.js_interop) '../dispositivos/voz_web.dart';
import '../tema.dart';
import '../util/util.dart';

/// Fala o serviço e o app lança: peso, vacina, diagnóstico, inseminação, parto,
/// morte, escore, piquete, leite, chuva, despesa e entrada no estoque.
class LancamentoVozPage extends StatefulWidget {
  const LancamentoVozPage({super.key});

  @override
  State<LancamentoVozPage> createState() => _LancamentoVozPageState();
}

class _LancamentoVozPageState extends State<LancamentoVozPage> {
  final frase = TextEditingController();
  String data = hojeIso();
  bool ouvindo = false;
  bool automatico = false;
  String? erro;
  ComandoVoz? comando;
  final feitos = <String>[];

  @override
  void dispose() {
    frase.dispose();
    super.dispose();
  }

  void _entender() {
    final nomes = [for (final i in Db.registros('insumos')) if (i['propriedade_id'] == Db.pid) txt(i['nome'])];
    setState(() {
      comando = frase.text.trim().isEmpty ? null : interpretarVoz(frase.text, insumos: nomes);
      erro = frase.text.trim().isNotEmpty && comando == null ? 'Não entendi. Veja os exemplos abaixo.' : null;
    });
  }

  Future<void> _ouvir() async {
    setState(() {
      ouvindo = true;
      erro = null;
    });
    final (texto, falha) = await ouvirFrase();
    if (!mounted) return;
    setState(() => ouvindo = false);
    if (texto == null) {
      setState(() => erro = falha);
      return;
    }
    frase.text = texto;
    _entender();
    if (automatico && comando != null) await _lancar();
  }

  Future<void> _lancar() async {
    final c = comando;
    if (c == null) return;
    try {
      final feito = await executarVoz(c, data: data);
      if (!mounted) return;
      setState(() {
        feitos.insert(0, feito);
        frase.clear();
        comando = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lançado: $feito')));
    } on StateError catch (e) {
      if (mounted) setState(() => erro = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Lançar por voz')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DateField(label: 'Data do serviço', value: data, obrigatorio: true, onChanged: (v) => setState(() => data = v!)),
        const SizedBox(height: 16),
        Center(
          child: SizedBox(
            width: 140,
            height: 140,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: ouvindo ? Cores.alerta : Cores.oliva,
              ),
              onPressed: !vozDisponivel || ouvindo ? null : _ouvir,
              child: Icon(ouvindo ? Icons.hearing : Icons.mic, size: 64),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          !vozDisponivel
              ? 'Este navegador não reconhece voz. Use o Chrome no Android ou o Safari no iPhone, ou digite a frase abaixo.'
              : ouvindo
                  ? 'Ouvindo… fale agora.'
                  : 'Toque no microfone e fale.',
          textAlign: TextAlign.center,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Lançar direto, sem confirmar'),
          value: automatico,
          onChanged: (v) => setState(() => automatico = v),
        ),
        TextField(
          controller: frase,
          decoration: InputDecoration(
            labelText: 'Frase',
            suffixIcon: IconButton(icon: const Icon(Icons.check), onPressed: _entender),
          ),
          onSubmitted: (_) => _entender(),
        ),
        if (erro != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(erro!, style: const TextStyle(color: Cores.alerta))),
        if (comando != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: Text(comando!.descricao, style: tema.titleMedium),
              subtitle: Text('em ${br(data)}'),
            ),
          ),
          FilledButton.icon(icon: const Icon(Icons.done), label: const Text('LANÇAR'), onPressed: _lancar),
        ],
        if (feitos.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Lançados agora (${feitos.length})', style: tema.titleSmall),
          for (final f in feitos)
            ListTile(dense: true, leading: const Icon(Icons.check_circle, color: Cores.sucesso), title: Text(f)),
        ],
        const SizedBox(height: 16),
        Text('Exemplos', style: tema.titleSmall),
        const Text(exemplosVoz),
      ]),
    );
  }
}

const exemplosVoz = '• "Brinco 123 peso 450"\n'
    '• "Brinco 45 vacina aftosa" ou "brinco 45 vermífugo ivermectina"\n'
    '• "Brinco 45 prenhe" ou "brinco 45 vazia"\n'
    '• "Vaca 12 inseminada touro Bravo" ou "vaca 12 monta"\n'
    '• "Vaca 12 pariu macho brinco 300"\n'
    '• "Brinco 45 morreu picada de cobra"\n'
    '• "Brinco 45 escore 3 e meio"\n'
    '• "Brinco 45 piquete 3"\n'
    '• "Vaca 12 leite 18 litros"\n'
    '• "Chuva 25 milímetros"\n'
    '• "Despesa 350 reais diesel"\n'
    '• "Entrada 20 sal mineral" (no estoque)';
