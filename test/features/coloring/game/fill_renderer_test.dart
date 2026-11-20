import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coloring/features/coloring/game/fill_renderer.dart';
import 'package:coloring/features/coloring/game/state_texture.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:coloring/features/coloring/model/picture_meta.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 64;
const _h = 48;
const _red = 0xFFFF0000;
const _green = 0xFF00FF00;
const _blue = 0xFF0000FF;

/// Quadrants: 1 top-left, 2 top-right, 300 bottom-left, 301 bottom-right
/// (ids above 256, so both R and G bytes matter); row 23 is a line (0).
int _idAt(int x, int y) {
  if (y == 23) return 0;
  if (y < 23) return x < 32 ? 1 : 2;
  return x < 32 ? 300 : 301;
}

/// 301 regions; palette index 0 except 2 → 1, 300 → 2, 301 → 3.
PictureMeta _meta() => PictureMeta.fromJson({
  'width': _w,
  'height': _h,
  'level': 'simple',
  'background': 1,
  'palette': ['#ff0000', '#00ff00', '#0000ff', '#ffff00'],
  'regions': [
    for (var id = 1; id <= 301; id++)
      {
        'id': id,
        'palette': switch (id) {
          2 => 1,
          300 => 2,
          301 => 3,
          _ => 0,
        },
        'color': '#808080',
        'area': 1,
        'bbox': [0, 0, 1, 1],
        'label': [0.5, 0.5],
        'label_radius': 1.0,
      },
  ],
});

Future<ui.Image> _regionsImage() {
  final rgba = Uint8List(_w * _h * 4);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      final id = _idAt(x, y);
      final i = (y * _w + x) * 4;
      rgba[i] = id >> 8;
      rgba[i + 1] = id & 0xFF;
      rgba[i + 3] = 255;
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    _w,
    _h,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

class _Pixels {
  _Pixels(this._bytes);

  final Uint8List _bytes;

  List<int> at(int x, int y) {
    final i = (y * _w + x) * 4;
    return _bytes.sublist(i, i + 4);
  }
}

Future<_Pixels> _render(FillRenderer renderer, FillUniforms u) async {
  final recorder = ui.PictureRecorder();
  renderer.paint(
    ui.Canvas(recorder),
    const ui.Rect.fromLTWH(0, 0, _w * 1.0, _h * 1.0),
    1,
    u,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_w, _h);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return _Pixels(data!.buffer.asUint8List());
}

Matcher _near(List<int> rgba) => predicate<List<int>>(
  (v) =>
      [for (var i = 0; i < 4; i++) (v[i] - rgba[i]).abs() <= 2]
          .every((ok) => ok),
  'within 2 of $rgba',
);

void main() {
  late PictureMeta meta;
  late ui.Image regions;
  late ShaderFillRenderer renderer;

  Future<void> setUpRenderer() async {
    meta = _meta();
    regions = await _regionsImage();
    renderer = ShaderFillRenderer(
      await ShaderFillRenderer.loadProgram(),
      regions,
    );
  }

  void tearDownRenderer() {
    renderer.dispose();
    regions.dispose();
  }

  FillUniforms uniformsFor(FillState state) => FillUniforms()
    ..fill = state
    ..stateTexture = buildStateTexture(state, meta);

  testWidgets('draws fills, white for unfilled regions and lines, and a '
      'half-done wave', (tester) async {
    await tester.runAsync(() async {
      await setUpRenderer();
      final state = FillState(301)
        ..colors[1] = _red
        ..colors[300] = _blue
        ..colors[301] = _green;
      final u = uniformsFor(state)
        ..waveId = 300
        ..waveX = 0
        ..waveY = 24
        ..waveRadius = 16
        ..waveOldColor = 0
        ..waveNewColor = _blue;
      final px = await _render(renderer, u);

      expect(px.at(5, 5), [255, 0, 0, 255]); // filled
      expect(px.at(40, 5), [255, 255, 255, 255]); // unfilled
      expect(px.at(5, 23), [255, 255, 255, 255]); // line: paper
      expect(px.at(2, 26), [0, 0, 255, 255]); // inside the wave
      expect(px.at(28, 44), [255, 255, 255, 255]); // outside the wave
      expect(px.at(40, 40), [0, 255, 0, 255]); // other region untouched

      u.stateTexture!.dispose();
      tearDownRenderer();
    });
  });

  testWidgets('no bleeding across a boundary between ids 300 and 301', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await setUpRenderer();
      final state = FillState(301)
        ..colors[300] = _blue
        ..colors[301] = _green;
      final u = uniformsFor(state);
      final px = await _render(renderer, u);

      for (final y in [24, 35, 47]) {
        expect(px.at(31, y), [0, 0, 255, 255], reason: 'id 300 at y $y');
        expect(px.at(32, y), [0, 255, 0, 255], reason: 'id 301 at y $y');
      }

      u.stateTexture!.dispose();
      tearDownRenderer();
    });
  });

  testWidgets('stripes only unfinished regions of the highlighted palette '
      'index and flashes a rejected region', (tester) async {
    await tester.runAsync(() async {
      await setUpRenderer();
      final state = FillState(301)..colors[1] = _red;
      final u = uniformsFor(state)
        ..highlightPalette = 1
        ..pulse = 0;
      var px = await _render(renderer, u);
      // Pixel centers: x + y = 46, 4 px from a period edge, inside a stripe:
      // mix(white, (0.55, 0.55, 0.58), 0.45).
      expect(px.at(40, 5), _near([203, 203, 207, 255]));
      // x + y = 50, on a period edge: between stripes, still white.
      expect(px.at(44, 5), [255, 255, 255, 255]);
      expect(px.at(5, 5), [255, 0, 0, 255]);

      u
        ..highlightPalette = 0
        ..flashId = 2
        ..flashAmount = 1;
      px = await _render(renderer, u);
      expect(px.at(5, 5), [255, 0, 0, 255]); // correct: no stripes
      expect(px.at(40, 5), _near([199, 214, 235, 255])); // flash color

      u.stateTexture!.dispose();
      tearDownRenderer();
    });
  });

  testWidgets('flat renderer paints white plus filled bounding boxes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final flatMeta = PictureMeta.fromJson({
        'width': _w,
        'height': _h,
        'level': 'simple',
        'background': 1,
        'palette': ['#ff0000'],
        'regions': [
          {
            'id': 1,
            'palette': 0,
            'color': '#ff0000',
            'area': 100,
            'bbox': [10, 10, 10, 10],
            'label': [15, 15],
            'label_radius': 5.0,
          },
        ],
      });
      final u = FillUniforms()..fill = (FillState(1)..colors[1] = _red);
      final px = await _render(FlatFillRenderer(flatMeta), u);
      expect(px.at(15, 15), [255, 0, 0, 255]);
      expect(px.at(5, 5), [255, 255, 255, 255]);
    });
  });
}
