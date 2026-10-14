import 'package:flutter/material.dart';

import '../tema.dart';

/// Foto do gado com uma camada verde oliva por cima, para o texto branco
/// continuar legível. Para trocar a foto, substitua o arquivo em
/// assets/imagens/fundo_gado.jpg (mantenha o nome).
class FundoFoto extends StatelessWidget {
  const FundoFoto({
    super.key,
    this.child,
    this.escurecer = 0.55,
    this.alinhamento = const Alignment(0.35, 0),
  });

  final Widget? child;

  /// 0 = foto pura, 1 = só o verde.
  final double escurecer;

  /// Onde focar a foto ao recortar. Na foto atual os animais estão
  /// à direita, então o padrão puxa um pouco para lá.
  final Alignment alinhamento;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Image.asset(
        'assets/imagens/fundo_gado.jpg',
        fit: BoxFit.cover,
        alignment: alinhamento,
        // Se a foto faltar, fica só o verde, sem quebrar a tela.
        errorBuilder: (_, __, ___) => const ColoredBox(color: Cores.olivaEscuro),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Cores.olivaEscuro.withValues(alpha: escurecer * 0.75),
              Cores.olivaEscuro.withValues(alpha: (escurecer + 0.25).clamp(0.0, 1.0)),
            ],
          ),
        ),
      ),
      if (child != null) child!,
    ]);
  }
}
