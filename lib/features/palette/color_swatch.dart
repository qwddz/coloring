import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/book_palette.dart';
import '../../l10n/app_localizations.dart';
import '../coloring/model/fill_state.dart';

/// One palette circle. The hit area is 48 x 48 dp. [number] and [progress]
/// are set only in the by-numbers mode: a progress ring around the circle,
/// or a check once [PaletteProgress.done].
class PaletteSwatch extends StatelessWidget {
  const PaletteSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.number,
    this.progress,
    super.key,
  });

  /// Opaque ARGB.
  final int color;
  final bool selected;
  final VoidCallback onTap;

  /// Shown on the circle when set (palette index + 1).
  final int? number;
  final PaletteProgress? progress;

  @override
  Widget build(BuildContext context) {
    final fill = Color(color);
    final done = progress?.done ?? false;
    final onFill = fill.computeLuminance() > 0.5
        ? BookPalette.text
        : Colors.white;
    final label = number == null
        ? null
        : AppLocalizations.of(context).paletteColorNumber(number!);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: label != null,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: CustomPaint(
            painter: _SwatchPainter(
              color: fill,
              selected: selected,
              progress: progress,
            ),
            child: Center(
              child: done
                  ? Icon(Icons.check, size: 22, color: onFill)
                  : number == null
                  ? null
                  : Text(
                      '$number',
                      style: TextStyle(
                        color: onFill,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter({
    required this.color,
    required this.selected,
    required this.progress,
  });

  final Color color;
  final bool selected;
  final PaletteProgress? progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, 17, Paint()..color = color);
    canvas.drawCircle(
      center,
      17,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = BookPalette.outline,
    );
    final p = progress;
    if (p != null && p.total > 0 && p.correct > 0) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = BookPalette.star;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 20),
        -math.pi / 2,
        2 * math.pi * p.correct / p.total,
        false,
        ring,
      );
    }
    if (selected) {
      canvas.drawCircle(
        center,
        22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = BookPalette.text,
      );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color ||
      old.selected != selected ||
      old.progress != progress;
}
