import 'dart:typed_data';

import 'picture_meta.dart';

/// The region id of every pixel of a picture (`regions.png`), 0 = line.
class RegionMap {
  RegionMap(this.width, this.height, this.ids) : maxId = _max(ids) {
    if (width <= 0 || height <= 0 || ids.length != width * height) {
      throw ArgumentError('ids.length ${ids.length} != $width x $height');
    }
  }

  /// Builds the map from straight RGBA bytes: id = R << 8 | G (B and A are
  /// ignored). Throws [ArgumentError] when the length is not width*height*4.
  factory RegionMap.fromRgba(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
      throw ArgumentError('rgba.length ${rgba.length} != $width x $height x 4');
    }
    final ids = Uint16List(width * height);
    for (var i = 0, j = 0; i < ids.length; i++, j += 4) {
      ids[i] = rgba[j] << 8 | rgba[j + 1];
    }
    return RegionMap(width, height, ids);
  }

  final int width;
  final int height;

  /// Row-major ids.
  final Uint16List ids;

  /// The largest id in the map.
  final int maxId;

  /// The id at pixel ([x], [y]); 0 outside the image.
  int idAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    return ids[y * width + x];
  }

  /// The id under image point ([x], [y]). On a line pixel, the nearest
  /// region within [tolerance] image px (Euclidean, pixel centers); ties go
  /// to the smaller id. 0 when nothing is found or outside the image.
  int lookup(double x, double y, {required double tolerance}) {
    if (x.isNaN || y.isNaN || x < 0 || y < 0 || x >= width || y >= height) {
      return 0;
    }
    final px = x.floor();
    final py = y.floor();
    final direct = ids[py * width + px];
    if (direct != 0 || tolerance < 1) return direct;
    final maxD2 = tolerance * tolerance;
    final maxRing = tolerance.floor();
    var bestD2 = 1 << 30;
    var bestId = 0;
    for (var r = 1; r <= maxRing; r++) {
      // Every pixel of ring r is at least r away.
      if (r * r > bestD2 || r * r > maxD2) break;
      final y0 = py - r;
      final y1 = py + r;
      for (var dx = -r; dx <= r; dx++) {
        final cx = px + dx;
        if (cx < 0 || cx >= width) continue;
        final d2 = dx * dx + r * r;
        if (d2 > maxD2 || d2 > bestD2) continue;
        if (y0 >= 0) {
          final id = ids[y0 * width + cx];
          if (id != 0 && (d2 < bestD2 || id < bestId)) {
            bestD2 = d2;
            bestId = id;
          }
        }
        if (y1 < height) {
          final id = ids[y1 * width + cx];
          if (id != 0 && (d2 < bestD2 || id < bestId)) {
            bestD2 = d2;
            bestId = id;
          }
        }
      }
      final x0 = px - r;
      final x1 = px + r;
      for (var dy = -r + 1; dy <= r - 1; dy++) {
        final cy = py + dy;
        if (cy < 0 || cy >= height) continue;
        final d2 = dy * dy + r * r;
        if (d2 > maxD2 || d2 > bestD2) continue;
        final row = cy * width;
        if (x0 >= 0) {
          final id = ids[row + x0];
          if (id != 0 && (d2 < bestD2 || id < bestId)) {
            bestD2 = d2;
            bestId = id;
          }
        }
        if (x1 < width) {
          final id = ids[row + x1];
          if (id != 0 && (d2 < bestD2 || id < bestId)) {
            bestD2 = d2;
            bestId = id;
          }
        }
      }
    }
    return bestId;
  }

  /// Throws [FormatException] when this map does not belong to [meta].
  void checkMatches(PictureMeta meta) {
    if (width != meta.width || height != meta.height) {
      throw FormatException(
        'regions.png is $width x $height, regions.json says '
        '${meta.width} x ${meta.height}',
      );
    }
    if (maxId != meta.regionCount) {
      throw FormatException(
        'regions.png max id $maxId != region count ${meta.regionCount}',
      );
    }
  }

  static int _max(Uint16List ids) {
    var m = 0;
    for (final id in ids) {
      if (id > m) m = id;
    }
    return m;
  }
}
