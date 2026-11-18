import 'dart:typed_data';

import '../../coloring/model/region_map.dart';

/// The fills of a work as straight RGBA bytes of [width] × [height]: each
/// output pixel takes the region id at its center in [map] (nearest
/// neighbour) and that region's color from [colors] (ARGB, index = region
/// id). Unfilled regions (0), ids beyond [colors] and line pixels (id 0) are
/// white. Every pixel is opaque. Throws [ArgumentError] for a size ≤ 0.
Uint8List composeFillPixels({
  required RegionMap map,
  required Uint32List colors,
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('output size $width x $height');
  }
  // One packed RGBA entry per region id, written byte by byte so the result
  // does not depend on the host byte order.
  final lut = Uint32List(map.maxId + 1);
  final lutBytes = lut.buffer.asUint8List();
  for (var id = 0; id < lut.length; id++) {
    final argb = id == 0 || id >= colors.length || colors[id] == 0
        ? 0xFFFFFFFF
        : colors[id];
    final b = id * 4;
    lutBytes[b] = (argb >> 16) & 0xFF;
    lutBytes[b + 1] = (argb >> 8) & 0xFF;
    lutBytes[b + 2] = argb & 0xFF;
    lutBytes[b + 3] = 0xFF;
  }

  // Source column/row of each output pixel center: floor((o + 0.5) · s / d).
  final xs = Int32List(width);
  for (var x = 0; x < width; x++) {
    xs[x] = ((2 * x + 1) * map.width) ~/ (2 * width);
  }
  final out = Uint8List(width * height * 4);
  final out32 = out.buffer.asUint32List();
  final ids = map.ids;
  for (var y = 0, i = 0; y < height; y++) {
    final row = (((2 * y + 1) * map.height) ~/ (2 * height)) * map.width;
    for (var x = 0; x < width; x++, i++) {
      out32[i] = lut[ids[row + xs[x]]];
    }
  }
  return out;
}
