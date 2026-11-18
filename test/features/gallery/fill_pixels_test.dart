import 'dart:typed_data';

import 'package:coloring/features/coloring/model/region_map.dart';
import 'package:coloring/features/gallery/model/fill_pixels.dart';
import 'package:flutter_test/flutter_test.dart';

import '../coloring/model/fixtures.dart';

/// (r, g, b, a) of pixel ([x], [y]) in straight RGBA [pixels] of [width].
(int, int, int, int) pixel(Uint8List pixels, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]);
}

const white = (255, 255, 255, 255);

void main() {
  final map = fixtureMap();

  Uint32List colorsWith(Map<int, int> fills) {
    final colors = Uint32List(6);
    fills.forEach((id, color) => colors[id] = color);
    return colors;
  }

  test('an unfilled picture is white and opaque', () {
    final out = composeFillPixels(
      map: map,
      colors: colorsWith({}),
      width: fixtureWidth,
      height: fixtureHeight,
    );
    expect(out.length, fixtureWidth * fixtureHeight * 4);
    expect(out.every((b) => b == 255), isTrue);
  });

  test('a filled region takes its color, lines stay white', () {
    final out = composeFillPixels(
      map: map,
      colors: colorsWith({1: red, 2: green, 5: base}),
      width: fixtureWidth,
      height: fixtureHeight,
    );
    expect(pixel(out, fixtureWidth, 2, 1), (255, 0, 0, 255));
    expect(pixel(out, fixtureWidth, 10, 1), (0, 255, 0, 255));
    expect(pixel(out, fixtureWidth, 8, 10), (0x12, 0x34, 0x56, 255));
    // Region 3 is unfilled; column 6 and row 4 are lines.
    expect(pixel(out, fixtureWidth, 2, 6), white);
    expect(pixel(out, fixtureWidth, 6, 1), white);
    expect(pixel(out, fixtureWidth, 3, 4), white);
  });

  test('every pixel is opaque, ids beyond the colors are white', () {
    final out = composeFillPixels(
      map: map,
      colors: Uint32List.fromList([0, blue]),
      width: fixtureWidth,
      height: fixtureHeight,
    );
    for (var i = 3; i < out.length; i += 4) {
      expect(out[i], 255);
    }
    expect(pixel(out, fixtureWidth, 0, 0), (0, 0, 255, 255));
    expect(pixel(out, fixtureWidth, 10, 1), white);
  });

  test('a 2x downscale samples the source at output pixel centers', () {
    // Source ids 1..16 per column, so the sampled column is visible.
    final wide = RegionMap(
      16,
      2,
      Uint16List.fromList([
        for (var r = 0; r < 2; r++) ...List.generate(16, (i) => i + 1),
      ]),
    );
    final colors = Uint32List.fromList([
      0,
      for (var id = 1; id <= 16; id++) 0xFF000000 | id,
    ]);
    final out = composeFillPixels(
      map: wide,
      colors: colors,
      width: 8,
      height: 1,
    );
    expect(out.length, 8 * 1 * 4);
    // Output x maps to source floor((x + 0.5) * 2) = 2x + 1, i.e. id 2x + 2.
    for (var x = 0; x < 8; x++) {
      expect(pixel(out, 8, x, 0), (0, 0, 2 * x + 2, 255));
    }
  });

  test('the fixture at half size keeps regions and the line pattern', () {
    final out = composeFillPixels(
      map: map,
      colors: colorsWith({1: red, 4: green}),
      width: 8,
      height: 6,
    );
    expect(out.length, 8 * 6 * 4);
    // (0, 0) → source (1, 1): region 1; (3, 2) → source (7, 5): region 4.
    expect(pixel(out, 8, 0, 0), (255, 0, 0, 255));
    expect(pixel(out, 8, 3, 2), (0, 255, 0, 255));
    // (0, 2) → source (1, 5): region 3, unfilled.
    expect(pixel(out, 8, 0, 2), white);
  });

  test('a size of zero is rejected', () {
    expect(
      () => composeFillPixels(
        map: map,
        colors: Uint32List(6),
        width: 0,
        height: 4,
      ),
      throwsArgumentError,
    );
  });
}
