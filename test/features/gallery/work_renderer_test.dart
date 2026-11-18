import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coloring/features/gallery/data/work_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../coloring/model/fixtures.dart';

const navy = (0, 0, 128, 255);

/// A transparent 16×12 `lines` layer with an opaque navy 3×3 block at
/// x 9–11, y 5–7, inside region 4.
Future<ui.Image> linesImage() {
  final rgba = Uint8List(fixtureWidth * fixtureHeight * 4);
  for (var y = 5; y <= 7; y++) {
    for (var x = 9; x <= 11; x++) {
      final i = (y * fixtureWidth + x) * 4;
      rgba[i + 2] = 128;
      rgba[i + 3] = 255;
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    fixtureWidth,
    fixtureHeight,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

/// Decodes [png]; returns its size and a pixel reader.
Future<(int, int, (int, int, int, int) Function(int, int))> decode(
  Uint8List png,
) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  final data = (await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  final width = image.width;
  final height = image.height;
  image.dispose();
  final bytes = data.buffer.asUint8List();
  return (
    width,
    height,
    (int x, int y) {
      final i = (y * width + x) * 4;
      return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
    },
  );
}

void main() {
  final colors = Uint32List(6)
    ..[1] = red
    ..[4] = green;

  testWidgets('renders a PNG of the requested size with fills and lines', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final lines = await linesImage();
      addTearDown(lines.dispose);
      for (final (w, h) in [(fixtureWidth, fixtureHeight), (32, 24)]) {
        final png = await renderWorkPng(
          map: fixtureMap(),
          colors: colors,
          lines: lines,
          width: w,
          height: h,
        );
        expect(png.sublist(1, 4), 'PNG'.codeUnits);
        final (width, height, at) = await decode(png);
        expect((width, height), (w, h));
        final s = w ~/ fixtureWidth;
        // Region 1 (filled red), region 3 (unfilled), region 4 (green).
        expect(at(2 * s, 1 * s), (255, 0, 0, 255));
        expect(at(2 * s, 6 * s), (255, 255, 255, 255));
        expect(at(14 * s, 6 * s), (0, 255, 0, 255));
        // Under the opaque line block the line color wins.
        expect(at(10 * s, 6 * s), navy);
      }
      expect(lines.debugDisposed, isFalse);
    });
  });
}
