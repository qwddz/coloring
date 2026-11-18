import 'dart:math';

const Duration tapMaxDuration = Duration(milliseconds: 300);
const Duration longPressDuration = Duration(milliseconds: 500);
const double tapSlopDp = 10;

sealed class TouchGesture {
  const TouchGesture();
}

class Tap extends TouchGesture {
  const Tap(this.position);
  final Point<double> position;
}

class LongPress extends TouchGesture {
  const LongPress(this.position);
  final Point<double> position;
}

class DragStart extends TouchGesture {
  const DragStart(this.position);
  final Point<double> position;
}

class DragUpdate extends TouchGesture {
  const DragUpdate(this.position, this.delta);
  final Point<double> position;
  final Point<double> delta;
}

class DragEnd extends TouchGesture {
  const DragEnd(this.position);
  final Point<double> position;
}

class ScaleStart extends TouchGesture {
  const ScaleStart(this.focal);
  final Point<double> focal;
}

/// [scaleFactor] is relative to the start of the scale gesture; [panDelta] is
/// the focal point movement since the previous update.
class ScaleUpdate extends TouchGesture {
  const ScaleUpdate(this.focal, this.scaleFactor, this.panDelta);
  final Point<double> focal;
  final double scaleFactor;
  final Point<double> panDelta;
}

class ScaleEnd extends TouchGesture {
  const ScaleEnd();
}

enum _Phase { idle, pending, longPressed, dragging, scaling, ignoring }

/// Turns raw pointer events into gestures. Pure: time is passed in. Long press
/// needs time to pass without events, so call [tick] (e.g. from a Timer).
/// A cancelled pointer is dropped alone: it never taps, and it ends the drag
/// or scale it belonged to (see [pointerCancel]).
class TouchClassifier {
  final Map<int, Point<double>> _pos = {};
  _Phase _phase = _Phase.idle;
  int _primary = -1;
  Point<double> _start = const Point(0, 0);
  Duration _downAt = Duration.zero;
  int? _a;
  int? _b;
  double _startDistance = 1;
  Point<double> _lastFocal = const Point(0, 0);

  List<TouchGesture> pointerDown(int id, Point<double> position, Duration now) {
    _pos[id] = position;
    switch (_phase) {
      case _Phase.idle:
        _phase = _Phase.pending;
        _primary = id;
        _start = position;
        _downAt = now;
        return const [];
      case _Phase.pending || _Phase.longPressed || _Phase.dragging:
        final out = <TouchGesture>[];
        if (_phase == _Phase.dragging) {
          out.add(DragEnd(_pos[_primary]!));
        }
        _a = _primary;
        _b = id;
        _phase = _Phase.scaling;
        _startDistance = max(_distance(), 1e-6);
        _lastFocal = _focal();
        out.add(ScaleStart(_lastFocal));
        return out;
      case _Phase.scaling || _Phase.ignoring:
        return const [];
    }
  }

  List<TouchGesture> pointerMove(int id, Point<double> position, Duration now) {
    if (!_pos.containsKey(id)) return const [];
    _pos[id] = position;
    switch (_phase) {
      // After a long press, moving past the slop still turns into a drag
      // (a held finger that starts a magic stroke or a pan).
      case _Phase.pending || _Phase.longPressed:
        if (id != _primary || _dist(position, _start) < tapSlopDp) {
          return const [];
        }
        _phase = _Phase.dragging;
        final out = [
          DragStart(_start),
          DragUpdate(position, position - _start),
        ];
        _start = position;
        return out;
      case _Phase.dragging:
        if (id != _primary) return const [];
        // _start holds the previous drag position.
        final delta = position - _start;
        _start = position;
        return [DragUpdate(position, delta)];
      case _Phase.scaling:
        if (id != _a && id != _b) return const [];
        final focal = _focal();
        final update = ScaleUpdate(
          focal,
          _distance() / _startDistance,
          focal - _lastFocal,
        );
        _lastFocal = focal;
        return [update];
      case _Phase.idle || _Phase.ignoring:
        return const [];
    }
  }

  List<TouchGesture> pointerUp(int id, Point<double> position, Duration now) {
    if (!_pos.containsKey(id)) return const [];
    _pos[id] = position;
    final out = <TouchGesture>[];
    switch (_phase) {
      case _Phase.pending:
        if (id == _primary && now - _downAt < tapMaxDuration) {
          out.add(Tap(position));
        }
        _phase = _Phase.idle;
      case _Phase.longPressed:
        _phase = _Phase.idle;
      case _Phase.dragging:
        if (id == _primary) {
          out.add(DragEnd(position));
          _phase = _Phase.idle;
        }
      case _Phase.scaling:
        if (id == _a || id == _b) {
          out.add(const ScaleEnd());
          _phase = _Phase.ignoring;
        }
      case _Phase.idle || _Phase.ignoring:
        break;
    }
    _pos.remove(id);
    if (_pos.isEmpty) _phase = _Phase.idle;
    return out;
  }

  /// Drops only [id]. A cancelled pointer never taps or long-presses; if it
  /// was dragging or scaling, that gesture ends ([DragEnd] at its last
  /// position, or [ScaleEnd]) and the remaining fingers are ignored until
  /// all are up.
  List<TouchGesture> pointerCancel(int id) {
    final last = _pos.remove(id);
    if (last == null) return const [];
    final out = <TouchGesture>[];
    switch (_phase) {
      case _Phase.pending || _Phase.longPressed:
        if (id == _primary) _phase = _Phase.ignoring;
      case _Phase.dragging:
        if (id == _primary) {
          out.add(DragEnd(last));
          _phase = _Phase.ignoring;
        }
      case _Phase.scaling:
        if (id == _a || id == _b) {
          out.add(const ScaleEnd());
          _phase = _Phase.ignoring;
        }
      case _Phase.idle || _Phase.ignoring:
        break;
    }
    if (_pos.isEmpty) _phase = _Phase.idle;
    return out;
  }

  /// Emits [LongPress] once when the held pointer reaches 500 ms.
  List<TouchGesture> tick(Duration now) {
    if (_phase != _Phase.pending || now - _downAt < longPressDuration) {
      return const [];
    }
    _phase = _Phase.longPressed;
    return [LongPress(_pos[_primary]!)];
  }

  double _distance() => _dist(_pos[_a]!, _pos[_b]!);

  Point<double> _focal() {
    final p = _pos[_a]!;
    final q = _pos[_b]!;
    return Point((p.x + q.x) / 2, (p.y + q.y) / 2);
  }

  static double _dist(Point<double> p, Point<double> q) => p.distanceTo(q);
}
