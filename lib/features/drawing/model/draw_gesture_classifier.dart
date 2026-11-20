import 'dart:math';

/// A touch stroke shorter than this path (dp) or younger than
/// [shortStrokeAge] when a second finger lands is discarded, not committed.
const double shortStrokeDp = 10;
const Duration shortStrokeAge = Duration(milliseconds: 250);

/// A fill fires on lift only when the pointer stayed within this distance.
const double fillSlopDp = 10;

/// Touches that land while a stylus is down, or up to this long after it
/// lifted, are palms and ignored for their whole contact.
const Duration palmWindow = Duration(milliseconds: 300);

/// Input device of a pointer. An inverted stylus erases; a mouse behaves
/// like touch.
enum PointerKind {
  touch,
  stylus,
  invertedStylus,
  mouse;

  bool get isStylus => this == stylus || this == invertedStylus;
}

sealed class DrawGesture {
  const DrawGesture();
}

/// A stroke starts at [position] (dp). [pressure] is 0..1 (1 for touch and
/// mouse). An [kind] of [PointerKind.invertedStylus] draws with the eraser.
class StrokeBegin extends DrawGesture {
  const StrokeBegin(this.position, this.pressure, this.time, this.kind);
  final Point<double> position;
  final double pressure;
  final Duration time;
  final PointerKind kind;

  bool get erases => kind == PointerKind.invertedStylus;
}

class StrokeAdd extends DrawGesture {
  const StrokeAdd(this.position, this.pressure, this.time);
  final Point<double> position;
  final double pressure;
  final Duration time;
}

/// The live stroke is committed.
class StrokeEnd extends DrawGesture {
  const StrokeEnd();
}

/// The live stroke (dabs and stamps) vanishes; no op is recorded.
class StrokeDiscard extends DrawGesture {
  const StrokeDiscard();
}

/// Fill at [position] (dp), where the pointer went down.
class FillTap extends DrawGesture {
  const FillTap(this.position);
  final Point<double> position;
}

class ScaleStart extends DrawGesture {
  const ScaleStart(this.focal);
  final Point<double> focal;
}

/// [scaleFactor] is relative to the start of the scale gesture; [panDelta] is
/// the focal point movement since the previous update.
class ScaleUpdate extends DrawGesture {
  const ScaleUpdate(this.focal, this.scaleFactor, this.panDelta);
  final Point<double> focal;
  final double scaleFactor;
  final Point<double> panDelta;
}

class ScaleEnd extends DrawGesture {
  const ScaleEnd();
}

enum _Mode { none, stroke, fill, scale }

/// Turns raw pointer events into drawing gestures (spec §7). Pure: time is
/// passed in. Unlike the coloring `TouchClassifier`, a stroke starts on the
/// first contact; a second finger turns a short stroke into nothing and a
/// longer one into a committed stroke, then zooms. A stylus never zooms,
/// beats touch, and makes touches near it (palms) ignored.
class DrawGestureClassifier {
  /// The fill tool is selected: a contact taps instead of drawing (an
  /// inverted stylus still erases).
  bool fillMode = false;

  _Mode _mode = _Mode.none;
  int _owner = -1;

  /// Tracked (not ignored) pointers.
  final Map<int, Point<double>> _pos = {};
  final Map<int, PointerKind> _kinds = {};

  /// Pointers ignored until they lift.
  final Set<int> _ignored = {};

  /// Touch / mouse pointers down, tracked or ignored.
  final Set<int> _touches = {};

  /// Stylus pointers down, tracked or ignored.
  final Set<int> _styluses = {};
  Duration? _stylusUpAt;

  /// After a scale, new touches are ignored until every touch has lifted.
  bool _touchLock = false;

  // Stroke.
  Duration _strokeStart = Duration.zero;
  double _strokePath = 0;

  // Fill.
  Point<double> _fillDown = const Point(0, 0);
  double _fillMoved = 0;

  // Scale.
  int _b = -1;
  double _startDistance = 1;
  Point<double> _lastFocal = const Point(0, 0);

  List<DrawGesture> pointerDown(
    int id,
    PointerKind kind,
    Point<double> position,
    double pressure,
    Duration now,
  ) {
    if (kind.isStylus) return _stylusDown(id, kind, position, pressure, now);
    _touches.add(id);
    final upAt = _stylusUpAt;
    final palm =
        _styluses.isNotEmpty || (upAt != null && now - upAt <= palmWindow);
    if (palm || _touchLock) {
      _ignored.add(id);
      return const [];
    }
    switch (_mode) {
      case _Mode.none:
        return _begin(id, kind, position, pressure, now);
      case _Mode.stroke:
        final short =
            _strokePath < shortStrokeDp || now - _strokeStart < shortStrokeAge;
        _track(id, kind, position);
        return [
          short ? const StrokeDiscard() : const StrokeEnd(),
          _startScale(id),
        ];
      case _Mode.fill:
        _track(id, kind, position);
        return [_startScale(id)];
      case _Mode.scale:
        _ignored.add(id);
        return const [];
    }
  }

  List<DrawGesture> pointerMove(
    int id,
    Point<double> position,
    double pressure,
    Duration now,
  ) {
    if (!_pos.containsKey(id)) return const [];
    final previous = _pos[id]!;
    _pos[id] = position;
    switch (_mode) {
      case _Mode.stroke when id == _owner:
        _strokePath += previous.distanceTo(position);
        return [StrokeAdd(position, _pressure(id, pressure), now)];
      case _Mode.fill when id == _owner:
        _fillMoved = max(_fillMoved, _fillDown.distanceTo(position));
        return const [];
      case _Mode.scale when id == _owner || id == _b:
        final focal = _focal();
        final update = ScaleUpdate(
          focal,
          _distance() / _startDistance,
          focal - _lastFocal,
        );
        _lastFocal = focal;
        return [update];
      default:
        return const [];
    }
  }

  List<DrawGesture> pointerUp(int id, Point<double> position, Duration now) {
    final out = <DrawGesture>[];
    if (_pos.containsKey(id)) {
      _pos[id] = position;
      switch (_mode) {
        case _Mode.stroke when id == _owner:
          out.add(const StrokeEnd());
          _mode = _Mode.none;
        case _Mode.fill when id == _owner:
          _fillMoved = max(_fillMoved, _fillDown.distanceTo(position));
          if (_fillMoved < fillSlopDp) out.add(FillTap(_fillDown));
          _mode = _Mode.none;
        case _Mode.scale when id == _owner || id == _b:
          out.add(_endScale());
        default:
          break;
      }
    }
    _release(id, now);
    return out;
  }

  /// A cancelled drawing pointer commits its stroke; a cancelled fill
  /// pointer does nothing; a cancelled scale pointer ends the scale.
  List<DrawGesture> pointerCancel(int id, Duration now) {
    final out = <DrawGesture>[];
    if (_pos.containsKey(id)) {
      switch (_mode) {
        case _Mode.stroke when id == _owner:
          out.add(const StrokeEnd());
          _mode = _Mode.none;
        case _Mode.fill when id == _owner:
          _mode = _Mode.none;
        case _Mode.scale when id == _owner || id == _b:
          out.add(_endScale());
        default:
          break;
      }
    }
    _release(id, now);
    return out;
  }

  List<DrawGesture> _stylusDown(
    int id,
    PointerKind kind,
    Point<double> position,
    double pressure,
    Duration now,
  ) {
    final second = _styluses.isNotEmpty;
    _styluses.add(id);
    if (second) {
      _ignored.add(id);
      return const [];
    }
    final out = <DrawGesture>[];
    switch (_mode) {
      case _Mode.stroke:
        out.add(const StrokeDiscard());
      case _Mode.scale:
        out.add(const ScaleEnd());
      case _Mode.fill || _Mode.none:
        break;
    }
    // Every touch down now is ignored until it lifts.
    for (final t in _touches) {
      _ignored.add(t);
      _pos.remove(t);
      _kinds.remove(t);
    }
    _mode = _Mode.none;
    out.addAll(_begin(id, kind, position, pressure, now));
    return out;
  }

  List<DrawGesture> _begin(
    int id,
    PointerKind kind,
    Point<double> position,
    double pressure,
    Duration now,
  ) {
    _track(id, kind, position);
    _owner = id;
    if (fillMode && kind != PointerKind.invertedStylus) {
      _mode = _Mode.fill;
      _fillDown = position;
      _fillMoved = 0;
      return const [];
    }
    _mode = _Mode.stroke;
    _strokeStart = now;
    _strokePath = 0;
    return [StrokeBegin(position, _pressure(id, pressure), now, kind)];
  }

  void _track(int id, PointerKind kind, Point<double> position) {
    _pos[id] = position;
    _kinds[id] = kind;
  }

  ScaleStart _startScale(int id) {
    _mode = _Mode.scale;
    _b = id;
    _startDistance = max(_distance(), 1e-6);
    _lastFocal = _focal();
    return ScaleStart(_lastFocal);
  }

  /// Ends the scale; the touches still down are ignored until all lift.
  ScaleEnd _endScale() {
    _mode = _Mode.none;
    for (final t in _touches) {
      _ignored.add(t);
      _pos.remove(t);
      _kinds.remove(t);
    }
    _touchLock = true;
    return const ScaleEnd();
  }

  void _release(int id, Duration now) {
    _pos.remove(id);
    _kinds.remove(id);
    _ignored.remove(id);
    _touches.remove(id);
    if (_styluses.remove(id) && _styluses.isEmpty) _stylusUpAt = now;
    if (_touches.isEmpty) _touchLock = false;
  }

  double _pressure(int id, double pressure) =>
      _kinds[id]!.isStylus ? pressure.clamp(0.0, 1.0) : 1.0;

  double _distance() => _pos[_owner]!.distanceTo(_pos[_b]!);

  Point<double> _focal() {
    final p = _pos[_owner]!;
    final q = _pos[_b]!;
    return Point((p.x + q.x) / 2, (p.y + q.y) / 2);
  }
}
