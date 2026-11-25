import 'dart:math' as math;

import 'package:coloring/features/drawing/model/flood_fill.dart';
import 'package:coloring/features/drawing/model/drawing_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _white = 0xFFFFFFFF;

/// An opaque RGBA raster with antialiased drawing helpers for the tests.
class _Raster {
  _Raster(this.width, this.height, [int color = _white])
    : rgba = Uint8List(width * height * 4) {
    for (var p = 0; p < width * height; p++) {
      set(p % width, p ~/ width, color);
    }
  }

  final int width;
  final int height;
  final Uint8List rgba;

  int get(int x, int y) {
    final o = (y * width + x) * 4;
    return 0xFF000000 | rgba[o] << 16 | rgba[o + 1] << 8 | rgba[o + 2];
  }

  void set(int x, int y, int color) {
    final o = (y * width + x) * 4;
    rgba
      ..[o] = color >> 16 & 0xFF
      ..[o + 1] = color >> 8 & 0xFF
      ..[o + 2] = color & 0xFF
      ..[o + 3] = 0xFF;
  }

  /// Blends [color] over every pixel with its coverage from [coverage].
  void draw(int color, double Function(int x, int y) coverage) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = coverage(x, y);
        if (c <= 0) continue;
        final base = get(x, y);
        int mix(int shift) {
          final a = base >> shift & 0xFF, b = color >> shift & 0xFF;
          return (a + (b - a) * c).round();
        }

        set(x, y, 0xFF000000 | mix(16) << 16 | mix(8) << 8 | mix(0));
      }
    }
  }

  void apply(FillMask mask, int color) {
    for (var i = 0; i < mask.runs.length; i += 3) {
      for (var x = mask.runs[i + 1]; x < mask.runs[i + 2]; x++) {
        set(x, mask.runs[i], color);
      }
    }
  }

  FillMask? fill(List<(int, int)> seeds, int color) =>
      floodFill(rgba, width, height, seeds, color);
}

/// The mask as one byte per pixel (1 = covered).
Uint8List _maskBits(FillMask mask, int width, int height) {
  final bits = Uint8List(width * height);
  for (var i = 0; i < mask.runs.length; i += 3) {
    final row = mask.runs[i] * width;
    bits.fillRange(row + mask.runs[i + 1], row + mask.runs[i + 2], 1);
  }
  return bits;
}

_Raster _copy(_Raster r) => _Raster(r.width, r.height)..rgba.setAll(0, r.rgba);

/// Distance from the pixel center to segment a–b.
double _segmentDistance(double px, double py, List<double> a, List<double> b) {
  final dx = b[0] - a[0], dy = b[1] - a[1];
  final t = (((px - a[0]) * dx + (py - a[1]) * dy) / (dx * dx + dy * dy)).clamp(
    0.0,
    1.0,
  );
  final cx = a[0] + t * dx - px, cy = a[1] + t * dy - py;
  return math.sqrt(cx * cx + cy * cy);
}

/// Coverage of a closed polyline stroke of [lineWidth], box-filter style.
double Function(int, int) _polygonStroke(
  List<List<double>> points,
  double lineWidth,
) => (x, y) {
  var d = double.infinity;
  for (var i = 0; i < points.length; i++) {
    d = math.min(
      d,
      _segmentDistance(
        x + 0.5,
        y + 0.5,
        points[i],
        points[(i + 1) % points.length],
      ),
    );
  }
  return (lineWidth / 2 + 0.5 - d).clamp(0.0, 1.0);
};

/// Whether the pixel center lies inside the convex polygon (clockwise or not).
bool _insidePolygon(List<List<double>> pts, int x, int y) {
  final px = x + 0.5, py = y + 0.5;
  var sign = 0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    final cross = (b[0] - a[0]) * (py - a[1]) - (b[1] - a[1]) * (px - a[0]);
    final s = cross > 0 ? 1 : (cross < 0 ? -1 : 0);
    if (s == 0) continue;
    if (sign == 0) sign = s;
    if (s != sign) return false;
  }
  return true;
}

void main() {
  test('colorDistance is the sum of channel differences', () {
    expect(colorDistance(0xFF102030, 0xFF000000), 0x10 + 0x20 + 0x30);
    expect(colorDistance(0x00FFFFFF, 0xFFFFFFFF), 0);
    expect(colorDistance(0xFFF4B6B6, 0xFFF1C6A0), 41);
  });

  test('the palette rationale of the threshold holds', () {
    final colors = drawingPalette.where((c) => c != _white).toList();
    for (final c in colors) {
      expect(colorDistance(c, _white), greaterThan(fillTolerance));
    }
    for (var i = 0; i < drawingPalette.length; i++) {
      for (var j = i + 1; j < drawingPalette.length; j++) {
        expect(
          colorDistance(drawingPalette[i], drawingPalette[j]),
          greaterThan(fillTolerance),
        );
      }
    }
  });

  test('a closed square fills inside only', () {
    final r = _Raster(20, 20);
    for (var i = 4; i <= 15; i++) {
      r
        ..set(i, 4, 0xFF000000)
        ..set(i, 15, 0xFF000000)
        ..set(4, i, 0xFF000000)
        ..set(15, i, 0xFF000000);
    }
    final mask = r.fill([(10, 10)], 0xFFE57373)!;
    expect(mask.pixelCount, 10 * 10);
    expect((mask.left, mask.top, mask.right, mask.bottom), (5, 5, 15, 15));
    expect(mask.runCount, 10);
    for (var y = 0; y < 20; y++) {
      for (var x = 0; x < 20; x++) {
        final inside = x > 4 && x < 15 && y > 4 && y < 15;
        expect(mask.contains(x, y), inside, reason: '($x, $y)');
      }
    }
  });

  test('a gap in the outline leaks to the whole canvas', () {
    final r = _Raster(20, 20);
    for (var i = 4; i <= 15; i++) {
      r
        ..set(i, 4, 0xFF000000)
        ..set(i, 15, 0xFF000000)
        ..set(4, i, 0xFF000000);
      if (i < 9 || i > 10) r.set(15, i, 0xFF000000);
    }
    final mask = r.fill([(10, 10)], 0xFFE57373)!;
    expect(mask.contains(0, 0), isTrue);
    expect(mask.contains(19, 19), isTrue);
    expect(mask.pixelCount, 20 * 20 - (12 * 4 - 4 - 2));
  });

  test('a full white canvas fills completely, one run per row', () {
    final r = _Raster(64, 48);
    final mask = r.fill([(3, 7)], 0xFF4A86C5)!;
    expect(mask.pixelCount, 64 * 48);
    expect(mask.runCount, 48);
    expect((mask.left, mask.top, mask.right, mask.bottom), (0, 0, 64, 48));
  });

  test('no change returns null', () {
    final r = _Raster(16, 16);
    expect(r.fill([(3, 3)], _white), isNull);
    expect(r.fill([(3, 3)], 0xFFF8F0FF), isNull, reason: 'within tolerance');
    expect(r.fill([(-1, 3), (16, 0), (0, 16)], 0xFF000000), isNull);
    expect(r.fill(const [], 0xFF000000), isNull);
  });

  test('a seed on a line recolors the line, not the area', () {
    final r = _Raster(20, 20);
    for (var i = 4; i <= 15; i++) {
      r
        ..set(i, 4, 0xFF2D4F8A)
        ..set(i, 15, 0xFF2D4F8A)
        ..set(4, i, 0xFF2D4F8A)
        ..set(15, i, 0xFF2D4F8A);
    }
    final mask = r.fill([(4, 9)], 0xFFD2483F)!;
    expect(mask.pixelCount, 12 * 4 - 4);
    for (var y = 0; y < 20; y++) {
      for (var x = 0; x < 20; x++) {
        expect(mask.contains(x, y), r.get(x, y) == 0xFF2D4F8A);
      }
    }
  });

  test('mirror seeds fill both sides in one mask', () {
    const w = 40;
    final r = _Raster(w, 20);
    for (var y = 0; y < 20; y++) {
      r.set(w ~/ 2, y, 0xFF000000);
    }
    final mask = r.fill([(5, 10), (w - 5, 10)], 0xFF9CCB7A)!;
    expect(mask.pixelCount, w * 20 - 20);
    expect(mask.contains(0, 0) && mask.contains(w - 1, 19), isTrue);
    expect(mask.contains(w ~/ 2, 10), isFalse);

    // Both seeds in one area: same as one seed.
    final one = _Raster(w, 20).fill([(5, 10)], 0xFF9CCB7A)!;
    final two = _Raster(w, 20).fill([(5, 10), (w - 5, 10)], 0xFF9CCB7A)!;
    expect(two.runs, one.runs);

    // Seeds on different colors each fill their own area.
    final split = _Raster(w, 20);
    for (var y = 0; y < 20; y++) {
      for (var x = w ~/ 2; x < w; x++) {
        split.set(x, y, 0xFFBFE0F2);
      }
    }
    final both = split.fill([(5, 10), (w - 5, 10)], 0xFF2F6B45)!;
    expect(both.pixelCount, w * 20);
  });

  test('dilation never joins a solid core pixel', () {
    for (final line in drawingPalette.where((c) => c != _white)) {
      for (final fill in drawingPalette) {
        if (fill == line) continue;
        final r = _Raster(24, 24);
        // A 1 px aliased diagonal and a vertical line, both solid cores.
        for (var i = 0; i < 24; i++) {
          r
            ..set(i, i, line)
            ..set(12, i, line);
        }
        final mask = r.fill([(20, 2)], fill);
        if (fill == _white) {
          expect(mask, isNull);
          continue;
        }
        for (var y = 0; y < 24; y++) {
          for (var x = 0; x < 24; x++) {
            if (r.get(x, y) == line) {
              expect(mask!.contains(x, y), isFalse, reason: '($x, $y)');
            }
          }
        }
        // The fill stays in its wedge: right of x = 12 and above y = x.
        expect(mask!.contains(5, 20), isFalse);
        expect(mask.contains(14, 20), isFalse);
      }
    }
  });

  test('an antialiased circle fills without a light halo', () {
    for (final line in [0xFF2D4F8A, 0xFFE3CFEF, 0xFFF4B6B6, 0xFF9B9590]) {
      for (final width in [1.5, 2.0, 3.0]) {
        const cx = 25.3, cy = 24.7, radius = 16.0;
        final r = _Raster(50, 50)
          ..draw(line, (x, y) {
            final d = math.sqrt(
              math.pow(x + 0.5 - cx, 2) + math.pow(y + 0.5 - cy, 2),
            );
            return (width / 2 + 0.5 - (d - radius).abs()).clamp(0.0, 1.0);
          });
        const fill = 0xFF5FA05A;
        final mask = r.fill([(25, 25)], fill)!;
        final before = _copy(r);
        r.apply(mask, fill);
        for (var y = 0; y < 50; y++) {
          for (var x = 0; x < 50; x++) {
            final d = math.sqrt(
              math.pow(x + 0.5 - cx, 2) + math.pow(y + 0.5 - cy, 2),
            );
            final coverage = (width / 2 + 0.5 - (d - radius).abs()).clamp(
              0.0,
              1.0,
            );
            final reason = 'line ${line.toRadixString(16)} w $width ($x, $y)';
            if (d > radius) {
              // Outside the circle's center line: never touched.
              expect(r.get(x, y), before.get(x, y), reason: reason);
            } else if (coverage < 0.5) {
              // Mostly white inside: painted, so no light ring is left.
              expect(r.get(x, y), fill, reason: reason);
            } else if (coverage >= fillEdgeRatio) {
              expect(r.get(x, y), before.get(x, y), reason: reason);
            }
          }
        }
      }
    }
  });

  group('every base color as a thin pencil line', () {
    final lines = drawingPalette.where((c) => c != _white).toList();
    // The small pencil at pressure 0.5 is about 5 px wide (12 x 0.5 x 0.85);
    // an antialiased 2 px line is thinner and so a stricter test.
    const lineWidth = 2.0;
    const w = 48, h = 40;
    final shapes = <String, List<List<double>>>{
      'axis-aligned rectangle': [
        [8.3, 7.6],
        [39.6, 7.6],
        [39.6, 31.8],
        [8.3, 31.8],
      ],
      'rotated quad': [
        [24.2, 3.3],
        [44.1, 19.6],
        [23.7, 36.4],
        [4.4, 20.1],
      ],
    };

    for (final MapEntry(key: name, value: points) in shapes.entries) {
      test('closes a $name against every other base color', () {
        final coverage = _polygonStroke(points, lineWidth);
        const inSeed = (24, 20), outSeed = (0, 0);
        bool inside(int x, int y) =>
            _insidePolygon(points, x, y) && coverage(x, y) == 0;
        bool outside(int x, int y) =>
            !_insidePolygon(points, x, y) && coverage(x, y) == 0;
        List<(int, int)> pixelsWith(bool Function(double) test) => [
          for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++)
              if (test(coverage(x, y))) (x, y),
        ];
        // Pixels mostly of the line color (a margin over the edge ratio for
        // rounding), and the line's solid core.
        final strong = pixelsWith((c) => c >= fillEdgeRatio + 0.05);
        final solid = pixelsWith((c) => c == 1);
        List<(int, int)> pixelsWithXY(bool Function(int, int) test) => [
          for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++)
              if (test(x, y)) (x, y),
        ];

        final insidePx = pixelsWithXY(inside);
        final outsidePx = pixelsWithXY(outside);

        void expectFill(
          _Raster r,
          (int, int) seed,
          int color,
          List<(int, int)> kept,
          String reason,
        ) {
          final fromInside = seed == inSeed;
          final before = [for (final (x, y) in kept) r.get(x, y)];
          final mask = r.fill([seed], color)!;
          final bits = _maskBits(mask, w, h);
          final other = fromInside ? outsidePx : insidePx;
          final own = fromInside ? insidePx : outsidePx;
          expect(
            [
              for (final (x, y) in other)
                if (bits[y * w + x] == 1) (x, y),
            ],
            isEmpty,
            reason: '$reason leak',
          );
          expect(
            [
              for (final (x, y) in own)
                if (bits[y * w + x] == 0) (x, y),
            ],
            isEmpty,
            reason: '$reason area',
          );
          r.apply(mask, color);
          expect(
            [
              for (var i = 0; i < kept.length; i++)
                if (r.get(kept[i].$1, kept[i].$2) != before[i]) kept[i],
            ],
            isEmpty,
            reason: '$reason line changed',
          );
        }

        for (final line in lines) {
          final onWhite = _Raster(w, h)..draw(line, coverage);
          for (final a in drawingPalette) {
            if (a == line) continue;
            final reason =
                'line ${line.toRadixString(16)} fill ${a.toRadixString(16)}';
            if (a == _white) {
              expect(onWhite.fill([inSeed], a), isNull, reason: reason);
              expect(onWhite.fill([outSeed], a), isNull, reason: reason);
              continue;
            }
            // On white, inside and outside, each on the freshly drawn line.
            expectFill(_copy(onWhite), inSeed, a, strong, '$reason in');
            expectFill(_copy(onWhite), outSeed, a, strong, '$reason out');

            // On a base color: the line drawn over a sheet filled with `a`,
            // then filled inside or outside with every other base color.
            final onColor = _Raster(w, h, a)..draw(line, coverage);
            for (final b in drawingPalette) {
              if (b == a) continue;
              final at = '$reason on ${b.toRadixString(16)}';
              expectFill(_copy(onColor), inSeed, b, solid, '$at in');
              expectFill(_copy(onColor), outSeed, b, solid, '$at out');
            }

            // In a row: inside, then outside with every color next to it.
            final filled = _copy(onWhite);
            filled.apply(filled.fill([inSeed], a)!, a);
            for (final b in drawingPalette.where((c) => c != _white)) {
              final bits = _maskBits(filled.fill([outSeed], b)!, w, h);
              expect(
                [
                  for (final (x, y) in insidePx)
                    if (bits[y * w + x] == 1) (x, y),
                ],
                isEmpty,
                reason: '$reason row ${b.toRadixString(16)}',
              );
            }
          }
        }
      });
    }
  });

  test('a line pixel that is no blend of the seed and its neighbor stays', () {
    // A peach area, a solid pink line pixel, then a pinkish antialiased pixel
    // on white: pink is far below 0.6 of that neighbor's distance from peach,
    // but it is no peach-to-pinkish blend, so it is a line, not an edge.
    final r = _Raster(8, 3);
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        r.set(x, y, 0xFFF1C6A0);
      }
      r
        ..set(3, y, 0xFFF4B6B6)
        ..set(4, y, 0xFFF8D3D3);
    }
    final mask = r.fill([(0, 1)], 0xFFE57373)!;
    expect(mask.pixelCount, 9);
    for (var y = 0; y < 3; y++) {
      expect(mask.contains(3, y), isFalse);
    }
  });

  test('2048 x 1536 timing', () {
    final r = _Raster(2048, 1536);
    // A few closed outlines so the fill has edges to dilate.
    for (var i = 0; i < 6; i++) {
      final x = 150.0 + i * 300, y = 200.0 + (i % 2) * 500;
      r.draw(0xFF2D4F8A, (px, py) {
        if (px < x - 3 || px > x + 263 || py < y - 3 || py > y + 403) return 0;
        return _polygonStroke([
          [x, y],
          [x + 260, y],
          [x + 260, y + 400],
          [x, y + 400],
        ], 4)(px, py);
      });
    }
    final watch = Stopwatch()..start();
    final full = r.fill([(5, 5)], 0xFFE57373)!;
    final fullMs = watch.elapsedMilliseconds;
    watch.reset();
    final mirrored = r.fill([(200, 300), (2048 - 200, 300)], 0xFFE57373)!;
    final mirroredMs = watch.elapsedMilliseconds;
    debugPrint(
      'floodFill 2048x1536: outer area ${full.pixelCount} px '
      '${full.runCount} runs in $fullMs ms; mirror seeds '
      '${mirrored.pixelCount} px in $mirroredMs ms',
    );
    expect(full.pixelCount, greaterThan(2048 * 1536 ~/ 2));
  });
}
