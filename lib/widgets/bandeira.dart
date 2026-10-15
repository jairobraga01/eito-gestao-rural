import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bandeira do Brasil desenhada pelo app (não depende de imagem nem de internet).
/// Proporção oficial 20 x 14.
class BandeiraBrasil extends StatelessWidget {
  const BandeiraBrasil({super.key, this.largura = 34});
  final double largura;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Bandeira do Brasil',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: CustomPaint(size: Size(largura, largura * 0.7), painter: _PintorBandeira()),
        ),
      );
}

class _PintorBandeira extends CustomPainter {
  static const _verde = Color(0xFF009C3B);
  static const _amarelo = Color(0xFFFFDF00);
  static const _azul = Color(0xFF002776);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    canvas.drawRect(Offset.zero & s, Paint()..color = _verde);

    // Losango amarelo (margem de 1,7 em 20 nas laterais e em 14 no alto e embaixo).
    final mx = w * 1.7 / 20, my = h * 1.7 / 14;
    final losango = Path()
      ..moveTo(w / 2, my)
      ..lineTo(w - mx, h / 2)
      ..lineTo(w / 2, h - my)
      ..lineTo(mx, h / 2)
      ..close();
    canvas.drawPath(losango, Paint()..color = _amarelo);

    // Círculo azul (raio 3,5 em 20).
    final centro = Offset(w / 2, h / 2);
    final raio = w * 3.5 / 20;
    canvas.drawCircle(centro, raio, Paint()..color = _azul);

    // Faixa branca curva atravessando o círculo.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: centro, radius: raio)));
    final faixa = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, raio * 0.18);
    final arco = Rect.fromCircle(center: Offset(centro.dx - raio * 0.4, centro.dy + raio * 2.1), radius: raio * 2.4);
    canvas.drawArc(arco, -math.pi * 0.85, math.pi * 0.7, false, faixa);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
