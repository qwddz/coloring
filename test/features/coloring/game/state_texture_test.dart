import 'dart:ui' as ui;

import 'package:coloring/features/coloring/game/state_texture.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:coloring/features/coloring/model/picture_meta.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fixtures.dart';

Future<List<int>> _rgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('packs display colors and palette metadata in two rows', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final meta = PictureMeta.fromJson(fixtureJson());
      // Palette: 0 red, 1 green, 2 blue. Region palette index:
      // 1→0, 2→1, 3→2, 4→0, 5→1.
      final state = FillState.fromList([0, red, red, 0, base, green], 5);

      final texture = buildStateTexture(state, meta);
      addTearDown(texture.dispose);
      expect(texture.width, 6);
      expect(texture.height, 2);

      final px = await _rgba(texture);
      List<int> at(int x, int y) =>
          px.sublist((y * 6 + x) * 4, (y * 6 + x) * 4 + 4);

      // Row 0: display colors, white when unfilled.
      expect(at(1, 0), [255, 0, 0, 255]);
      expect(at(2, 0), [255, 0, 0, 255]);
      expect(at(3, 0), [255, 255, 255, 255]);
      expect(at(4, 0), [0x12, 0x34, 0x56, 255]);
      expect(at(5, 0), [0, 255, 0, 255]);

      // Row 1: R = palette index, G = 255 only when correct.
      expect(at(1, 1), [0, 255, 0, 255]); // red on palette 0: correct
      expect(at(2, 1), [1, 0, 0, 255]); // red on palette 1: wrong
      expect(at(3, 1), [2, 0, 0, 255]); // unfilled
      expect(at(4, 1), [0, 0, 0, 255]); // base color: wrong
      expect(at(5, 1), [1, 255, 0, 255]); // green on palette 1: correct

      for (var i = 3; i < px.length; i += 4) {
        expect(px[i], 255, reason: 'alpha at byte $i');
      }
    });
  });
}
