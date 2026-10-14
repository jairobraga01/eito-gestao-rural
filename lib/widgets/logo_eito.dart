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
  const TelaCarregando({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Cores.olivaEscuro,
        body: Center(child: LogoEito(tamanho: 120)),
      );
}
