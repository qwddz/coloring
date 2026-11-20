import 'dart:typed_data';

/// A pixel joins the fill when its sum RGB distance to the seed color is at
/// most this. The lightest non-white base color is 92 from white and the
/// closest base pair is 41 apart, so a solid line of any base color stops it.
const int fillTolerance = 32;

/// An edge pixel joins the fill when its distance to the seed is below this
/// share of the largest distance among its 8-neighbors outside the fill (a
/// stronger line) and it is a blend of the seed color and that neighbor
/// ([fillBlendSlack]).
const double fillEdgeRatio = 0.6;

/// How far (sum RGB) an edge pixel may stray from the straight blend between
/// the seed color and its stronger neighbor and still count as that blend. A
/// lighter line between the seed area and a darker area is no such blend, so
/// filling next to it does not eat into it.
const int fillBlendSlack = 16;

/// The pixels a fill covers: a bounding box and run-length rows.
///
/// [runs] holds triples `(y, x0, x1)` with `x1` exclusive, sorted by `y`, then
/// `x0`; runs of one row never touch or overlap.
class FillMask {
  const FillMask({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.runs,
  });

  /// Bounding box, `right` and `bottom` exclusive.
  final int left;
  final int top;
  final int right;
  final int bottom;

  final Int32List runs;

  int get runCount => runs.length ~/ 3;

  int get pixelCount {
    var count = 0;
    for (var i = 0; i < runs.length; i += 3) {
      count += runs[i + 2] - runs[i + 1];
    }
    return count;
  }

  bool contains(int x, int y) {
    if (x < left || x >= right || y < top || y >= bottom) return false;
    for (var i = 0; i < runs.length; i += 3) {
      final ry = runs[i];
      if (ry > y) return false;
      if (ry == y && x >= runs[i + 1] && x < runs[i + 2]) return true;
    }
    return false;
  }
}

/// Sum RGB distance between two ARGB colors; alpha is ignored.
int colorDistance(int a, int b) =>
    ((a >> 16 & 0xFF) - (b >> 16 & 0xFF)).abs() +
    ((a >> 8 & 0xFF) - (b >> 8 & 0xFF)).abs() +
    ((a & 0xFF) - (b & 0xFF)).abs();

/// Scanline flood fill of the opaque RGBA raster [rgba] ([width] × [height],
/// 4 bytes per pixel, R first) from each of [seeds] (`(x, y)` in pixels).
///
/// Each seed fills its 4-connected area of pixels within [fillTolerance] of the
/// seed pixel's color, plus one pixel of antialiased edge (see
/// [fillEdgeRatio]). Seeds outside the raster, seeds already covered by an
/// earlier seed and seeds whose color is within [fillTolerance] of [fillColor]
/// (ARGB) add nothing. Returns `null` when nothing would change.
FillMask? floodFill(
  Uint8List rgba,
  int width,
  int height,
  List<(int, int)> seeds,
  int fillColor,
) {
  assert(rgba.length >= width * height * 4);
  // 0 = outside, 1 = in the mask, 2 = joins by edge dilation (pending).
  final state = Uint8List(width * height);
  final stack = <int>[];
  var left = width, top = height, right = 0, bottom = 0;
  var any = false;

  int distanceAt(int p, int r, int g, int b) {
    final o = p * 4;
    return (rgba[o] - r).abs() +
        (rgba[o + 1] - g).abs() +
        (rgba[o + 2] - b).abs();
  }

  for (final (sx, sy) in seeds) {
    if (sx < 0 || sy < 0 || sx >= width || sy >= height) continue;
    final seedIndex = sy * width + sx;
    if (state[seedIndex] == 1) continue;
    final so = seedIndex * 4;
    final r = rgba[so], g = rgba[so + 1], b = rgba[so + 2];
    final seedColor = 0xFF000000 | r << 16 | g << 8 | b;
    if (colorDistance(seedColor, fillColor) <= fillTolerance) continue;

    bool joins(int p) =>
        state[p] != 1 && distanceAt(p, r, g, b) <= fillTolerance;

    // Runs this seed adds, as (y, x0, x1) triples, for the dilation pass.
    final added = <int>[];
    stack.add(seedIndex);
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      if (!joins(p)) continue;
      final y = p ~/ width;
      final rowStart = y * width;
      var x0 = p - rowStart;
      while (x0 > 0 && joins(rowStart + x0 - 1)) {
        x0--;
      }
      var x1 = p - rowStart + 1;
      while (x1 < width && joins(rowStart + x1)) {
        x1++;
      }
      for (var x = x0; x < x1; x++) {
        state[rowStart + x] = 1;
      }
      added
        ..add(y)
        ..add(x0)
        ..add(x1);
      for (final ny in [y - 1, y + 1]) {
        if (ny < 0 || ny >= height) continue;
        final nRow = ny * width;
        var x = x0;
        while (x < x1) {
          // Push one pixel per joining stretch of the neighbor row.
          if (joins(nRow + x)) {
            stack.add(nRow + x);
            while (x < x1 && joins(nRow + x)) {
              x++;
            }
          } else {
            x++;
          }
        }
      }
    }

    // One pixel of edge dilation against this seed's mask: a pixel p outside
    // the mask joins when its farthest neighbor q outside the mask is a much
    // stronger line and p is a partial blend between the seed and q.
    final joined = <int>[];
    for (var i = 0; i < added.length; i += 3) {
      final y = added[i];
      final cx0 = added[i + 1] > 0 ? added[i + 1] - 1 : 0;
      final cx1 = added[i + 2] < width ? added[i + 2] + 1 : width;
      for (var cy = y - 1; cy <= y + 1; cy++) {
        if (cy < 0 || cy >= height) continue;
        for (var cx = cx0; cx < cx1; cx++) {
          final p = cy * width + cx;
          if (state[p] != 0) continue;
          final d = distanceAt(p, r, g, b);
          // The farthest 8-neighbor outside the mask: the line p may blend to.
          var q = -1, dq = 0;
          for (var ny = cy - 1; ny <= cy + 1; ny++) {
            if (ny < 0 || ny >= height) continue;
            for (var nx = cx - 1; nx <= cx + 1; nx++) {
              if (nx < 0 || nx >= width || (nx == cx && ny == cy)) continue;
              final n = ny * width + nx;
              if (state[n] == 1) continue;
              final dn = distanceAt(n, r, g, b);
              if (dn > dq) {
                q = n;
                dq = dn;
              }
            }
          }
          if (q < 0 || d >= fillEdgeRatio * dq) continue;
          // p must be the blend seed + t (q - seed), t = d / dq.
          final t = d / dq, po = p * 4, qo = q * 4;
          final off =
              (rgba[po] - r - t * (rgba[qo] - r)).abs() +
              (rgba[po + 1] - g - t * (rgba[qo + 1] - g)).abs() +
              (rgba[po + 2] - b - t * (rgba[qo + 2] - b)).abs();
          if (off <= fillBlendSlack) {
            state[p] = 2;
            joined.add(p);
          }
        }
      }
    }
    for (final p in joined) {
      state[p] = 1;
    }

    if (added.isEmpty) continue;
    any = true;
    for (var i = 0; i < added.length; i += 3) {
      final y = added[i];
      // Dilation reaches one pixel beyond the runs.
      if (y - 1 < top) top = y - 1 < 0 ? 0 : y - 1;
      if (y + 2 > bottom) bottom = y + 2 > height ? height : y + 2;
      final x0 = added[i + 1] - 1, x1 = added[i + 2] + 1;
      if (x0 < left) left = x0 < 0 ? 0 : x0;
      if (x1 > right) right = x1 > width ? width : x1;
    }
  }
  if (!any) return null;

  // Collect canonical runs over the (possibly loose) bounding box, then
  // tighten the box to them.
  final runs = <int>[];
  var tLeft = width, tTop = height, tRight = 0, tBottom = 0;
  for (var y = top; y < bottom; y++) {
    final row = y * width;
    var x = left;
    while (x < right) {
      if (state[row + x] != 1) {
        x++;
        continue;
      }
      final x0 = x;
      while (x < right && state[row + x] == 1) {
        x++;
      }
      runs
        ..add(y)
        ..add(x0)
        ..add(x);
      if (x0 < tLeft) tLeft = x0;
      if (x > tRight) tRight = x;
      if (y < tTop) tTop = y;
      tBottom = y + 1;
    }
  }
  return FillMask(
    left: tLeft,
    top: tTop,
    right: tRight,
    bottom: tBottom,
    runs: Int32List.fromList(runs),
  );
}
