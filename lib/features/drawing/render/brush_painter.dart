import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/drawing_tool.dart';
import '../model/stroke.dart';
import 'brush_sprites.dart';

/// Where [composeStroke] draws a stroke (spec §6.1–6.2).
enum StrokeStage {
  /// Commit and replay: the bounded layer with the tool's opacity and the
  /// watercolor bleed blur.
  commit,

  /// The live preview: the same layer, no blur (the bleed appears on lift).
  live,

  /// Baking live dabs into the display-only `bakedStroke` image: the dabs
  /// alone, pre-opacity, no layer and no blur.
  bake,
}

/// Blur sigma of the watercolor bleed for a stroke of radius [radius].
double bleedSigma(double radius) => 0.25 * radius;

/// The area [dabs] paint, rounded out to whole pixels; with [bleed] grown
/// by the blur reach (3 σ of the largest dab). Empty dabs give
/// [ui.Rect.zero].
ui.Rect strokeBounds(List<Dab> dabs, {bool bleed = false}) {
  if (dabs.isEmpty) return ui.Rect.zero;
  var left = double.infinity, top = double.infinity;
  var right = double.negativeInfinity, bottom = double.negativeInfinity;
  var maxRadius = 0.0;
  for (final d in dabs) {
    // Sprites and stamp outlines stay within the dab radius; the sprite rim
    // and bilinear sampling add up to 2 texels, antialiasing 1 px.
    final r = d.radius * (1 + 2 / spriteShapeRadius) + 1;
    left = min(left, d.x - r);
    top = min(top, d.y - r);
    right = max(right, d.x + r);
    bottom = max(bottom, d.y + r);
    maxRadius = max(maxRadius, d.radius);
  }
  final margin = bleed ? (3 * bleedSigma(maxRadius)).ceilToDouble() : 0.0;
  return ui.Rect.fromLTRB(
    (left - margin).floorToDouble(),
    (top - margin).floorToDouble(),
    (right + margin).ceilToDouble(),
    (bottom + margin).ceilToDouble(),
  );
}

/// Draws [dabs] of a [spec] stroke onto [canvas]: the one composition
/// function for the live preview, commit and replay (spec §6.1), so commit
/// and replay issue identical draw commands.
///
/// When the tool has a layer opacity below 1 or bleeds (and [stage] is not
/// [StrokeStage.bake]), the dabs go into a layer bounded by [bounds] (see
/// [strokeBounds]) that is composited with that opacity and, at
/// [StrokeStage.commit], the bleed blur. [baked], drawn at [bakedAt] before
/// the dabs inside that layer, is the pre-opacity image of earlier live
/// dabs (display only). Each pass is one `drawAtlas` call; stamps are
/// filled outlines.
void composeStroke(
  ui.Canvas canvas,
  List<Dab> dabs,
  BrushSpec spec,
  BrushSprites sprites, {
  required ui.Rect bounds,
  StrokeStage stage = StrokeStage.commit,
  ui.Image? baked,
  ui.Offset bakedAt = ui.Offset.zero,
}) {
  final blur = spec.bleed && stage == StrokeStage.commit;
  final layer = stage != StrokeStage.bake && (spec.layerOpacity < 1 || blur);
  if (layer) {
    final paint = ui.Paint()
      ..color = ui.Color.fromRGBO(0, 0, 0, spec.layerOpacity);
    if (blur) {
      var maxRadius = 0.0;
      for (final d in dabs) {
        maxRadius = max(maxRadius, d.radius);
      }
      final sigma = bleedSigma(maxRadius);
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: ui.TileMode.decal,
      );
    }
    canvas.saveLayer(bounds, paint);
  }
  if (baked != null) canvas.drawImage(baked, bakedAt, ui.Paint());
  if (spec.kind == BrushKind.stamps) {
    _drawStamps(canvas, dabs, spec);
  } else {
    for (var pass = 0; pass < spec.passes.length; pass++) {
      _drawPass(canvas, dabs, spec.passes[pass], pass, sprites);
    }
  }
  if (layer) canvas.restore();
}

/// ARGB [color] with its alpha multiplied by [alpha].
int dabColor(int color, double alpha) {
  final a = ((color >>> 24) * alpha).round().clamp(0, 255);
  return a << 24 | (color & 0xFFFFFF);
}

void _drawPass(
  ui.Canvas canvas,
  List<Dab> dabs,
  BrushPass pass,
  int index,
  BrushSprites sprites,
) {
  var n = 0;
  for (final d in dabs) {
    if (d.pass == index) n++;
  }
  if (n == 0) return;
  final transforms = Float32List(n * 4);
  final rects = Float32List(n * 4);
  final colors = Int32List(n);
  const half = spriteCellSize / 2;
  var i = 0;
  for (final d in dabs) {
    if (d.pass != index) continue;
    final scale = d.radius / spriteShapeRadius;
    final scos = cos(d.rotation) * scale;
    final ssin = sin(d.rotation) * scale;
    final o = i * 4;
    // RSTransform with the cell center as the anchor.
    transforms
      ..[o] = scos
      ..[o + 1] = ssin
      ..[o + 2] = d.x - scos * half + ssin * half
      ..[o + 3] = d.y - ssin * half - scos * half;
    final cell = sprites.cell(pass.sprite, d.variant);
    rects
      ..[o] = cell.left
      ..[o + 1] = cell.top
      ..[o + 2] = cell.right
      ..[o + 3] = cell.bottom;
    colors[i] = dabColor(d.color, d.alpha);
    i++;
  }
  canvas.drawRawAtlas(
    sprites.atlas,
    transforms,
    rects,
    colors,
    ui.BlendMode.modulate,
    null,
    ui.Paint()..filterQuality = ui.FilterQuality.low,
  );
}

void _drawStamps(ui.Canvas canvas, List<Dab> dabs, BrushSpec spec) {
  final outline = spec.stamp?.outline;
  if (outline == null) return;
  final paint = ui.Paint()..isAntiAlias = true;
  for (final d in dabs) {
    final c = cos(d.rotation) * d.radius;
    final s = sin(d.rotation) * d.radius;
    final path = ui.Path();
    for (var i = 0; i < outline.length; i++) {
      final p = outline[i];
      final x = d.x + p.x * c - p.y * s;
      final y = d.y + p.x * s + p.y * c;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint..color = ui.Color(dabColor(d.color, d.alpha)));
  }
}
