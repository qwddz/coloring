import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coloring/features/drawing/model/brush_size.dart';
import 'package:coloring/features/drawing/model/dab_generator.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/drawing/model/stroke.dart';
import 'package:coloring/features/drawing/model/symmetry.dart';

/// Premultiplied RGBA bytes of [image] (equal to straight ones where
/// opaque, as on the drawing canvas).
Future<Uint8List> pixelsOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

/// Renders [draw] onto a [width] × [height] canvas filled with
/// [background] and returns its RGBA bytes (see [pixelsOf]).
Future<Uint8List> render(
  int width,
  int height,
  void Function(ui.Canvas canvas) draw, {
  int background = drawingWhite,
}) async {
  final recorder = ui.PictureRecorder();
  final rect = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final canvas = ui.Canvas(recorder, rect)
    ..drawRect(rect, ui.Paint()..color = ui.Color(background));
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    return await pixelsOf(image);
  } finally {
    image.dispose();
  }
}

/// ARGB of pixel (x, y) in RGBA [rgba] of [width].
int argbAt(Uint8List rgba, int width, int x, int y) {
  final o = (y * width + x) * 4;
  return rgba[o + 3] << 24 | rgba[o] << 16 | rgba[o + 1] << 8 | rgba[o + 2];
}

int red(int argb) => argb >> 16 & 0xFF;
int green(int argb) => argb >> 8 & 0xFF;
int blue(int argb) => argb & 0xFF;

/// Sum of the RGB channels.
int brightness(int argb) => red(argb) + green(argb) + blue(argb);

/// A stroke input along [points] (canvas pixels, pressure 1).
StrokeInput strokeInput(
  DrawingTool tool,
  List<(double, double)> points, {
  int color = 0xFF1E88E5,
  BrushSize size = BrushSize.medium,
  int seed = 7,
  SymmetryMode symmetry = SymmetryMode.off,
}) => StrokeInput(
  tool: tool,
  color: color,
  size: size,
  seed: seed,
  symmetry: symmetry,
  points: [
    for (var i = 0; i < points.length; i++)
      StrokePoint(points[i].$1, points[i].$2, tMillis: i * 16),
  ],
);

/// The dabs of a stroke input along [points].
List<Dab> dabsOf(
  DrawingTool tool,
  List<(double, double)> points, {
  int color = 0xFF1E88E5,
  BrushSize size = BrushSize.medium,
  int seed = 7,
}) => DabGenerator.generate(
  strokeInput(tool, points, color: color, size: size, seed: seed),
);
