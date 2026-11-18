import 'dart:math' as math;

/// Timing of the canvas animations (spec §3, §4). Pure Dart, so the math is
/// unit-tested without Flame. Times are in seconds.

/// The fill wave grows over this time.
const double waveSeconds = 0.25;

/// One highlight pulse cycle.
const double pulseSeconds = 1.2;

/// The reject flash and the label wiggle.
const double flashSeconds = 0.3;

/// The free-mode long-press hint.
const double hintSeconds = 0.6;

/// Wave radius for an instant fill (reduced motion, hint). Huge but finite:
/// the shader compares distances against it.
const double instantRadius = 1e9;

/// Label wiggle amplitude (dp) and number of cycles in [flashSeconds].
const double wiggleAmplitudeDp = 3;
const int wiggleCycles = 3;

double easeOutCubic(double t) {
  final u = 1 - t.clamp(0.0, 1.0);
  return 1 - u * u * u;
}

/// Distance from ([x], [y]) to the farthest corner of the bbox: the radius
/// at which the wave covers the whole region.
double waveMaxRadius(
  double x,
  double y,
  int bboxX,
  int bboxY,
  int bboxWidth,
  int bboxHeight,
) {
  final dx = math.max((x - bboxX).abs(), (x - bboxX - bboxWidth).abs());
  final dy = math.max((y - bboxY).abs(), (y - bboxY - bboxHeight).abs());
  return math.sqrt(dx * dx + dy * dy);
}

/// Wave radius [elapsed] seconds after the tap: 0 → [maxRadius], ease-out.
double waveRadiusAt(double elapsed, double maxRadius) =>
    maxRadius * easeOutCubic(elapsed / waveSeconds);

/// Highlight pulse 0..1: `0.5 + 0.5·sin(2π·t / 1.2 s)`.
double pulseAt(double t) =>
    0.5 + 0.5 * math.sin(2 * math.pi * t / pulseSeconds);

/// Reject flash strength 0..1: a soft bump that is 0 at both ends.
double flashAmountAt(double elapsed) {
  if (elapsed <= 0 || elapsed >= flashSeconds) return 0;
  return math.sin(math.pi * elapsed / flashSeconds);
}

/// Horizontal label wiggle in dp: ±3 dp, 3 cycles over 300 ms.
double wiggleOffsetAt(double elapsed) {
  if (elapsed <= 0 || elapsed >= flashSeconds) return 0;
  return wiggleAmplitudeDp *
      math.sin(2 * math.pi * wiggleCycles * elapsed / flashSeconds);
}

/// One region drawn differently from the state texture: the fill wave
/// (old color outside a growing circle, new color inside) or the hint (the
/// whole region in the hint color for [hintSeconds]).
///
/// An instant wave (reduced motion) stays for exactly one frame: the first
/// [advance] after [startWave] keeps it, the next one ends it. Flame calls
/// update before render, so that frame is drawn with [instantRadius].
class WaveAnimation {
  /// 0 = none.
  int regionId = 0;
  double x = 0;
  double y = 0;
  int oldColor = 0;
  int newColor = 0;

  double _maxRadius = 0;
  double _elapsed = 0;
  double _duration = 0;
  bool _grows = false;
  bool _shown = false;

  bool get active => regionId != 0;

  /// Current radius in image px.
  double get radius =>
      _grows ? waveRadiusAt(_elapsed, _maxRadius) : instantRadius;

  void startWave({
    required int regionId,
    required double x,
    required double y,
    required double maxRadius,
    required int oldColor,
    required int newColor,
    required bool instant,
  }) {
    _start(regionId, oldColor, newColor);
    this.x = x;
    this.y = y;
    _maxRadius = maxRadius;
    _grows = !instant;
    _duration = instant ? 0 : waveSeconds;
  }

  void startHint({
    required int regionId,
    required int oldColor,
    required int color,
  }) {
    _start(regionId, oldColor, color);
    _grows = false;
    _duration = hintSeconds;
  }

  void _start(int id, int oldColor, int newColor) {
    regionId = id;
    this.oldColor = oldColor;
    this.newColor = newColor;
    _elapsed = 0;
    _shown = false;
  }

  void stop() => regionId = 0;

  void advance(double dt) {
    if (!active) return;
    if (_duration == 0) {
      if (_shown) stop();
      _shown = true;
      return;
    }
    _elapsed += dt;
    if (_elapsed >= _duration) stop();
  }
}

/// The numbers-mode reject flash plus the wiggle of that region's label.
class FlashAnimation {
  /// 0 = none.
  int regionId = 0;
  double _elapsed = 0;

  bool get active => regionId != 0;
  double get amount => active ? flashAmountAt(_elapsed) : 0;
  double get wiggleDp => active ? wiggleOffsetAt(_elapsed) : 0;

  void start(int id) {
    regionId = id;
    _elapsed = 0;
  }

  void advance(double dt) {
    if (!active) return;
    _elapsed += dt;
    if (_elapsed >= flashSeconds) regionId = 0;
  }
}
