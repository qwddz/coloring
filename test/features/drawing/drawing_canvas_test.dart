import 'package:coloring/features/drawing/drawing_canvas.dart';
import 'package:coloring/features/drawing/live_stroke.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/drawing/model/stroke.dart';
import 'package:coloring/features/drawing/render/brush_sprites.dart';
import 'package:coloring/features/drawing/render/raster_engine.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The canvas is 512 × 384 dp: a 2048 × 1536 sheet at 1× is 4 canvas
/// pixels per dp.
const _canvas = Size(512, 384);
const _pxPerDp = drawingCanvasWidth / 512;

void main() {
  late BrushSprites sprites;
  late RasterEngine engine;
  late LiveStroke live;
  late List<String> log;
  late List<StrokePoint> points;

  setUp(() => log = []);

  Future<void> pumpCanvas(WidgetTester tester, {bool fillMode = false}) async {
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      sprites = await BrushSprites.create();
      engine = await RasterEngine.create(sprites: sprites);
    });
    live = LiveStroke();
    addTearDown(() {
      live.dispose();
      engine.dispose();
      sprites.dispose();
    });
    points = [];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DrawingCanvas(
          engine: engine,
          live: live,
          fillMode: fillMode,
          onStrokeBegin: (point, erases) {
            points.add(point);
            log.add(erases ? 'begin erasing' : 'begin');
          },
          onStrokeAdd: (point) {
            points.add(point);
            log.add('add');
          },
          onStrokeEnd: () => log.add('end'),
          onStrokeDiscard: () => log.add('discard'),
          onFill: (x, y) => log.add('fill ${x.round()} ${y.round()}'),
        ),
      ),
    );
  }

  DrawingCanvasState canvasState(WidgetTester tester) =>
      tester.state<DrawingCanvasState>(find.byType(DrawingCanvas));

  testWidgets('a finger draws from the first contact, in canvas pixels', (
    tester,
  ) async {
    await pumpCanvas(tester);
    final gesture = await tester.startGesture(const Offset(100, 100));
    expect(log, ['begin']);
    await gesture.moveTo(const Offset(150, 120));
    await gesture.up();
    expect(log, ['begin', 'add', 'end']);
    expect(points.first.x, closeTo(100 * _pxPerDp, 1e-6));
    expect(points.first.y, closeTo(100 * _pxPerDp, 1e-6));
    expect(points.last.x, closeTo(150 * _pxPerDp, 1e-6));
    expect(points.first.pressure, 1);
  });

  testWidgets('stylus pressure reaches the stroke', (tester) async {
    await pumpCanvas(tester);
    final gesture = await tester.createGesture(
      pointer: 7,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.downWithCustomEvent(
      const Offset(200, 200),
      const PointerDownEvent(
        pointer: 7,
        position: Offset(200, 200),
        kind: PointerDeviceKind.stylus,
        pressure: 0.25,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await gesture.moveTo(const Offset(220, 200));
    await gesture.up();
    expect(log, ['begin', 'add', 'end']);
    expect(points.first.pressure, closeTo(0.25, 1e-6));
  });

  testWidgets('an inverted stylus erases', (tester) async {
    await pumpCanvas(tester);
    final gesture = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.invertedStylus,
    );
    await gesture.up();
    expect(log, ['begin erasing', 'end']);
  });

  testWidgets('fill taps on lift, not when the finger moved', (tester) async {
    await pumpCanvas(tester, fillMode: true);
    final tap = await tester.startGesture(const Offset(50, 60));
    expect(log, isEmpty);
    await tap.up();
    expect(log, ['fill ${(50 * _pxPerDp).round()} ${(60 * _pxPerDp).round()}']);

    final drag = await tester.startGesture(const Offset(50, 60));
    await drag.moveBy(const Offset(30, 0));
    await drag.up();
    expect(log, hasLength(1));
  });

  testWidgets('two fingers zoom and pan without a stroke', (tester) async {
    await pumpCanvas(tester);
    final a = await tester.startGesture(const Offset(200, 192));
    final b = await tester.startGesture(const Offset(312, 192), pointer: 2);
    expect(log, ['begin', 'discard'], reason: 'the short stroke vanishes');
    for (var i = 1; i <= 5; i++) {
      await a.moveTo(Offset(200 - i * 10, 192));
      await b.moveTo(Offset(312 + i * 10, 192));
    }
    await a.up();
    await b.up();
    await tester.pump();
    expect(log, ['begin', 'discard']);
    final zoom = canvasState(tester).viewport!.zoom;
    expect(zoom, closeTo((112 + 100) / 112, 1e-6));

    // A stroke after the zoom maps through the zoomed view.
    await tester.startGesture(const Offset(256, 192)).then((g) => g.up());
    final center = points.last;
    expect(center.x, closeTo(drawingCanvasWidth / 2, 1));
    expect(center.y, closeTo(drawingCanvasHeight / 2, 1));
  });

  testWidgets('paints the committed sheet and repaints on a commit', (
    tester,
  ) async {
    await pumpCanvas(tester);
    final painted = find.descendant(
      of: find.byType(DrawingCanvas),
      matching: find.byType(CustomPaint),
    );
    expect(painted, findsOneWidget);
    final paint = tester.renderObject<RenderCustomPaint>(painted);
    expect(paint.painter, isNotNull);
    await tester.runAsync(() => engine.clear());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
