import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('starts empty with N + 1 slots', () {
    final fill = FillState(5);
    expect(fill.colors, hasLength(6));
    expect(fill.regionCount, 5);
    expect(fill.filledCount, 0);
    expect(fill.filledFraction, 0);
    expect(fill.isFilled(1), isFalse);
    expect(fill.colorOf(1), 0);
    expect(fill.wasReset, isFalse);
  });

  test('filled count and fraction count regions, not area', () {
    final fill = FillState(5)
      ..setColor(1, red)
      ..setColor(5, blue);
    expect(fill.filledCount, 2);
    expect(fill.filledFraction, closeTo(0.4, 1e-12));
    expect(fill.isFilled(5), isTrue);
    expect(fill.colorOf(5), blue);
    fill.setColor(5, 0);
    expect(fill.filledCount, 1);
  });

  test('isCorrect compares with palette[paletteIndex]', () {
    final meta = fixtureMeta();
    final fill = FillState(5)
      ..setColor(1, red)
      ..setColor(2, red);
    expect(fill.isCorrect(1, meta), isTrue);
    expect(fill.isCorrect(2, meta), isFalse);
    expect(fill.isCorrect(3, meta), isFalse);
  });

  test('paletteProgress counts correct regions per palette index', () {
    final meta = fixtureMeta();
    // Index 0: regions 1, 4. Index 1: regions 2, 5. Index 2: region 3.
    final fill = FillState(5)
      ..setColor(1, red)
      ..setColor(4, green)
      ..setColor(2, green)
      ..setColor(5, green)
      ..setColor(3, base);
    expect(fill.paletteProgress(meta), const [
      PaletteProgress(1, 2),
      PaletteProgress(2, 2),
      PaletteProgress(0, 1),
    ]);
    expect(fill.paletteProgress(meta)[1].done, isTrue);
    expect(fill.paletteProgress(meta)[0].done, isFalse);
  });

  group('fromList / toList', () {
    test('round trip', () {
      final fill = FillState(5)
        ..setColor(2, green)
        ..setColor(3, base);
      final restored = FillState.fromList(fill.toList(), 5);
      expect(restored.colors, fill.colors);
      expect(restored.wasReset, isFalse);
    });

    test('a length mismatch resets to empty and sets the flag', () {
      final restored = FillState.fromList([0, red, red], 5);
      expect(restored.wasReset, isTrue);
      expect(restored.colors, hasLength(6));
      expect(restored.filledCount, 0);
    });

    test('an invalid color resets to empty and sets the flag', () {
      final restored = FillState.fromList([0, 0x00FF0000, 0, 0, 0, 0], 5);
      expect(restored.wasReset, isTrue);
      expect(restored.filledCount, 0);
      expect(FillState.fromList([0, -1, 0, 0, 0, 0], 5).wasReset, isTrue);
      expect(
        FillState.fromList([0, 0x1FFFFFFFF, 0, 0, 0, 0], 5).wasReset,
        isTrue,
      );
    });

    test('toList is a copy', () {
      final fill = FillState(2);
      final list = fill.toList()..[1] = red;
      expect(fill.colorOf(1), 0);
      expect(list[1], red);
    });
  });

  test('copy is independent', () {
    final fill = FillState(2)..setColor(1, red);
    final copy = fill.copy()..setColor(1, blue);
    expect(fill.colorOf(1), red);
    expect(copy.colorOf(1), blue);
  });
}
