import 'dart:math';

/// The stamp outlines, centered on (0, 0) and fitting the unit circle (the
/// widest point touches it). y grows downwards, as on the canvas. The
/// renderer scales an outline by the stamp dab's radius, rotates it by the
/// dab's rotation and fills it.
enum StampShape {
  star,
  heart;

  /// Closed outline (the last point connects back to the first).
  List<Point<double>> get outline => switch (this) {
    star => _star,
    heart => _heart,
  };
}

/// Inner radius of the star relative to the outer one.
const double starInnerRadius = 0.45;

/// Points sampled along the heart outline.
const int heartOutlinePoints = 48;

final List<Point<double>> _star = List.unmodifiable([
  for (var i = 0; i < 10; i++)
    Point(
      (i.isEven ? 1.0 : starInnerRadius) * cos(-pi / 2 + i * pi / 5),
      (i.isEven ? 1.0 : starInnerRadius) * sin(-pi / 2 + i * pi / 5),
    ),
]);

final List<Point<double>> _heart = _buildHeart();

/// The classic parametric heart, x = 16 sin³t, y = 13 cos t − 5 cos 2t −
/// 2 cos 3t − cos 4t, flipped (y down), centered on its bounding box and
/// scaled so the farthest point is at distance 1.
List<Point<double>> _buildHeart() {
  final raw = <Point<double>>[
    for (var i = 0; i < heartOutlinePoints; i++)
      () {
        final t = 2 * pi * i / heartOutlinePoints;
        final s = sin(t);
        return Point(
          16 * s * s * s,
          -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)),
        );
      }(),
  ];
  final minY = raw.map((p) => p.y).reduce(min);
  final maxY = raw.map((p) => p.y).reduce(max);
  final cy = (minY + maxY) / 2;
  final centered = [for (final p in raw) Point(p.x, p.y - cy)];
  final reach = centered.map((p) => p.magnitude).reduce(max);
  return List.unmodifiable([
    for (final p in centered) Point(p.x / reach, p.y / reach),
  ]);
}
