import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:coloring/features/coloring/model/mode_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final meta = fixtureMeta();

  TapRule rule(
    ColoringMode mode, {
    ColoringTool tool = ColoringTool.brush,
    int region = 2,
    int color = base,
    int? index = 0,
  }) => tapRule(
    mode: mode,
    tool: tool,
    meta: meta,
    regionId: region,
    selectedColor: color,
    selectedPaletteIndex: index,
  );

  int? paintColor(TapRule r) => r is PaintRule ? r.color : null;

  group('tapRule', () {
    test('free paints the selected color; eraser paints 0', () {
      expect(paintColor(rule(ColoringMode.free)), base);
      expect(paintColor(rule(ColoringMode.free, tool: ColoringTool.eraser)), 0);
    });

    test('numbers paints the palette color only for the selected number', () {
      // Region 2 has palette index 1.
      expect(rule(ColoringMode.numbers, index: 0), isA<RejectRule>());
      expect(paintColor(rule(ColoringMode.numbers, index: 1)), green);
      expect(
        paintColor(
          rule(ColoringMode.numbers, tool: ColoringTool.eraser, index: 0),
        ),
        0,
      );
    });

    test('magic paints the correct color whatever is selected', () {
      expect(paintColor(rule(ColoringMode.magic, region: 3)), blue);
      expect(strokeColor(meta, 4), red);
    });
  });

  test('numbers shows a number until the region is correct (D1)', () {
    final fill = FillState(5)..setColor(1, base);
    expect(showsNumber(fill, meta, 1), isTrue);
    expect(showsNumber(fill, meta, 2), isTrue);
    fill.setColor(1, red);
    expect(showsNumber(fill, meta, 1), isFalse);
  });

  group('isComplete', () {
    test('free never completes on its own', () {
      final fill = FillState(5);
      for (var id = 1; id <= 5; id++) {
        fill.setColor(id, meta.correctColorOf(id));
      }
      expect(isComplete(ColoringMode.free, fill, meta), isFalse);
      expect(isComplete(ColoringMode.numbers, fill, meta), isTrue);
      expect(isComplete(ColoringMode.magic, fill, meta), isTrue);
    });

    test('numbers and magic both need every region correct (D1)', () {
      final fill = FillState(5);
      for (var id = 1; id <= 5; id++) {
        fill.setColor(id, base);
      }
      expect(isComplete(ColoringMode.numbers, fill, meta), isFalse);
      expect(isComplete(ColoringMode.magic, fill, meta), isFalse);
      for (var id = 1; id <= 4; id++) {
        fill.setColor(id, meta.correctColorOf(id));
      }
      expect(isComplete(ColoringMode.magic, fill, meta), isFalse);
      fill.setColor(5, meta.correctColorOf(5));
      expect(isComplete(ColoringMode.magic, fill, meta), isTrue);
    });
  });

  test('canFinish flips at exactly 80 % in free mode only', () {
    final fill = FillState(5);
    for (var id = 1; id <= 3; id++) {
      fill.setColor(id, base);
    }
    expect(canFinish(ColoringMode.free, fill), isFalse);
    fill.setColor(4, base);
    expect(canFinish(ColoringMode.free, fill), isTrue);
    expect(canFinish(ColoringMode.numbers, fill), isFalse);
    expect(canFinish(ColoringMode.magic, fill), isFalse);

    // 141 regions: 80 % lies between 112 and 113 filled.
    final big = FillState(141);
    for (var id = 1; id <= 112; id++) {
      big.setColor(id, base);
    }
    expect(canFinish(ColoringMode.free, big), isFalse); // 79.4 %
    big.setColor(113, base);
    expect(canFinish(ColoringMode.free, big), isTrue); // 80.1 %
  });

  test('firstIncompletePaletteIndex skips fully done colors', () {
    final fill = FillState(5);
    expect(firstIncompletePaletteIndex(fill, meta), 0);
    fill
      ..setColor(1, red)
      ..setColor(4, red);
    expect(firstIncompletePaletteIndex(fill, meta), 1);
    fill
      ..setColor(2, green)
      ..setColor(5, green);
    expect(firstIncompletePaletteIndex(fill, meta), 2);
    fill.setColor(3, blue);
    expect(firstIncompletePaletteIndex(fill, meta), 0);
  });
}
