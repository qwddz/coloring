import 'dart:ui' as ui;

import '../model/dab_generator.dart';
import '../model/drawing_tool.dart';
import '../model/fill_geometry.dart';
import '../model/flood_fill.dart';
import '../model/stroke.dart';
import 'brush_painter.dart';
import 'brush_sprites.dart';

/// One undoable drawing operation. [replay] draws it on top of the canvas
/// it was first applied to; the first application and every replay call it
/// the same way, so they produce the same pixels (spec §6.3).
sealed class DrawOp {
  const DrawOp();

  void replay(ui.Canvas canvas, BrushSprites sprites);
}

/// A committed stroke. Keeps its dabs (generated once from [input]), so the
/// commit and every replay draw identical commands.
class StrokeOp extends DrawOp {
  StrokeOp(this.input, {List<Dab>? dabs})
    : dabs = List.unmodifiable(dabs ?? DabGenerator.generate(input));

  final StrokeInput input;
  final List<Dab> dabs;

  BrushSpec get spec => input.tool.spec;

  /// The commit layer bounds (with the bleed margin for watercolor).
  late final ui.Rect bounds = strokeBounds(dabs, bleed: spec.bleed);

  @override
  void replay(ui.Canvas canvas, BrushSprites sprites) {
    if (dabs.isEmpty) return;
    composeStroke(canvas, dabs, spec, sprites, bounds: bounds);
  }
}

/// A flood fill: [mask] painted opaque [color] (ARGB), pixel-exact, through
/// `drawVertices` (two triangles per run). Nothing is cached per op.
class FillOp extends DrawOp {
  const FillOp(this.mask, this.color);

  final FillMask mask;
  final int color;

  @override
  void replay(ui.Canvas canvas, BrushSprites sprites) {
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      fillTriangles(mask),
    );
    canvas.drawVertices(
      vertices,
      ui.BlendMode.src,
      ui.Paint()
        ..color = ui.Color(0xFF000000 | color)
        ..blendMode = ui.BlendMode.src
        ..isAntiAlias = false,
    );
    vertices.dispose();
  }
}

/// Clear the sheet: the whole canvas white.
class ClearOp extends DrawOp {
  const ClearOp({
    this.width = drawingCanvasWidth,
    this.height = drawingCanvasHeight,
  });

  final int width;
  final int height;

  @override
  void replay(ui.Canvas canvas, BrushSprites sprites) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()
        ..color = const ui.Color(drawingWhite)
        ..blendMode = ui.BlendMode.src,
    );
  }
}
