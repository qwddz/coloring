import 'dart:math';
import 'dart:ui' as ui;

import 'package:coloring/features/coloring/coloring_canvas.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/game/coloring_game.dart';
import 'package:coloring/features/coloring/game/fill_renderer.dart';
import 'package:coloring/features/coloring/perf/fill_latency_probe.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'model/fixtures.dart';

ui.Image _image(int argb) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(ui.Color(argb), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(fixtureWidth, fixtureHeight);
  picture.dispose();
  return image;
}

const _frame = Duration(milliseconds: 16);

class _Calls {
  final events = <String>[];
  final points = <(double, double, double)>[];

  CanvasPointCallback record(String name) => (x, y, tolerance) {
    events.add(name);
    points.add((x, y, tolerance));
  };
}

void main() {
  late LoadedPicture picture;
  late _Calls calls;

  setUp(() {
    picture = LoadedPicture(
      regionsImage: _image(0xFF000001),
      linesImage: _image(0x00000000),
      map: fixtureMap(),
      meta: fixtureMeta(),
    );
    calls = _Calls();
  });
  tearDown(() => picture.dispose());

  /// The 16×12 fixture on an 800×600 canvas: 50 dp per image px, origin
  /// (0, 0) at 1×.
  Future<ColoringGame> pumpCanvas(
    WidgetTester tester, {
    bool brushDrags = false,
    Size canvas = const Size(800, 600),
    FillLatencyProbe? probe,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = ColoringGame(
      picture: picture,
      createRenderer: (_) => FlatFillRenderer(picture.meta),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: canvas,
            child: ColoringCanvas(
              game: game,
              brushDrags: brushDrags,
              onTap: calls.record('tap'),
              onLongPress: calls.record('longPress'),
              onStrokeStart: calls.record('strokeStart'),
              onStrokeUpdate: calls.record('strokeUpdate'),
              onStrokeEnd: calls.record('strokeEnd'),
              latencyProbe: probe,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async => game.toBeLoaded());
    await tester.pump();
    await tester.pump(_frame);
    return game;
  }

  testWidgets('a tap reports the image point and tolerance at 1x', (
    tester,
  ) async {
    await pumpCanvas(tester);
    await tester.tapAt(const Offset(525, 75));
    expect(calls.events, ['tap']);
    final (x, y, tolerance) = calls.points.single;
    expect(x, closeTo(10.5, 1e-9));
    expect(y, closeTo(1.5, 1e-9));
    // 6 dp at 50 dp per image px is below the 4 px minimum.
    expect(tolerance, 4);
  });

  testWidgets('the latency probe starts at the pointer-up stamp', (
    tester,
  ) async {
    final probe = FillLatencyProbe(log: (_) {});
    await pumpCanvas(tester, probe: probe);
    final g = await tester.createGesture();
    await g.down(const Offset(125, 75), timeStamp: const Duration(seconds: 3));
    await g.up(timeStamp: const Duration(seconds: 3, milliseconds: 100));
    expect(calls.events, ['tap']);
    probe.recordFrame(vsyncStartMicros: 3105000, rasterFinishMicros: 3130000);
    expect(probe.samples, [30000]);
  });

  testWidgets('a pinch zooms in around the focal point, capped at 4x', (
    tester,
  ) async {
    final game = await pumpCanvas(tester);
    final a = await tester.startGesture(const Offset(350, 300), pointer: 1);
    final b = await tester.startGesture(const Offset(450, 300), pointer: 2);
    await a.moveTo(const Offset(300, 300));
    await b.moveTo(const Offset(500, 300));
    await tester.pump(_frame);
    expect(game.viewport!.zoom, closeTo(2, 1e-9));
    // The image point under the focal point stays put.
    final focal = game.viewport!.screenToImage(const Point(400, 300));
    expect(focal.x, closeTo(8, 1e-9));
    expect(focal.y, closeTo(6, 1e-9));

    await a.moveTo(const Offset(0, 300));
    await b.moveTo(const Offset(800, 300));
    await tester.pump(_frame);
    expect(game.viewport!.zoom, 4);
    await a.up();
    await b.up();
    expect(calls.events, isEmpty);
  });

  testWidgets('a one-finger drag at 1x is neither a tap nor a pan', (
    tester,
  ) async {
    final game = await pumpCanvas(tester);
    final before = game.viewport!;
    await tester.dragFrom(const Offset(400, 300), const Offset(150, 80));
    expect(calls.events, isEmpty);
    expect(game.viewport!.zoom, 1);
    expect(game.viewport!.pan, before.pan);
  });

  testWidgets('a one-finger drag pans when zoomed in', (tester) async {
    final game = await pumpCanvas(tester);
    game.viewport = game.viewport!.zoomAt(const Point(400, 300), 2);
    final before = game.viewport!.pan;
    await tester.dragFrom(const Offset(400, 300), const Offset(100, 50));
    expect(calls.events, isEmpty);
    expect(game.viewport!.pan.x, greaterThan(before.x));
    expect(game.viewport!.pan.y, greaterThan(before.y));
  });

  testWidgets('in magic mode a drag is a stroke, also when zoomed in', (
    tester,
  ) async {
    final game = await pumpCanvas(tester, brushDrags: true);
    game.viewport = game.viewport!.zoomAt(const Point(400, 300), 2);
    final pan = game.viewport!.pan;
    final g = await tester.startGesture(const Offset(400, 300));
    await g.moveBy(const Offset(50, 0));
    await g.moveBy(const Offset(50, 0));
    await g.up();
    expect(calls.events, [
      'strokeStart',
      'strokeUpdate',
      'strokeUpdate',
      'strokeEnd',
    ]);
    expect(game.viewport!.pan, pan);
    // Start at the canvas center = image center (8, 6) at any zoom here.
    expect(calls.points.first.$1, closeTo(8, 1e-9));
    expect(calls.points.last.$1, greaterThan(8));
  });

  testWidgets('a second finger ends the stroke and starts a pinch', (
    tester,
  ) async {
    await pumpCanvas(tester, brushDrags: true);
    final a = await tester.startGesture(const Offset(300, 300), pointer: 1);
    await a.moveBy(const Offset(40, 0));
    final b = await tester.startGesture(const Offset(500, 300), pointer: 2);
    await b.moveBy(const Offset(40, 0));
    await a.up();
    await b.up();
    expect(calls.events, ['strokeStart', 'strokeUpdate', 'strokeEnd']);
  });

  testWidgets('a cancelled pointer commits the open stroke', (tester) async {
    await pumpCanvas(tester, brushDrags: true);
    final g = await tester.startGesture(const Offset(300, 300));
    await g.moveBy(const Offset(40, 0));
    await g.cancel();
    expect(calls.events, ['strokeStart', 'strokeUpdate', 'strokeEnd']);
    expect(calls.points.last.$1, calls.points[1].$1);
  });

  testWidgets('cancelling the second finger keeps the first one down', (
    tester,
  ) async {
    await pumpCanvas(tester);
    final a = await tester.startGesture(const Offset(300, 300), pointer: 1);
    final b = await tester.startGesture(const Offset(500, 300), pointer: 2);
    await b.cancel();
    // Finger 1 is still tracked, so a touch while it is down is no tap.
    await tester.tapAt(const Offset(125, 75), pointer: 3);
    expect(calls.events, isEmpty);
    await a.up();
    await tester.tapAt(const Offset(125, 75), pointer: 4);
    expect(calls.events, ['tap']);
  });

  testWidgets('in magic mode a 600 ms hold then a swipe is a stroke', (
    tester,
  ) async {
    await pumpCanvas(tester, brushDrags: true);
    final g = await tester.createGesture();
    await g.down(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(50, 0));
    await g.moveBy(const Offset(50, 0));
    await g.up();
    expect(calls.events, [
      'strokeStart',
      'strokeUpdate',
      'strokeUpdate',
      'strokeEnd',
    ]);
  });

  testWidgets('zoomed in, a long press then a move pans', (tester) async {
    final game = await pumpCanvas(tester);
    game.viewport = game.viewport!.zoomAt(const Point(400, 300), 2);
    final before = game.viewport!.pan;
    final g = await tester.createGesture();
    await g.down(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(100, 50));
    await g.up();
    expect(calls.events, ['longPress']);
    expect(game.viewport!.pan.x, greaterThan(before.x));
    expect(game.viewport!.pan.y, greaterThan(before.y));
  });

  group('long press timer', () {
    testWidgets('held 500 ms without moving: one long press, no tap', (
      tester,
    ) async {
      await pumpCanvas(tester);
      final g = await tester.createGesture();
      await g.down(const Offset(125, 75));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls.events, ['longPress']);
      expect(calls.points.single.$1, closeTo(2.5, 1e-9));
      await tester.pump(const Duration(milliseconds: 500));
      await g.up(timeStamp: const Duration(milliseconds: 1000));
      expect(calls.events, ['longPress']);
    });

    testWidgets('released at 250 ms: a tap, no long press', (tester) async {
      await pumpCanvas(tester);
      final g = await tester.createGesture();
      await g.down(const Offset(125, 75));
      await tester.pump(const Duration(milliseconds: 250));
      await g.up(timeStamp: const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls.events, ['tap']);
    });

    testWidgets('released at 400 ms: too long for a tap, too short for a '
        'long press', (tester) async {
      await pumpCanvas(tester);
      final g = await tester.createGesture();
      await g.down(const Offset(125, 75));
      await tester.pump(const Duration(milliseconds: 400));
      await g.up(timeStamp: const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls.events, isEmpty);
    });
  });

  testWidgets('labels hide below the size threshold and show when zoomed', (
    tester,
  ) async {
    // 80×60 canvas: 5 dp per image px, so a 1.5 px label radius is 7.5 dp.
    final game = await pumpCanvas(tester, canvas: const Size(80, 60));
    await tester.pump(_frame);
    expect(game.drawnLabels, 0, reason: 'labels are off');

    game.setLabelsEnabled(true);
    await tester.pump(_frame);
    expect(game.drawnLabels, 0, reason: '7.5 dp < 10 dp');

    game.viewport = game.viewport!.zoomAt(const Point(40, 30), 4);
    await tester.pump(_frame);
    // 30 dp each; at 4x a quarter of the image is visible, all 5 label
    // circles touch the middle quarter.
    expect(game.drawnLabels, greaterThan(0));
    final zoomed = game.drawnLabels;

    // A correctly filled region drops its number.
    final fill = game.fill.copy();
    for (var id = 1; id <= 5; id++) {
      fill.setColor(id, fixtureMeta().correctColorOf(id));
    }
    game.showFill(fill, const []);
    await tester.pump(_frame);
    expect(game.drawnLabels, 0);
    expect(zoomed, greaterThan(0));
  });
}
