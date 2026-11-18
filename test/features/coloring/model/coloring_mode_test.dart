import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('modes persist by name', () {
    for (final m in ColoringMode.values) {
      expect(ColoringMode.fromName(m.name), m);
    }
    expect(ColoringMode.values.map((m) => m.name), [
      'free',
      'numbers',
      'magic',
    ]);
  });

  test('unknown names give null', () {
    expect(ColoringMode.fromName('paint'), isNull);
    expect(ColoringMode.fromName(null), isNull);
    expect(ColoringMode.fromName(1), isNull);
  });
}
