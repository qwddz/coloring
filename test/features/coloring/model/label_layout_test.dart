import 'package:coloring/features/coloring/model/label_layout.dart';
import 'package:coloring/features/coloring/model/viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('labelVisible', () {
    test('threshold is 8 dp on screen', () {
      expect(labelVisible(16, 2), isTrue); // exactly 8 dp
      expect(labelVisible(15.9, 2), isFalse);
      expect(labelVisible(100, 2), isTrue);
    });
  });

  group('maxZoomFor', () {
    test('is the zoom that brings the smallest label to 8 dp', () {
      // 1 px at 1.25 dp/px is 1.25 dp at 1x: 8 / 1.25 = 6.4x.
      expect(maxZoomFor(1, 1.25), closeTo(6.4, 1e-9));
    });
    test('never goes below the default max zoom', () {
      expect(maxZoomFor(20, 1), defaultMaxZoom);
    });
    test('is capped at 8x', () {
      expect(labelMaxZoomCap, 8);
      expect(maxZoomFor(0.1, 0.5), labelMaxZoomCap);
    });
    test('invalid input gives the default', () {
      expect(maxZoomFor(0, 1), defaultMaxZoom);
      expect(maxZoomFor(-1, 1), defaultMaxZoom);
      expect(maxZoomFor(double.infinity, 1), defaultMaxZoom);
      expect(maxZoomFor(double.nan, 1), defaultMaxZoom);
      expect(maxZoomFor(1, 0), defaultMaxZoom);
    });
  });

  group('labelFontSize', () {
    test('is 0.9 of the on-screen radius inside the clamp', () {
      expect(labelFontSize(20, 1), closeTo(18, 1e-9));
    });
    test('clamps to 10..28', () {
      expect(labelFontSize(5, 1), 10);
      expect(labelFontSize(100, 1), 28);
    });
  });

  group('lineTolerance', () {
    test('is 8 dp in image px', () {
      expect(lineTolerance(2), 16);
    });
    test('clamps to 12..24', () {
      expect(lineTolerance(0.1), 12);
      expect(lineTolerance(1.5), 12);
      expect(lineTolerance(2.5), 20);
      expect(lineTolerance(10), 24);
    });
  });
}
