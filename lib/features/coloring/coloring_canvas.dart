import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart' hide Viewport;

import 'game/coloring_game.dart';
import 'model/label_layout.dart';
import 'model/touch_classifier.dart';
import 'model/viewport.dart';
import 'perf/fill_latency_probe.dart';

/// A touch on the picture: image point plus the line tolerance for the
/// lookup (image px, from [lineTolerance] at the current zoom).
typedef CanvasPointCallback = void Function(
  double imageX,
  double imageY,
  double tolerance,
);

enum _Drag { none, stroke, pan }

/// At 1× outside magic mode a one-finger drag has nothing to do, so a finger
/// that wobbles past [tapSlopDp] but stays within this distance of where it
/// went down still taps there.
const double wobbleTapDp = 24;

/// The [ColoringGame] with touch input (spec §4, A3): raw pointers go
/// through [TouchClassifier]; taps, long presses and magic-brush strokes are
/// reported through the callbacks, pinch and pan move the game's viewport.
///
/// - Two fingers always zoom (1×–4×) and pan.
/// - One finger drags the picture when zoomed in, unless [brushDrags]
///   (magic mode), where it paints a stroke at any zoom. At 1× without
///   [brushDrags] a drag that stays within [wobbleTapDp] of its start is a
///   tap there; a longer one does nothing.
/// - A held finger reports [onLongPress] at 500 ms when that callback is set
///   (and not [brushDrags]); without it, holding and lifting is a tap.
/// - A second finger ends a running stroke through [onStrokeEnd]. So does a
///   cancelled pointer (the system took the touch): the regions already
///   painted stay and the stroke is committed, never left open.
class ColoringCanvas extends StatefulWidget {
  const ColoringCanvas({
    super.key,
    required this.game,
    this.brushDrags = false,
    this.onTap,
    this.onLongPress,
    this.onStrokeStart,
    this.onStrokeUpdate,
    this.onStrokeEnd,
    this.latencyProbe,
  });

  final ColoringGame game;
  final bool brushDrags;
  final CanvasPointCallback? onTap;
  final CanvasPointCallback? onLongPress;
  final CanvasPointCallback? onStrokeStart;
  final CanvasPointCallback? onStrokeUpdate;
  final CanvasPointCallback? onStrokeEnd;

  /// Defaults to a new probe when [FillLatencyProbe.enabled], else none.
  final FillLatencyProbe? latencyProbe;

  @override
  State<ColoringCanvas> createState() => _ColoringCanvasState();
}

class _ColoringCanvasState extends State<ColoringCanvas> {
  final _classifier = TouchClassifier();
  final _pointers = <int>{};
  Timer? _longPressTimer;
  Duration _downAt = Duration.zero;
  _Drag _drag = _Drag.none;
  Point<double>? _wobbleFrom;
  bool _longPressed = false;
  double _wobbleFar = 0;
  Viewport? _scaleStart;
  late final FillLatencyProbe? _probe =
      widget.latencyProbe ??
      (FillLatencyProbe.enabled ? FillLatencyProbe() : null);

  ColoringGame get _game => widget.game;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _probe?.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent e) {
    final first = _pointers.isEmpty;
    _pointers.add(e.pointer);
    _longPressTimer?.cancel();
    // A finger takes the view back from a running "find" move and blocks
    // new ones until it lifts.
    _game.gestureActive = true;
    // Magic mode has no long press: a held finger only waits for its stroke.
    if (first) _longPressed = false;
    if (first && !widget.brushDrags && widget.onLongPress != null) {
      _downAt = e.timeStamp;
      // The classifier needs time to pass without events for a long press.
      _longPressTimer = Timer(
        longPressDuration,
        () => _handle(_classifier.tick(_downAt + longPressDuration)),
      );
    }
    _handle(_classifier.pointerDown(e.pointer, _point(e), e.timeStamp));
  }

  void _onMove(PointerMoveEvent e) =>
      _handle(_classifier.pointerMove(e.pointer, _point(e), e.timeStamp));

  void _onUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    _game.gestureActive = _pointers.isNotEmpty;
    _longPressTimer?.cancel();
    _handle(
      _classifier.pointerUp(e.pointer, _point(e), e.timeStamp),
      upStamp: e.timeStamp,
    );
  }

  /// Drops only the cancelled pointer. If it was drawing, the classifier
  /// ends the drag and the open stroke is committed at its last point, so
  /// the controller never keeps a stroke running.
  void _onCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    _game.gestureActive = _pointers.isNotEmpty;
    _longPressTimer?.cancel();
    _handle(_classifier.pointerCancel(e.pointer));
  }

  static Point<double> _point(PointerEvent e) =>
      Point(e.localPosition.dx, e.localPosition.dy);

  void _handle(List<TouchGesture> gestures, {Duration? upStamp}) {
    for (final g in gestures) {
      switch (g) {
        case Tap(:final position):
          _tap(position, upStamp);
        case LongPress(:final position):
          _longPressed = true;
          _emit(widget.onLongPress, position);
        case DragStart(:final position):
          final zoomed = (_game.viewport?.zoom ?? minZoom) > minZoom;
          _drag = widget.brushDrags
              ? _Drag.stroke
              : zoomed
              ? _Drag.pan
              : _Drag.none;
          if (_drag == _Drag.stroke) _emit(widget.onStrokeStart, position);
          // A finger that already showed a hint never taps.
          _wobbleFrom = _drag == _Drag.none && !_longPressed ? position : null;
          _wobbleFar = 0;
        case DragUpdate(:final position, :final delta):
          switch (_drag) {
            case _Drag.stroke:
              _emit(widget.onStrokeUpdate, position);
            case _Drag.pan:
              final v = _game.viewport;
              if (v != null) _game.viewport = v.panBy(delta);
            case _Drag.none:
              final from = _wobbleFrom;
              if (from != null) {
                _wobbleFar = max(_wobbleFar, position.distanceTo(from));
              }
          }
        case DragEnd(:final position):
          if (_drag == _Drag.stroke) _emit(widget.onStrokeEnd, position);
          // Only a lifted finger taps: a drag ended by a second finger or a
          // cancel has no up stamp.
          final from = _wobbleFrom;
          if (_drag == _Drag.none &&
              from != null &&
              upStamp != null &&
              max(_wobbleFar, position.distanceTo(from)) <= wobbleTapDp) {
            _tap(from, upStamp);
          }
          _wobbleFrom = null;
          _drag = _Drag.none;
        case ScaleStart():
          _scaleStart = _game.viewport;
        case ScaleUpdate(:final focal, :final scaleFactor, :final panDelta):
          final start = _scaleStart;
          final v = _game.viewport;
          if (start == null || v == null) break;
          // Zoom around the previous focal point, then follow the fingers,
          // so the image point under them stays under them.
          final previous = focal - panDelta;
          _game.viewport = v
              .zoomAt(previous, start.zoom * scaleFactor / v.zoom)
              .panBy(panDelta);
        case ScaleEnd():
          _scaleStart = null;
      }
    }
  }

  void _tap(Point<double> position, Duration? upStamp) {
    final probe = _probe;
    if (probe == null || upStamp == null) {
      _emit(widget.onTap, position);
      return;
    }
    probe.tapUp(upStamp);
    final watch = Stopwatch()..start();
    _emit(widget.onTap, position);
    probe.fillApplied(watch.elapsed);
  }

  void _emit(CanvasPointCallback? callback, Point<double> screen) {
    final v = _game.viewport;
    if (callback == null || v == null) return;
    final p = v.screenToImage(screen);
    callback(p.x, p.y, lineTolerance(v.imagePxPerDp).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: GameWidget(key: ObjectKey(_game), game: _game),
      ),
    );
  }
}
