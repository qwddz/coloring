import 'package:coloring/features/coloring/model/label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('labelVisible', () {
    test('threshold is 10 dp on screen', () {
      expect(labelVisible(20, 2), isTrue); // exactly 10 dp
      expect(labelVisible(19.9, 2), isFalse);
      expect(labelVisible(100, 2), isTrue);
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
    test('is 6 dp in image px', () {
      expect(lineTolerance(1.5), 9);
    });
    test('clamps to 4..16', () {
      expect(lineTolerance(0.1), 4);
      expect(lineTolerance(1), 6);
      expect(lineTolerance(10), 16);
    });
  });
}
