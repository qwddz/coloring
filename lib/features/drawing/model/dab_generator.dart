import 'dart:math';

import 'brush_size.dart';
import 'drawing_tool.dart';
import 'stroke.dart';
import 'symmetry.dart';

/// Rainbow: degrees of hue per pixel of stroke length is `1 / this`.
const double rainbowPixelsPerDegree = 6;
const double rainbowSaturation = 0.85;
const double rainbowValue = 0.95;

/// The curve between two input points is walked in steps of at most this
/// many pixels.
const double _maxStep = 1;

/// Dabs are never closer than this, whatever the tool and size.
const double _minSpacing = 0.5;

/// Turns stroke points into dabs, incrementally and deterministically
/// (spec §5).
///
/// The path is smoothed with quadratic curves through the midpoints of the
/// input points (a straight line from the first point to the first midpoint
/// and from the last midpoint to the last point). Dabs sit at equal arc
/// length along it, the first one at the first point, so a tap is one dab
/// (or one stamp). Every random choice comes from `Random(seed)` in a fixed
/// order per dab, so feeding the points one by one ([add]) gives the same
/// dabs as [generate]. Airbrush dots appear only where the path moves.
///
/// A [mirrored] generator is fed mirrored points (see `mirror`) and negates
/// rotations and horizontal offsets, so its dabs are the exact mirror image
/// of the unmirrored copy with the same seed.
class DabGenerator {
  DabGenerator({
    required this.tool,
    required this.color,
    required this.size,
    required int seed,
    this.mirrored = false,
  }) : _random = Random(seed) {
    if (_spec.colorMode == BrushColorMode.rainbow) {
      _startHue = _random.nextDouble() * 360;
    }
  }

  /// A generator for one copy of [input]: the original, or with [mirrored]
  /// the mirror copy.
  factory DabGenerator.forInput(StrokeInput input, {bool mirrored = false}) =>
      DabGenerator(
        tool: input.tool,
        color: input.color,
        size: input.size,
        seed: input.seed,
        mirrored: mirrored,
      );

  /// All dabs of [input]: the original copy, then the mirror copy when
  /// [StrokeInput.symmetry] is on. Equal to feeding every point to [add]
  /// and calling [finish].
  static List<Dab> generate(StrokeInput input) {
    final copies = mirror(input.points, input.symmetry);
    final out = <Dab>[];
    for (var i = 0; i < copies.length; i++) {
      final g = DabGenerator.forInput(input, mirrored: i == 1);
      for (final p in copies[i]) {
        out.addAll(g.add(p));
      }
      out.addAll(g.finish());
    }
    return out;
  }

  final DrawingTool tool;
  final int color;
  final BrushSize size;
  final bool mirrored;
  final Random _random;

  BrushSpec get _spec => tool.spec;

  double _startHue = 0;
  int _count = 0;
  bool _finished = false;
  StrokePoint? _last;
  StrokePoint? _lastMid;

  /// Arc length of the walked path so far.
  double _arc = 0;

  /// Distance along the path until the next dab.
  double _untilNext = 0;

  /// Adds an input point; returns the dabs it completes. Ignored after
  /// [finish].
  List<Dab> add(StrokePoint p) {
    if (_finished || _spec.kind == BrushKind.fill) return const [];
    final out = <Dab>[];
    final last = _last;
    if (last == null) {
      _emit(out, p.x, p.y, p.pressure, 0);
    } else {
      final mid = _midpoint(last, p);
      final lastMid = _lastMid;
      if (lastMid == null) {
        _walkLine(out, last, mid);
      } else {
        _walkQuad(out, lastMid, last, mid);
      }
      _lastMid = mid;
    }
    _last = p;
    _count++;
    return out;
  }

  /// Ends the stroke: walks the rest of the path to the last point.
  List<Dab> finish() {
    if (_finished) return const [];
    _finished = true;
    final out = <Dab>[];
    final last = _last;
    final lastMid = _lastMid;
    if (_count >= 2 && last != null && lastMid != null) {
      _walkLine(out, lastMid, last);
    }
    return out;
  }

  static StrokePoint _midpoint(StrokePoint a, StrokePoint b) => StrokePoint(
    (a.x + b.x) / 2,
    (a.y + b.y) / 2,
    pressure: (a.pressure + b.pressure) / 2,
    tMillis: b.tMillis,
  );

  void _walkLine(List<Dab> out, StrokePoint a, StrokePoint b) {
    _walkSegment(out, a.x, a.y, a.pressure, b.x, b.y, b.pressure);
  }

  void _walkQuad(List<Dab> out, StrokePoint a, StrokePoint c, StrokePoint b) {
    final estimate =
        sqrt(_sq(c.x - a.x) + _sq(c.y - a.y)) +
        sqrt(_sq(b.x - c.x) + _sq(b.y - c.y));
    final steps = max(1, (estimate / _maxStep).ceil());
    var px = a.x;
    var py = a.y;
    var pp = a.pressure;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final u = 1 - t;
      final x = u * u * a.x + 2 * u * t * c.x + t * t * b.x;
      final y = u * u * a.y + 2 * u * t * c.y + t * t * b.y;
      final p = a.pressure + (b.pressure - a.pressure) * t;
      _walkSegment(out, px, py, pp, x, y, p);
      px = x;
      py = y;
      pp = p;
    }
  }

  void _walkSegment(
    List<Dab> out,
    double x0,
    double y0,
    double p0,
    double x1,
    double y1,
    double p1,
  ) {
    final length = sqrt(_sq(x1 - x0) + _sq(y1 - y0));
    var travelled = 0.0;
    while (length - travelled >= _untilNext) {
      travelled += _untilNext;
      final t = travelled / length;
      _emit(
        out,
        x0 + (x1 - x0) * t,
        y0 + (y1 - y0) * t,
        p0 + (p1 - p0) * t,
        _arc + travelled,
      );
    }
    _untilNext -= length - travelled;
    _arc += length;
  }

  /// Emits the dabs of one sample point and schedules the next one.
  void _emit(List<Dab> out, double x, double y, double pressure, double arc) {
    final spec = _spec;
    final baseRadius =
        size.width / 2 * spec.radiusFactor * spec.pressureScale(pressure);
    _untilNext = max(_minSpacing, spec.spacing * 2 * baseRadius);

    final sizeJitter = _jitter(spec.sizeJitter);
    final rotationJitter = _jitter(spec.rotationJitter);
    final variant = spec.spriteVariants > 1
        ? _random.nextInt(spec.spriteVariants)
        : 0;
    var dx = 0.0;
    var dy = 0.0;
    if (spec.scatter > 0) {
      final angle = _random.nextDouble() * 2 * pi;
      final dist = spec.scatter * baseRadius * sqrt(_random.nextDouble());
      dx = cos(angle) * dist;
      dy = sin(angle) * dist;
    }
    final radius = baseRadius * (1 + sizeJitter);
    final rotation = mirrored ? -rotationJitter : rotationJitter;
    if (mirrored) dx = -dx;
    final dabColor = switch (spec.colorMode) {
      BrushColorMode.selected => color,
      BrushColorMode.white => drawingWhite,
      BrushColorMode.rainbow => rainbowColor(
        _startHue + arc / rainbowPixelsPerDegree,
      ),
    };

    if (spec.sprayDensity > 0) {
      final pass = spec.passes.first;
      final dots = max(1, (spec.sprayDensity * radius).round());
      final dotRadius = max(1.0, spec.dotScale * radius);
      for (var i = 0; i < dots; i++) {
        final angle = _random.nextDouble() * 2 * pi;
        final dist = radius * sqrt(_random.nextDouble());
        final ox = cos(angle) * dist;
        out.add(
          Dab(
            x: x + dx + (mirrored ? -ox : ox),
            y: y + dy + sin(angle) * dist,
            radius: dotRadius * pass.radiusScale,
            color: mixWithWhite(dabColor, pass.tint),
            alpha: spec.dabAlpha * pass.alpha,
          ),
        );
      }
      return;
    }

    for (var i = 0; i < spec.passes.length; i++) {
      final pass = spec.passes[i];
      out.add(
        Dab(
          x: x + dx,
          y: y + dy,
          radius: radius * pass.radiusScale,
          rotation: rotation,
          color: mixWithWhite(dabColor, pass.tint),
          alpha: spec.dabAlpha * pass.alpha,
          pass: i,
          variant: variant,
        ),
      );
    }
  }

  double _jitter(double amount) =>
      amount == 0 ? 0 : (_random.nextDouble() * 2 - 1) * amount;

  static double _sq(double v) => v * v;
}

/// Opaque ARGB of [hue] degrees (any value, taken mod 360) at the rainbow
/// saturation and value.
int rainbowColor(double hue) =>
    hsvToArgb(hue % 360, rainbowSaturation, rainbowValue);

/// Opaque ARGB from HSV ([hue] 0..360, [saturation] and [value] 0..1).
int hsvToArgb(double hue, double saturation, double value) {
  final c = value * saturation;
  final h = (hue % 360) / 60;
  final x = c * (1 - (h % 2 - 1).abs());
  final (r, g, b) = switch (h.floor()) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  final m = value - c;
  int channel(double v) => ((v + m) * 255).round().clamp(0, 255);
  return 0xFF000000 | channel(r) << 16 | channel(g) << 8 | channel(b);
}

/// [argb] with each color channel moved [amount] (0..1) of the way to
/// white; alpha kept.
int mixWithWhite(int argb, double amount) {
  if (amount <= 0) return argb;
  int mix(int shift) {
    final c = (argb >> shift) & 0xFF;
    return (c + (255 - c) * amount).round().clamp(0, 255) << shift;
  }

  return (argb & 0xFF000000) | mix(16) | mix(8) | mix(0);
}
