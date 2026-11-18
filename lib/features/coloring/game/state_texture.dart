import 'dart:ui' as ui;

import '../model/fill_state.dart';
import '../model/picture_meta.dart';

/// Builds the fill-state texture that `shaders/coloring.frag` samples
/// (spec §3): opaque, (N + 1) × 2, one column per region id (column 0 is
/// unused).
///
/// - Row 0: the display color, white when the region is unfilled.
/// - Row 1: R = palette index, G = 255 when the region holds its correct
///   palette color (else 0), B = 0.
///
/// Alpha is 255 everywhere, so premultiplication cannot change a value.
/// Built synchronously with [ui.Picture.toImageSync], so the caller can
/// install it in the same frame as the change. The caller owns the result
/// and must dispose it.
ui.Image buildStateTexture(FillState state, PictureMeta meta) {
  final width = meta.regionCount + 1;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()
    ..blendMode = ui.BlendMode.src
    ..isAntiAlias = false;

  paint.color = const ui.Color(0xFFFFFFFF);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), paint);
  paint.color = const ui.Color(0xFF000000);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 1, 1, 1), paint);

  for (var id = 1; id < width; id++) {
    final x = id.toDouble();
    final color = state.colorOf(id);
    paint.color = ui.Color(color == 0 ? 0xFFFFFFFF : color);
    canvas.drawRect(ui.Rect.fromLTWH(x, 0, 1, 1), paint);

    final paletteIndex = meta.region(id).paletteIndex;
    final correct = state.isCorrect(id, meta) ? 0xFF : 0;
    paint.color = ui.Color(0xFF000000 | paletteIndex << 16 | correct << 8);
    canvas.drawRect(ui.Rect.fromLTWH(x, 1, 1, 1), paint);
  }

  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(width, 2);
  } finally {
    picture.dispose();
  }
}
