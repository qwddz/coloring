import 'dart:math' as math;
import 'dart:typed_data';

import 'package:coloring/features/drawing/model/fill_geometry.dart';
import 'package:coloring/features/drawing/model/flood_fill.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pixel centers covered by the triangle list, by a pure point-in-triangle
/// check. Edges count as inside: a pixel center can lie on a run's diagonal,
/// never on its outer rect.
Set<(int, int)> _rasterize(Float32List t, int width, int height) {
  final covered = <(int, int)>{};
  double cross(
    double ax,
    double ay,
    double bx,
    double by,
    double px,
    double py,
  ) => (bx - ax) * (py - ay) - (by - ay) * (px - ax);
  for (var i = 0; i < t.length; i += 6) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final px = x + 0.5, py = y + 0.5;
        final c0 = cross(t[i], t[i + 1], t[i + 2], t[i + 3], px, py);
        final c1 = cross(t[i + 2], t[i + 3], t[i + 4], t[i + 5], px, py);
        final c2 = cross(t[i + 4], t[i + 5], t[i], t[i + 1], px, py);
        if ((c0 >= 0 && c1 >= 0 && c2 >= 0) ||
            (c0 <= 0 && c1 <= 0 && c2 <= 0)) {
          covered.add((x, y));
        }
      }
    }
  }
  return covered;
}

void main() {
  test('a hand-made mask: two triangles per run, exact coverage', () {
    final mask = FillMask(
      left: 1,
      top: 0,
      right: 7,
      bottom: 3,
      runs: Int32List.fromList([0, 2, 5, 1, 1, 3, 1, 4, 7, 2, 6, 7]),
    );
    final t = fillTriangles(mask);
    expect(t.length, mask.runCount * 2 * 6);
    final covered = _rasterize(t, 8, 4);
    expect(covered, {
      for (var y = 0; y < 4; y++)
        for (var x = 0; x < 8; x++)
          if (mask.contains(x, y)) (x, y),
    });
  });

  test('flood fill masks rasterize back to themselves', () {
    final random = math.Random(7);
    for (var round = 0; round < 20; round++) {
      const w = 24, h = 18;
      final rgba = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
      // Random black specks and bars break the area into irregular runs.
      for (var k = 0; k < 60; k++) {
        final x = random.nextInt(w), y = random.nextInt(h);
        final len = 1 + random.nextInt(5);
        final vertical = random.nextBool();
        for (var s = 0; s < len; s++) {
          final px = vertical ? x : math.min(w - 1, x + s);
          final py = vertical ? math.min(h - 1, y + s) : y;
          final o = (py * w + px) * 4;
          rgba
            ..[o] = 0
            ..[o + 1] = 0
            ..[o + 2] = 0;
        }
      }
      final seed = (random.nextInt(w), random.nextInt(h));
      final mask = floodFill(rgba, w, h, [seed], 0xFFE57373);
      if (mask == null) continue;
      final t = fillTriangles(mask);
      expect(t.length ~/ 6, 2 * mask.runCount);
      expect(_rasterize(t, w, h), {
        for (var y = 0; y < h; y++)
          for (var x = 0; x < w; x++)
            if (mask.contains(x, y)) (x, y),
      }, reason: 'round $round');
    }
  });

  test('an empty run list gives no triangles', () {
    final mask = FillMask(
      left: 0,
      top: 0,
      right: 0,
      bottom: 0,
      runs: Int32List(0),
    );
    expect(fillTriangles(mask), isEmpty);
  });
}
