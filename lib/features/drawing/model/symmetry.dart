import 'drawing_tool.dart';
import 'stroke.dart';

/// Mirror mode; persisted by [name]. v1 has left-right mirroring only.
enum SymmetryMode {
  off,
  vertical;

  /// The mode with [name], or null.
  static SymmetryMode? fromName(Object? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

/// [p] reflected across the vertical center line of a canvas [width] wide
/// (x ↦ width − x).
StrokePoint mirrorPoint(StrokePoint p, {int width = drawingCanvasWidth}) =>
    StrokePoint(width - p.x, p.y, pressure: p.pressure, tMillis: p.tMillis);

/// The point lists to draw for [points]: the points alone when [mode] is
/// off, plus their mirror image when vertical. The second copy is generated
/// with the same seed and `mirrored: true` (see `DabGenerator`).
List<List<StrokePoint>> mirror(
  List<StrokePoint> points,
  SymmetryMode mode, {
  int width = drawingCanvasWidth,
}) => switch (mode) {
  SymmetryMode.off => [points],
  SymmetryMode.vertical => [
    points,
    [for (final p in points) mirrorPoint(p, width: width)],
  ],
};
