import 'package:coloring/features/drawing/drawing_controller.dart';
import 'package:coloring/features/drawing/model/drawing_palette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('36 distinct opaque colors with black and white', () {
    expect(drawingPalette.length, 36);
    expect(drawingPalette.toSet().length, 36);
    expect(drawingPalette.every((c) => c >> 24 == 0xFF), isTrue);
    expect(drawingPalette, containsAll([0xFF000000, 0xFFFFFFFF]));
  });

  test('the default color is in the palette', () {
    expect(drawingPalette, contains(defaultDrawingColor));
  });
}
