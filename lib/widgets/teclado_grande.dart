import 'package:flutter/material.dart';

import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/formato.dart';

/// Teclado numérico de tela com teclas enormes. Evita o teclado pequeno do
/// celular e os erros de digitação no manejo.
class TecladoGrande extends StatelessWidget {
  const TecladoGrande({super.key, required this.valor, this.decimal = true, this.maxDigitos = 15});

  final ValueNotifier<String> valor;
  final bool decimal;
  final int maxDigitos;

  void _tecla(String t) {
    final v = valor.value;
    if (t == 'apagar') {
      if (v.isNotEmpty) valor.value = v.substring(0, v.length - 1);
      return;
    }
    if (t == ',') {
      if (!decimal || v.contains(',')) return;
      valor.value = v.isEmpty ? '0,' : '$v,';
      return;
    }
    if (v.replaceAll(',', '').length >= maxDigitos) return;
    valor.value = v + t;
  }

  @override
  Widget build(BuildContext context) {
    const teclas = ['1', '2', '3', '4', '5', '6', '7', '8', '9', ',', '0', 'apagar'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        for (final t in teclas)
          if (t == ',' && !decimal)
            const SizedBox.shrink()
          else
            _Tecla(texto: t, aoTocar: () => _tecla(t)),
      ],
    );
  }
}

class _Tecla extends StatelessWidget {
  const _Tecla({required this.texto, required this.aoTocar});
  final String texto;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final apagar = texto == 'apagar';
    return Material(
      color: apagar ? Cores.olivaClaro : Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: aoTocar,
        child: Center(
          child: apagar
              ? const Icon(Icons.backspace_outlined, size: 34, color: Colors.white, semanticLabel: 'Apagar')
              : Text(texto,
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Cores.tinta)),
        ),
      ),
    );
  }
}

/// Visor grande do número que está sendo digitado ou lido.
class VisorNumero extends StatelessWidget {
  const VisorNumero({super.key, required this.valor, this.sufixo});
  final ValueNotifier<String> valor;
  final String? sufixo;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: valor,
      builder: (context, v, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Cores.oliva, width: 3),
        ),
        child: Text(
          v.isEmpty ? '—' : (sufixo == null ? v : '$v $sufixo'),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Cores.tinta),
        ),
      ),
    );
  }
}

/// Abre um teclado grande em tela cheia e devolve o texto confirmado.
/// Se o bastão ou a balança mandarem uma leitura, ela preenche o visor.
Future<String?> pedirNumero(BuildContext context,
    {required String titulo, bool decimal = false, String? sufixo, String inicial = ''}) {
  return Navigator.of(context).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _TelaNumero(titulo: titulo, decimal: decimal, sufixo: sufixo, inicial: inicial),
  ));
}

Future<double?> pedirPeso(BuildContext context, {String titulo = 'Peso'}) async {
  final s = await pedirNumero(context, titulo: titulo, decimal: true, sufixo: 'kg');
  return s == null ? null : lerNumero(s);
}

class _TelaNumero extends StatefulWidget {
  const _TelaNumero({required this.titulo, required this.decimal, required this.inicial, this.sufixo});
  final String titulo;
  final bool decimal;
  final String inicial;
  final String? sufixo;

  @override
  State<_TelaNumero> createState() => _TelaNumeroState();
}

class _TelaNumeroState extends State<_TelaNumero> {
  late final ValueNotifier<String> _valor = ValueNotifier(widget.inicial);
  VoidCallback? _cancelar;

  @override
  void initState() {
    super.initState();
    _cancelar = LeitorTeclado.instancia.assinar((leitura) {
      _valor.value = widget.decimal ? (leituraParaVisor(leitura) ?? _valor.value) : leitura;
    });
  }

  @override
  void dispose() {
    _cancelar?.call();
    _valor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            VisorNumero(valor: _valor, sufixo: widget.sufixo),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: TecladoGrande(valor: _valor, decimal: widget.decimal),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Cores.laranja, foregroundColor: Cores.azul, minimumSize: const Size.fromHeight(72)),
              onPressed: () {
                if (_valor.value.isEmpty) return;
                Navigator.pop(context, _valor.value);
              },
              icon: const Icon(Icons.check, size: 32),
              label: const Text('CONFIRMAR'),
            ),
          ]),
        ),
      ),
    );
  }
}
