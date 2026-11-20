import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/passe_partout.dart';
import '../../l10n/app_localizations.dart';
import 'drawing_route.dart';

/// The «Рисовалка» tile, first on the home grid (spec §14.1): a crayon
/// doodle painted in code in a passe-partout. Opens the latest drawing.
/// Never locked.
class DrawingTile extends StatelessWidget {
  const DrawingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PassePartout(
      tiltDegrees: -1.2,
      onTap: () => context.push(drawRoute()),
      caption: Row(
        children: [
          const Icon(Icons.brush_rounded, size: 20, color: BookPalette.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.drawingTileTitle,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: BookPalette.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      child: const AspectRatio(
        aspectRatio: 4 / 3,
        child: CustomPaint(painter: DoodlePainter()),
      ),
    );
  }
}

/// A fixed crayon doodle on paper: a rainbow arc, a sun, a star and a
/// heart. Deterministic, scaled to the size.
class DoodlePainter extends CustomPainter {
  const DoodlePainter();

  static const _rainbow = [
    Color(0xFFE5554F),
    Color(0xFFF2A03D),
    Color(0xFFF4D35E),
    Color(0xFF6BBF59),
    Color(0xFF4A86C5),
    Color(0xFF8E6CC4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = BookPalette.paper);
    final unit = size.width / 100;
    Paint crayon(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Rainbow arc over the lower middle.
    final center = Offset(50 * unit, 70 * unit);
    for (var i = 0; i < _rainbow.length; i++) {
      final radius = (34 - i * 3.6) * unit;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi * 1.05,
        math.pi * 0.9,
        false,
        crayon(_rainbow[i], 3.2),
      );
    }

    // Sun in the top left corner.
    final sun = Offset(16 * unit, 16 * unit);
    canvas.drawCircle(sun, 7 * unit, Paint()..color = const Color(0xFFF4C542));
    final rays = crayon(const Color(0xFFF2A03D), 1.6);
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        sun + direction * 9.5 * unit,
        sun + direction * 13 * unit,
        rays,
      );
    }

    // Star top right.
    final star = Path();
    final starCenter = Offset(82 * unit, 18 * unit);
    for (var i = 0; i < 10; i++) {
      final radius = (i.isEven ? 10 : 4.4) * unit;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point =
          starCenter + Offset(math.cos(angle), math.sin(angle)) * radius;
      i == 0
          ? star.moveTo(point.dx, point.dy)
          : star.lineTo(point.dx, point.dy);
    }
    star.close();
    canvas
      ..drawPath(star, Paint()..color = const Color(0xFFF4D35E))
      ..drawPath(star, crayon(const Color(0xFFE2A33B), 1.2));

    // Heart bottom right.
    final h = Offset(84 * unit, 62 * unit);
    final s = 9 * unit;
    final heart = Path()
      ..moveTo(h.dx, h.dy + s * 0.9)
      ..cubicTo(
        h.dx - s * 1.4,
        h.dy,
        h.dx - s * 0.7,
        h.dy - s * 0.9,
        h.dx,
        h.dy - s * 0.3,
      )
      ..cubicTo(
        h.dx + s * 0.7,
        h.dy - s * 0.9,
        h.dx + s * 1.4,
        h.dy,
        h.dx,
        h.dy + s * 0.9,
      )
      ..close();
    canvas.drawPath(heart, Paint()..color = const Color(0xFFE9798F));

    // A loose scribble along the bottom.
    final scribble = Path()..moveTo(8 * unit, 66 * unit);
    for (var i = 0; i < 5; i++) {
      final x = 8 + i * 6.0;
      scribble.quadraticBezierTo(
        (x + 3) * unit,
        (i.isEven ? 58 : 72) * unit,
        (x + 6) * unit,
        66 * unit,
      );
    }
    canvas.drawPath(scribble, crayon(const Color(0xFF4A86C5), 1.8));
  }

  @override
  bool shouldRepaint(DoodlePainter oldDelegate) => false;
}
