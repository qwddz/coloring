import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/drawing/model/stroke.dart';
import 'package:coloring/features/drawing/model/symmetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const points = [
    StrokePoint(10, 20, pressure: 0.5, tMillis: 1),
    StrokePoint(1024, 30, pressure: 1, tMillis: 2),
    StrokePoint(2000, 1500, pressure: 0.2, tMillis: 3),
  ];

  test('off draws the points alone', () {
    final copies = mirror(points, SymmetryMode.off);
    expect(copies, hasLength(1));
    expect(copies.single, points);
  });

  test('vertical adds the left-right mirror image', () {
    final copies = mirror(points, SymmetryMode.vertical);
    expect(copies, hasLength(2));
    expect(copies.first, points);
    expect(copies.last, const [
      StrokePoint(drawingCanvasWidth - 10.0, 20, pressure: 0.5, tMillis: 1),
      StrokePoint(1024, 30, pressure: 1, tMillis: 2),
      StrokePoint(48, 1500, pressure: 0.2, tMillis: 3),
    ]);
  });

  test('mirroring twice gives the original; width is configurable', () {
    for (final p in points) {
      expect(mirrorPoint(mirrorPoint(p)), p);
    }
    expect(mirrorPoint(points.first, width: 100).x, 90);
  });

  test('modes round-trip by name', () {
    for (final m in SymmetryMode.values) {
      expect(SymmetryMode.fromName(m.name), m);
    }
    expect(SymmetryMode.fromName('quad'), isNull);
    expect(SymmetryMode.fromName(null), isNull);
  });
}
