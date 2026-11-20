import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../../app/book_palette.dart';
import '../model/label_layout.dart';
import '../model/mode_rules.dart' as rules;
import 'coloring_game.dart';

/// Region numbers (numbers mode only). Draws only regions whose label is
/// big enough on screen ([labelVisible]), lies inside the visible part of
/// the image, and still shows a number ([rules.showsNumber]). At max zoom
/// size no longer matters, so a region too small for the zoom cap still
/// gets its number. Painters are
/// cached per (number, whole-dp font size), so a frame allocates nothing
/// once the cache is warm. The rejected region's label wiggles.
class LabelsComponent extends Component with HasGameReference<ColoringGame> {
  final Map<int, TextPainter> _painters = {};

  /// Labels drawn in the last frame.
  int drawnCount = 0;

  static const _textStyle = TextStyle(
    fontFamily: 'Nunito',
    fontWeight: FontWeight.w700,
    color: BookPalette.textMuted,
  );

  TextPainter _painter(int number, int fontSize) {
    return _painters.putIfAbsent(
      number << 8 | fontSize,
      () => TextPainter(
        text: TextSpan(
          text: '$number',
          style: _textStyle.copyWith(fontSize: fontSize.toDouble()),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  @override
  void render(Canvas canvas) {
    drawnCount = 0;
    final g = game;
    final v = g.viewport;
    if (!g.labelsEnabled || v == null || g.isDisposed) return;
    final meta = g.meta;
    final fill = g.fill;
    final scale = v.scale;
    final pxPerDp = v.imagePxPerDp;
    final origin = v.origin;
    final ox = origin.x;
    final oy = origin.y;
    // Visible part of the image, in image px.
    final left = -ox / scale;
    final top = -oy / scale;
    final right = (v.canvasWidth - ox) / scale;
    final bottom = (v.canvasHeight - oy) / scale;
    final flashId = g.flash.regionId;
    final wiggle = g.reducedMotion ? 0.0 : g.flash.wiggleDp;
    final anySize = v.atMaxZoom;

    final regions = meta.regions;
    for (var i = 0; i < regions.length; i++) {
      final r = regions[i];
      final radius = r.labelRadius;
      if (!(anySize || labelVisible(radius, pxPerDp)) ||
          r.labelX + radius < left ||
          r.labelX - radius > right ||
          r.labelY + radius < top ||
          r.labelY - radius > bottom ||
          !rules.showsNumber(fill, meta, r.id)) {
        continue;
      }
      final painter = _painter(
        r.number,
        labelFontSize(radius, pxPerDp).round(),
      );
      var x = ox + r.labelX * scale - painter.width / 2;
      if (r.id == flashId) x += wiggle;
      final y = oy + r.labelY * scale - painter.height / 2;
      canvas
        ..save()
        ..translate(x, y);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
      drawnCount++;
    }
  }

  /// Releases the cached painters; called by the game on removal.
  void disposeCache() {
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
  }
}
