import 'dart:ui' as ui;

import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/game/coloring_game.dart';
import 'package:coloring/features/coloring/game/fill_animations.dart';
import 'package:coloring/features/coloring/game/fill_renderer.dart';
import 'package:coloring/features/coloring/model/canvas_sink.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
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

LoadedPicture _picture() => LoadedPicture(
  regionsImage: _image(0xFF000001),
  linesImage: _image(0x00000000),
  map: fixtureMap(),
  meta: fixtureMeta(),
);

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
