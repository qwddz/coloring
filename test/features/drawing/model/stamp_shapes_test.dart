import 'dart:math';

import 'package:coloring/features/drawing/model/stamp_shapes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Signed area of a closed polygon (shoelace).
double area(List<Point<double>> pts) {
  var sum = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum / 2;
}

/// Every point has a mirror partner across x = 0.
void expectLeftRightSymmetric(List<Point<double>> pts) {
  for (final p in pts) {
    final partner = pts.any(
      (q) => (q.x + p.x).abs() < 1e-9 && (q.y - p.y).abs() < 1e-9,
    );
    expect(partner, isTrue, reason: '$p');
  }
}

void main() {
  test('star: 10 points alternating outer 1 and inner radius, top up', () {
    final pts = StampShape.star.outline;
    expect(pts, hasLength(10));
    for (var i = 0; i < pts.length; i++) {
      expect(pts[i].magnitude, closeTo(i.isEven ? 1 : starInnerRadius, 1e-9));
    }
    expect(pts.first.x, closeTo(0, 1e-9));
    expect(pts.first.y, closeTo(-1, 1e-9), reason: 'tip points up (y down)');
    expectLeftRightSymmetric(pts);
    expect(area(pts).abs(), greaterThan(0.5));
  });

  test('heart: fits the unit circle, symmetric, lobes up, tip down', () {
    final pts = StampShape.heart.outline;
    expect(pts, hasLength(heartOutlinePoints));
    final reach = pts.map((p) => p.magnitude).reduce(max);
    expect(reach, closeTo(1, 1e-9));
    expectLeftRightSymmetric(pts);
    final minY = pts.map((p) => p.y).reduce(min);
    final maxY = pts.map((p) => p.y).reduce(max);
    expect(minY + maxY, closeTo(0, 1e-9), reason: 'centered vertically');
    // The tip (x = 0, lowest point on screen) is at the bottom.
    final tip = pts.reduce((a, b) => a.y > b.y ? a : b);
    expect(tip.x, closeTo(0, 1e-9));
    // The cleft between the lobes is above the center at x = 0.
    final cleft = pts.firstWhere((p) => p.x.abs() < 1e-9 && p != tip);
    expect(cleft.y, lessThan(0));
    expect(area(pts).abs(), greaterThan(1));
  });

  test('outlines are fixed lists', () {
    expect(identical(StampShape.star.outline, StampShape.star.outline), isTrue);
    expect(
      () => StampShape.heart.outline.add(const Point(0, 0)),
      throwsUnsupportedError,
    );
  });
}
