import 'dart:typed_data';

import 'flood_fill.dart';

/// Triangle positions covering [mask] for `Vertices.raw(VertexMode.triangles,
/// positions)`: two triangles (12 floats) per run, each run the pixel rect
/// `(x0, y)`–`(x1, y + 1)` in canvas pixels.
Float32List fillTriangles(FillMask mask) {
  final runs = mask.runs;
  final positions = Float32List(mask.runCount * 12);
  var o = 0;
  for (var i = 0; i < runs.length; i += 3) {
    final y0 = runs[i].toDouble();
    final x0 = runs[i + 1].toDouble();
    final x1 = runs[i + 2].toDouble();
    final y1 = y0 + 1;
    positions
      ..[o] = x0
      ..[o + 1] = y0
      ..[o + 2] = x1
      ..[o + 3] = y0
      ..[o + 4] = x1
      ..[o + 5] = y1
      ..[o + 6] = x0
      ..[o + 7] = y0
      ..[o + 8] = x1
      ..[o + 9] = y1
      ..[o + 10] = x0
      ..[o + 11] = y1;
    o += 12;
  }
  return positions;
}
