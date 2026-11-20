import 'brush_size.dart';
import 'drawing_tool.dart';
import 'symmetry.dart';

/// One input sample in canvas pixels. [pressure] is 0..1 (touch and mouse
/// are 1.0, see [normalizePressure]); [tMillis] is the event time.
class StrokePoint {
  const StrokePoint(this.x, this.y, {this.pressure = 1, this.tMillis = 0});

  final double x;
  final double y;
  final double pressure;
  final int tMillis;

  @override
  bool operator ==(Object other) =>
      other is StrokePoint &&
      other.x == x &&
      other.y == y &&
      other.pressure == pressure &&
      other.tMillis == tMillis;

  @override
  int get hashCode => Object.hash(x, y, pressure, tMillis);

  @override
  String toString() => 'StrokePoint($x, $y, p: $pressure, t: $tMillis)';
}

/// Stylus pressure mapped to 0..1 over the device range [min]..[max]. An
/// empty or inverted range gives 1.
double normalizePressure(double pressure, double min, double max) {
  if (!(max > min)) return 1;
  return ((pressure - min) / (max - min)).clamp(0.0, 1.0);
}

/// Everything needed to (re)generate a stroke's dabs. [seed] drives every
/// random choice, so a replay produces the same dabs.
class StrokeInput {
  StrokeInput({
    required this.tool,
    required this.color,
    required this.size,
    required this.seed,
    required this.symmetry,
    required List<StrokePoint> points,
  }) : points = List.unmodifiable(points);

  final DrawingTool tool;

  /// ARGB, the selected color (ignored by the eraser and rainbow).
  final int color;
  final BrushSize size;
  final int seed;
  final SymmetryMode symmetry;
  final List<StrokePoint> points;
}

/// One sprite (or stamp) placement. [pass] indexes `BrushSpec.passes`;
/// [variant] is added to the pass sprite's cell (0 unless the tool has
/// `spriteVariants > 1`). [rotation] is in radians, [color] ARGB, [alpha]
/// 0..1.
class Dab {
  const Dab({
    required this.x,
    required this.y,
    required this.radius,
    required this.color,
    this.rotation = 0,
    this.alpha = 1,
    this.pass = 0,
    this.variant = 0,
  });

  final double x;
  final double y;
  final double radius;
  final double rotation;
  final int color;
  final double alpha;
  final int pass;
  final int variant;

  @override
  bool operator ==(Object other) =>
      other is Dab &&
      other.x == x &&
      other.y == y &&
      other.radius == radius &&
      other.rotation == rotation &&
      other.color == color &&
      other.alpha == alpha &&
      other.pass == pass &&
      other.variant == variant;

  @override
  int get hashCode =>
      Object.hash(x, y, radius, rotation, color, alpha, pass, variant);

  @override
  String toString() =>
      'Dab($x, $y, r: $radius, rot: $rotation, '
      'c: 0x${color.toRadixString(16)}, a: $alpha, pass: $pass, v: $variant)';
}
