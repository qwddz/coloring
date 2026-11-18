import 'dart:ui';

import 'package:flame/components.dart';

import '../../../app/book_palette.dart';
import 'coloring_game.dart';

/// The fills (through the game's [ColoringGame.renderer]), `lines.png` on
/// top and a thin paper border around the picture. Allocates nothing per
/// frame: the rects and paints are kept between frames.
class PictureComponent extends Component with HasGameReference<ColoringGame> {
  final Paint _linesPaint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = BookPalette.outline;
  late final Rect _linesSource = Rect.fromLTWH(
    0,
    0,
    game.linesImage.width.toDouble(),
    game.linesImage.height.toDouble(),
  );

  @override
  void render(Canvas canvas) {
    final g = game;
    final viewport = g.viewport;
    if (viewport == null || g.isDisposed) return;
    final rect = g.imageRect;
    g.renderer.paint(canvas, rect, viewport.scale, g.uniforms);
    canvas
      ..drawImageRect(g.linesImage, _linesSource, rect, _linesPaint)
      ..drawRect(rect, _borderPaint);
  }
}
