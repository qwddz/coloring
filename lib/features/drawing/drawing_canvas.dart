import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' hide Viewport;

import '../coloring/model/viewport.dart';
import 'live_stroke.dart';
import 'model/draw_gesture_classifier.dart';
import 'model/stroke.dart';
import 'render/raster_engine.dart';

/// The drawing sheet (spec §7): raw pointers go through a
/// [DrawGestureClassifier]; strokes and fill taps are reported in canvas
/// pixels, two-finger zoom and pan move the view. Paints the committed
/// image of [engine] with [live] on top.
class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    required this.engine,
    required this.live,
    required this.fillMode,
    required this.onStrokeBegin,
    required this.onStrokeAdd,
    required this.onStrokeEnd,
    required this.onStrokeDiscard,
    required this.onFill,
    super.key,
  });

  final RasterEngine engine;
  final LiveStroke live;

  /// The fill tool is selected: a contact taps instead of drawing.
  final bool fillMode;

  /// [erases] is set for an inverted stylus.
  final void Function(StrokePoint point, bool erases) onStrokeBegin;
  final ValueChanged<StrokePoint> onStrokeAdd;
  final VoidCallback onStrokeEnd;
  final VoidCallback onStrokeDiscard;

  /// A fill tap at canvas pixel ([x], [y]).
  final void Function(double x, double y) onFill;

  @override
  State<DrawingCanvas> createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  final _classifier = DrawGestureClassifier();
  Viewport? _viewport;
  double _scaleStartZoom = 1;

  /// The current view; null before the first layout.
  @visibleForTesting
  Viewport? get viewport => _viewport;

  Viewport _viewportFor(Size size) {
    final current = _viewport;
    if (current != null &&
        current.canvasWidth == size.width &&
        current.canvasHeight == size.height &&
        current.imageWidth == widget.engine.width &&
        current.imageHeight == widget.engine.height) {
      return current;
    }
    return _viewport = Viewport(
      canvasWidth: size.width,
      canvasHeight: size.height,
      imageWidth: widget.engine.width.toDouble(),
      imageHeight: widget.engine.height.toDouble(),
    );
  }

  static PointerKind _kindOf(PointerEvent event) => switch (event.kind) {
    PointerDeviceKind.stylus => PointerKind.stylus,
    PointerDeviceKind.invertedStylus => PointerKind.invertedStylus,
    PointerDeviceKind.mouse || PointerDeviceKind.trackpad => PointerKind.mouse,
    _ => PointerKind.touch,
  };

  /// Stylus pressure over the device range; the classifier ignores it for
  /// touch and mouse.
  static double _pressureOf(PointerEvent event) =>
      normalizePressure(event.pressure, event.pressureMin, event.pressureMax);

  static Point<double> _pointOf(PointerEvent event) =>
      Point(event.localPosition.dx, event.localPosition.dy);

  void _onDown(PointerDownEvent event) => _handle(
    _classifier.pointerDown(
      event.pointer,
      _kindOf(event),
      _pointOf(event),
      _pressureOf(event),
      event.timeStamp,
    ),
  );

  void _onMove(PointerMoveEvent event) => _handle(
    _classifier.pointerMove(
      event.pointer,
      _pointOf(event),
      _pressureOf(event),
      event.timeStamp,
    ),
  );

  void _onUp(PointerUpEvent event) => _handle(
    _classifier.pointerUp(event.pointer, _pointOf(event), event.timeStamp),
  );

  void _onCancel(PointerCancelEvent event) =>
      _handle(_classifier.pointerCancel(event.pointer, event.timeStamp));

  StrokePoint _strokePoint(
    Point<double> position,
    double pressure,
    Duration t,
  ) {
    final p = _viewport!.screenToImage(position);
    return StrokePoint(p.x, p.y, pressure: pressure, tMillis: t.inMilliseconds);
  }

  void _handle(List<DrawGesture> gestures) {
    if (_viewport == null) return;
    for (final gesture in gestures) {
      switch (gesture) {
        case StrokeBegin():
          widget.onStrokeBegin(
            _strokePoint(gesture.position, gesture.pressure, gesture.time),
            gesture.erases,
          );
        case StrokeAdd():
          widget.onStrokeAdd(
            _strokePoint(gesture.position, gesture.pressure, gesture.time),
          );
        case StrokeEnd():
          widget.onStrokeEnd();
        case StrokeDiscard():
          widget.onStrokeDiscard();
        case FillTap():
          final p = _viewport!.screenToImage(gesture.position);
          widget.onFill(p.x, p.y);
        case ScaleStart():
          _scaleStartZoom = _viewport!.zoom;
        case ScaleUpdate():
          final viewport = _viewport!;
          final factor = _scaleStartZoom * gesture.scaleFactor / viewport.zoom;
          setState(() {
            _viewport = viewport
                .zoomAt(gesture.focal, factor)
                .panBy(gesture.panDelta);
          });
        case ScaleEnd():
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _classifier.fillMode = widget.fillMode;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = _viewportFor(constraints.biggest);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onCancel,
          child: ClipRect(
            child: CustomPaint(
              size: constraints.biggest,
              painter: _SheetPainter(
                engine: widget.engine,
                live: widget.live,
                viewport: viewport,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter({
    required this.engine,
    required this.live,
    required this.viewport,
  }) : super(repaint: Listenable.merge([engine, live]));

  final RasterEngine engine;
  final LiveStroke live;
  final Viewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = viewport.origin;
    canvas
      ..save()
      ..translate(origin.x, origin.y)
      ..scale(viewport.scale);
    canvas.drawImage(
      engine.committed,
      Offset.zero,
      Paint()..filterQuality = ui.FilterQuality.medium,
    );
    live.paint(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      !identical(old.engine, engine) ||
      !identical(old.live, live) ||
      !identical(old.viewport, viewport);
}
