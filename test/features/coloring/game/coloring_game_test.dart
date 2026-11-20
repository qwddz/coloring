import 'dart:math';
import 'dart:ui' as ui;

import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/game/coloring_game.dart';
import 'package:coloring/features/coloring/game/fill_animations.dart';
import 'package:coloring/features/coloring/game/fill_renderer.dart';
import 'package:coloring/features/coloring/model/canvas_sink.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:coloring/features/coloring/model/picture_meta.dart';
import 'package:coloring/features/coloring/model/viewport.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';

import '../model/fixtures.dart';

ui.Image _image(int argb) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(ui.Color(argb), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(fixtureWidth, fixtureHeight);
  picture.dispose();
  return image;
}

/// The fixture; [labelRadius] (image px) replaces every region's label
/// radius.
LoadedPicture _picture({double? labelRadius}) {
  final json = fixtureJson();
  if (labelRadius != null) {
    for (final r in json['regions']! as List<Object?>) {
      (r! as Map<String, Object?>)['label_radius'] = labelRadius;
    }
  }
  return LoadedPicture(
    regionsImage: _image(0xFF000001),
    linesImage: _image(0x00000000),
    map: fixtureMap(),
    meta: PictureMeta.fromJson(json),
  );
}

const _frame = Duration(milliseconds: 16);

void main() {
  late LoadedPicture picture;

  setUp(() => picture = _picture());
  tearDown(() => picture.dispose());

  Future<ColoringGame> pumpGame(
    WidgetTester tester, {
    FillRendererFactory? createRenderer,
    bool reducedMotion = false,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = ColoringGame(
      picture: picture,
      createRenderer: createRenderer ?? (_) => FlatFillRenderer(picture.meta),
      reducedMotion: reducedMotion,
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.runAsync(() async => game.toBeLoaded());
    await tester.pump();
    await tester.pump(_frame);
    return game;
  }

  /// Fills region 2 with red, as a tap at its label would.
  (FillState, List<RegionChange>) fillRegion2(ColoringGame game) {
    final state = game.fill.copy()..setColor(2, red);
    return (state, const [RegionChange(2, 0, red)]);
  }

  testWidgets('a fill swaps the state texture and disposes the old one', (
    tester,
  ) async {
    final game = await pumpGame(tester);
    final before = game.uniforms.stateTexture!;
    final (state, changes) = fillRegion2(game);
    game.showFill(state, changes);
    expect(game.uniforms.stateTexture, isNot(same(before)));
    expect(before.debugDisposed, isTrue);
    expect(game.uniforms.fill, same(state));
    expect(game.wave.active, isFalse);
  });

  testWidgets('a tap fill shows the new color in the next frame, then the '
      'wave ends', (tester) async {
    final game = await pumpGame(tester);
    final (state, changes) = fillRegion2(game);
    game.showFill(state, changes, waveX: 10.5, waveY: 1.5);
    await tester.pump(_frame);
    final u = game.uniforms;
    expect(u.waveId, 2);
    expect(u.waveNewColor, red);
    expect(u.waveOldColor, 0);
    expect(u.waveRadius, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(_frame);
    expect(game.uniforms.waveId, 0);
  });

  testWidgets('reduced motion: one frame at the huge finite radius', (
    tester,
  ) async {
    final game = await pumpGame(tester, reducedMotion: true);
    final (state, changes) = fillRegion2(game);
    game.showFill(state, changes, waveX: 10.5, waveY: 1.5);
    await tester.pump(_frame);
    expect(game.uniforms.waveId, 2);
    expect(game.uniforms.waveRadius, instantRadius);
    await tester.pump(_frame);
    expect(game.uniforms.waveId, 0);
  });

  testWidgets('a new fill finishes the running wave at once', (tester) async {
    final game = await pumpGame(tester);
    final (state, changes) = fillRegion2(game);
    game.showFill(state, changes, waveX: 10.5, waveY: 1.5);
    await tester.pump(_frame);
    game.showFill(state.copy()..setColor(1, blue), const [
      RegionChange(1, 0, blue),
    ]);
    expect(game.uniforms.waveId, 0);
  });

  testWidgets('flash, hint and highlight drive their uniforms', (tester) async {
    final game = await pumpGame(tester);
    game.flashRejected(3);
    await tester.pump(const Duration(milliseconds: 150));
    expect(game.uniforms.flashId, 3);
    expect(game.uniforms.flashAmount, greaterThan(0.5));
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.uniforms.flashId, 0);

    game.showHint(4, red);
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.uniforms.waveId, 4);
    expect(game.uniforms.waveNewColor, red);
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.uniforms.waveId, 0);

    game.setHighlight(1);
    expect(game.highlightPalette, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.uniforms.highlightPalette, 1);
    expect(game.uniforms.pulse, isNot(0.5));
    game.setHighlight(null);
    expect(game.uniforms.highlightPalette, -1);
  });

  testWidgets('removing the game mid-wave disposes only its own handles', (
    tester,
  ) async {
    final game = await pumpGame(tester);
    final (state, changes) = fillRegion2(game);
    game.showFill(state, changes, waveX: 10.5, waveY: 1.5);
    game.flashRejected(1);
    await tester.pump(_frame);
    final texture = game.uniforms.stateTexture!;

    await tester.pumpWidget(const SizedBox());
    await tester.pump(_frame);
    expect(game.isDisposed, isTrue);
    expect(texture.debugDisposed, isTrue);
    expect(game.regionsImage.debugDisposed, isTrue);
    expect(game.linesImage.debugDisposed, isTrue);
    expect(picture.regionsImage.debugDisposed, isFalse);
    expect(picture.linesImage.debugDisposed, isFalse);

    // The controller may still talk to a removed game.
    game
      ..showFill(state, changes, waveX: 1, waveY: 1)
      ..flashRejected(2)
      ..showHint(3, blue)
      ..setHighlight(0)
      ..setLabelsEnabled(true);
    expect(game.uniforms.stateTexture, isNull);
    await tester.pump(_frame);
  });

  testWidgets('the owner may dispose its picture before the game', (
    tester,
  ) async {
    final game = await pumpGame(tester);
    picture.dispose();
    picture = _picture();
    await tester.pump(_frame);
    expect(game.regionsImage.debugDisposed, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  group('find', () {
    // 800×600 canvas, 50 dp per image px. A 0.1 px label radius is 5 dp, so
    // find zooms to 8 dp * 1.5 / 5 dp = 2.4x.
    const findZoom = 2.4;

    Point<double> centerOf(Viewport v) =>
        v.screenToImage(Point(v.canvasWidth / 2, v.canvasHeight / 2));

    testWidgets('goes to the nearest candidate and ends at the target', (
      tester,
    ) async {
      picture.dispose();
      picture = _picture(labelRadius: 0.1);
      final game = await pumpGame(tester);
      final start = game.viewport!;
      // View center (8, 6): region 4 (10.5, 6.5) is nearer than 1 (2.5, 1.5).
      game.focusOn(const [1, 4]);
      expect(game.focusedRegion, 4);
      expect(game.focusing, isTrue);

      await tester.pump(_frame);
      final mid = game.viewport!;
      expect(mid.zoom, greaterThan(1));
      expect(mid.zoom, lessThan(findZoom));

      await tester.pump(const Duration(milliseconds: 500));
      expect(game.focusing, isFalse);
      final end = game.viewport!;
      final expected = start.focusOn(const Point(10.5, 6.5), findZoom);
      expect(end.zoom, closeTo(findZoom, 1e-9));
      expect(end.pan.x, closeTo(expected.pan.x, 1e-9));
      expect(end.pan.y, closeTo(expected.pan.y, 1e-9));
      expect(centerOf(end).x, closeTo(10.5, 1e-9));
      expect(centerOf(end).y, closeTo(6.5, 1e-9));
    });

    testWidgets('alternates between candidates and keeps a single one', (
      tester,
    ) async {
      picture.dispose();
      picture = _picture(labelRadius: 0.1);
      final game = await pumpGame(tester, reducedMotion: true);
      game.focusOn(const [1, 4]);
      expect(game.focusedRegion, 4);
      game.focusOn(const [1, 4]);
      expect(game.focusedRegion, 1);
      game.focusOn(const [1, 4]);
      expect(game.focusedRegion, 4);
      game.focusOn(const [4]);
      expect(game.focusedRegion, 4);
    });

    testWidgets('three candidates: all are visited before any repeats', (
      tester,
    ) async {
      picture.dispose();
      picture = _picture(labelRadius: 0.1);
      final game = await pumpGame(tester, reducedMotion: true);
      const ids = [1, 2, 4];
      final order = <int>[];
      for (var i = 0; i < 4; i++) {
        game.focusOn(ids);
        order.add(game.focusedRegion);
      }
      expect(order.take(3).toSet(), ids.toSet());
      expect(order[3], isNot(order[2]), reason: 'a new round skips the last');

      // A colored region leaves the candidates; the round goes on.
      game.focusOn(const [1, 2]);
      expect(const [1, 2], contains(game.focusedRegion));
    });

    testWidgets('a resize mid-move uses the new fit for the target zoom', (
      tester,
    ) async {
      picture.dispose();
      picture = _picture(labelRadius: 0.1);
      final game = await pumpGame(tester);
      game.focusOn(const [4]);
      await tester.pump(_frame);
      // 400×300: 25 dp per px, the 2.5 dp label wants 4.8x; max zoom is 4.
      tester.view.physicalSize = const Size(400, 300);
      await tester.pump(_frame);
      await tester.pump(const Duration(milliseconds: 500));
      expect(game.focusing, isFalse);
      expect(game.viewport!.zoom, closeTo(4, 1e-9));
    });

    testWidgets('never zooms out and stays within max zoom', (tester) async {
      picture.dispose();
      picture = _picture(labelRadius: 0.1);
      final game = await pumpGame(tester, reducedMotion: true);
      game.viewport = game.viewport!.zoomAt(const Point(400, 300), 3.5);
      game.focusOn(const [4]);
      expect(game.viewport!.zoom, closeTo(3.5, 1e-9));

      picture.dispose();
      picture = _picture(labelRadius: 0.001);
      final tiny = await pumpGame(tester, reducedMotion: true);
      tiny.focusOn(const [4]);
      expect(tiny.viewport!.zoom, tiny.viewport!.maxZoom);
      expect(tiny.viewport!.maxZoom, 8);
    });

    testWidgets('reduced motion jumps at once', (tester) async {
      picture.dispose();
      picture = _picture(labelRadius: 0.1);
      final game = await pumpGame(tester, reducedMotion: true);
      game.focusOn(const [4]);
      expect(game.focusing, isFalse);
      expect(game.viewport!.zoom, closeTo(findZoom, 1e-9));
      expect(centerOf(game.viewport!).x, closeTo(10.5, 1e-9));
    });

    testWidgets('cancel stops the move where it is', (tester) async {
      picture.dispose();
      picture = _picture(labelRadius: 0.1);
      final game = await pumpGame(tester);
      game.focusOn(const [4]);
      await tester.pump(_frame);
      game.cancelFocus();
      expect(game.focusing, isFalse);
      final stopped = game.viewport!;
      await tester.pump(const Duration(milliseconds: 500));
      expect(game.viewport!.zoom, stopped.zoom);
      expect(game.viewport!.pan, stopped.pan);
      expect(stopped.zoom, lessThan(findZoom));
    });

    testWidgets('a removed game ignores find', (tester) async {
      final game = await pumpGame(tester);
      await tester.pumpWidget(const SizedBox());
      game.focusOn(const [1]);
      expect(game.focusing, isFalse);
      expect(game.focusedRegion, 0);
    });
  });

  testWidgets('max zoom fits the smallest label; at max zoom every number '
      'shows', (tester) async {
    // 0.01 px is 0.5 dp at 1x: 16x would be needed, the cap is 8x, where
    // the label is 4 dp, below the 8 dp threshold.
    picture.dispose();
    picture = _picture(labelRadius: 0.01);
    final game = await pumpGame(tester);
    expect(game.viewport!.maxZoom, 8);
    game.setLabelsEnabled(true);

    // Zoom around region 4's label (10.5, 6.5), so it stays in view.
    const label4 = Point(525.0, 325.0);
    game.viewport = game.viewport!.zoomAt(label4, 7.9);
    await tester.pump(_frame);
    expect(game.viewport!.atMaxZoom, isFalse);
    expect(game.drawnLabels, 0);

    game.viewport = game.viewport!.zoomAt(label4, 2);
    await tester.pump(_frame);
    expect(game.viewport!.atMaxZoom, isTrue);
    expect(game.drawnLabels, greaterThan(0));
  });

  testWidgets('a resize to a bigger canvas lowers max zoom and clamps the '
      'view', (tester) async {
    // 0.1 px label: 160×120 is 10 dp per px, so 8 dp needs 8x; 800×600 is
    // 50 dp per px, where 4x is enough.
    picture.dispose();
    picture = _picture(labelRadius: 0.1);
    final game = await pumpGame(tester);
    tester.view.physicalSize = const Size(160, 120);
    await tester.pump(_frame);
    expect(game.viewport!.maxZoom, 8);
    game.viewport = game.viewport!.zoomAt(const Point(150, 110), 100);
    expect(game.viewport!.atMaxZoom, isTrue);

    tester.view.physicalSize = const Size(800, 600);
    await tester.pump(_frame);
    final v = game.viewport!;
    expect(v.maxZoom, defaultMaxZoom);
    expect(v.zoom, defaultMaxZoom);
    // The image still covers the whole canvas.
    expect(v.origin.x, lessThanOrEqualTo(1e-9));
    expect(v.origin.y, lessThanOrEqualTo(1e-9));
    final end = v.imageToScreen(const Point(16, 12));
    expect(end.x, greaterThanOrEqualTo(800 - 1e-9));
    expect(end.y, greaterThanOrEqualTo(600 - 1e-9));
  });

  testWidgets('max zoom stays 4x when the labels are big enough', (
    tester,
  ) async {
    final game = await pumpGame(tester);
    expect(game.viewport!.maxZoom, defaultMaxZoom);
  });

  testWidgets('renders with the real shader renderer', (tester) async {
    final program = (await tester.runAsync(ShaderFillRenderer.loadProgram))!;
    ShaderFillRenderer? created;
    final game = await pumpGame(
      tester,
      createRenderer: (regions) =>
          created = ShaderFillRenderer(program, regions),
    );
    expect(created!.regions, same(game.regionsImage));
    final (state, changes) = fillRegion2(game);
    game
      ..setLabelsEnabled(true)
      ..showFill(state, changes, waveX: 10.5, waveY: 1.5);
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(game.isDisposed, isTrue);
  });
}
