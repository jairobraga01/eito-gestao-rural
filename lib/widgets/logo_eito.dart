import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../marca.dart';
import '../tema.dart';

/// Ícone "E": mourão + tábuas de porteira que crescem como um gráfico de ganho de peso.
class LogoEito extends StatelessWidget {
  const LogoEito({super.key, this.tamanho = 96});
  final double tamanho;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/logo/eito_icone.svg',
        width: tamanho,
        height: tamanho,
        semanticsLabel: Marca.nome,
      );
}

class TelaCarregando extends StatelessWidget {
  const TelaCarregando({super.key, this.mensagem});
  final String? mensagem;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Cores.olivaEscuro,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const LogoEito(tamanho: 120),
            if (mensagem != null) ...[
              const SizedBox(height: 20),
              const SizedBox(
                  width: 32, height: 32, child: CircularProgressIndicator(color: Cores.laranja, strokeWidth: 3)),
              const SizedBox(height: 14),
              Text(mensagem!, style: const TextStyle(color: Colors.white70, fontSize: 17)),
            ],
          ]),
        ),
      );
}
