import 'package:flutter/material.dart';

import '../tema.dart';

/// Botão grande do Modo Curral: alvo de toque enorme, ícone e texto fortes,
/// para usar com luva, dedo sujo ou debaixo de sol.
class BotaoCurral extends StatelessWidget {
  const BotaoCurral({
    super.key,
    required this.icone,
    required this.rotulo,
    required this.aoTocar,
    this.cor = Cores.oliva,
    this.detalhe,
  });

  final IconData icone;
  final String rotulo;
  final String? detalhe;
  final Color cor;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: detalhe == null ? rotulo : '$rotulo, $detalhe',
      child: Material(
        color: cor,
        elevation: 2,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aoTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 132),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icone, size: 52, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(rotulo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 20, height: 1.1, fontWeight: FontWeight.w800)),
                  if (detalhe != null) ...[
                    const SizedBox(height: 4),
                    Text(detalhe!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
