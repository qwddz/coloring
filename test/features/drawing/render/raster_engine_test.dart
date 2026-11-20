import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coloring/features/drawing/model/brush_size.dart';
import 'package:coloring/features/drawing/model/drawing_history.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/drawing/model/flood_fill.dart';
import 'package:coloring/features/drawing/model/symmetry.dart';
import 'package:coloring/features/drawing/render/brush_painter.dart';
import 'package:coloring/features/drawing/render/brush_sprites.dart';
import 'package:coloring/features/drawing/render/draw_op.dart';
import 'package:coloring/features/drawing/render/raster_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_helpers.dart';

/// Pixels that differ between two RGBA buffers.
int diffCount(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      n++;
    }
  }
  return n;
}

/// A rectangle outline of pencil strokes on a [w] × [h] canvas.
List<StrokeOp> box(int w, int h, double l, double t, double r, double b) => [
  for (final side in [
    [(l, t), (r, t)],
    [(r, t), (r, b)],
    [(r, b), (l, b)],
    [(l, b), (l, t)],
  ])
    StrokeOp(
      strokeInput(
        DrawingTool.pencil,
        [for (final p in side) (p.$1 * w, p.$2 * h)],
        color: 0xFF000000,
        size: BrushSize.small,
      ),
    ),
];

/// A stroke of [tool] along points given as fractions of the canvas.
StrokeOp stroke(
  DrawingTool tool,
  int w,
  int h,
  List<(double, double)> points, {
  int color = 0xFF1E88E5,
  int seed = 3,
  BrushSize size = BrushSize.medium,
  SymmetryMode symmetry = SymmetryMode.off,
}) => StrokeOp(
  strokeInput(
    tool,
    [for (final p in points) (p.$1 * w, p.$2 * h)],
    color: color,
    seed: seed,
    size: size,
    symmetry: symmetry,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BrushSprites sprites;
  setUpAll(() async => sprites = await BrushSprites.create());
  tearDownAll(() => sprites.dispose());

  /// Up to 25 ops of a session on [engine]'s canvas: every brush, a mirror
  /// stroke, three fills (computed from the engine's readback at that
  /// point) and a clear. Commits the first [count] in order; [after] sees
  /// every state.
  Future<List<DrawOp>> drawSession(
    RasterEngine engine,
    int count, {
    Future<void> Function(int state)? after,
  }) async {
    final w = engine.width, h = engine.height;
    StrokeOp s(
      DrawingTool tool,
      List<(double, double)> points, {
      int color = 0xFF1E88E5,
      int seed = 3,
      SymmetryMode symmetry = SymmetryMode.off,
    }) => stroke(
      tool,
      w,
      h,
      points,
      color: color,
      seed: seed,
      symmetry: symmetry,
    );
    Future<DrawOp> fill(double x, double y, int color) async {
      final rgba = await engine.readback();
      final seed = ((x * w).round(), (y * h).round());
      final mask = floodFill(rgba, w, h, [seed], color);
      expect(mask, isNotNull, reason: 'fill at $seed');
      return FillOp(mask!, color);
    }

    final steps = <FutureOr<DrawOp> Function()>[
      for (final op in box(w, h, 0.1, 0.1, 0.45, 0.5)) () => op,
      () => fill(0.25, 0.3, 0xFFF4B6B6),
      () => s(DrawingTool.felt, [(0.5, 0.2), (0.7, 0.4), (0.9, 0.3)]),
      () => s(DrawingTool.marker, [(0.1, 0.8), (0.6, 0.6)], color: 0xFFE53935),
      () => s(DrawingTool.rainbow, [
        (0.2, 0.9),
        (0.4, 0.7),
        (0.3, 0.6),
      ], symmetry: SymmetryMode.vertical),
      () => s(DrawingTool.pastel, [(0.6, 0.7), (0.9, 0.9)], seed: 11),
      () => s(DrawingTool.watercolor, [
        (0.3, 0.2),
        (0.6, 0.5),
      ], color: 0xFF43A047),
      () => s(DrawingTool.airbrush, [(0.7, 0.1), (0.8, 0.5)], seed: 5),
      () => s(DrawingTool.neon, [(0.5, 0.9), (0.9, 0.6)]),
      () => ClearOp(width: w, height: h),
      () =>
          s(DrawingTool.stampStar, [(0.1, 0.5), (0.4, 0.5)], color: 0xFFFDD835),
      () => s(DrawingTool.stampHeart, [(0.6, 0.2)], color: 0xFFD81B60),
      for (final op in box(w, h, 0.5, 0.5, 0.9, 0.9)) () => op,
      () => fill(0.7, 0.7, 0xFF8E24AA),
      () => s(DrawingTool.eraser, [(0.6, 0.6), (0.8, 0.8)]),
      () => fill(0.05, 0.05, 0xFFFFF59D),
      () => s(DrawingTool.felt, [(0.05, 0.95), (0.95, 0.05)], seed: 9),
      () => s(DrawingTool.pencil, [(0.2, 0.3), (0.3, 0.2)], color: 0xFF000000),
      () => s(DrawingTool.watercolor, [
        (0.8, 0.2),
        (0.6, 0.4),
      ], color: 0xFF1E88E5),
    ];
    expect(steps, hasLength(25));
    final ops = <DrawOp>[];
    for (final step in steps.take(count)) {
      final op = await step();
      await engine.commit(op);
      ops.add(op);
      await after?.call(ops.length);
    }
    return ops;
  }

  /// State 0 (white) with [ops] replayed in one picture, rasterized the way
  /// the engine rasterizes (`toImageSync`).
  Future<Uint8List> replayAll(int w, int h, List<DrawOp> ops) async {
    final recorder = ui.PictureRecorder();
    final rect = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final canvas = ui.Canvas(recorder, rect)
      ..drawRect(rect, ui.Paint()..color = const ui.Color(drawingWhite));
    for (final op in ops) {
      op.replay(canvas, sprites);
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    try {
      return await pixelsOf(image);
    } finally {
      image.dispose();
    }
  }

  test('20 sequential commits with fills and a clear equal one replay from '
      'state 0, pixel for pixel (2048 × 1536)', () async {
    final engine = await RasterEngine.create(sprites: sprites);
    final ops = await drawSession(engine, 20);
    expect(ops.whereType<FillOp>(), isNotEmpty);
    expect(ops.whereType<ClearOp>(), isNotEmpty);
    final sequential = await engine.readback();
    final replayed = await replayAll(engine.width, engine.height, ops);
    expect(diffCount(sequential, replayed), 0);
    engine.dispose();
    await engine.idle;
    expect(engine.liveImageCount, 0);
  });

  test('undo and redo across checkpoints give the sequential states', () async {
    final engine = await RasterEngine.create(
      sprites: sprites,
      width: 320,
      height: 240,
    );
    addTearDown(engine.dispose);
    final states = <int, Uint8List>{
      0: Uint8List.fromList(await engine.readback()),
    };
    await drawSession(
      engine,
      25,
      after: (i) async =>
          states[i] = Uint8List.fromList(await engine.readback()),
    );
    expect(engine.checkpointEvery, defaultCheckpointEvery);
    for (var i = 24; i >= 0; i--) {
      expect(await engine.undo(), isTrue);
      expect(
        diffCount(await engine.readback(), states[i]!),
        0,
        reason: 'undo to $i',
      );
    }
    expect(engine.canUndo, isFalse);
    expect(await engine.undo(), isFalse);
    for (var i = 1; i <= 25; i++) {
      expect(await engine.redo(), isTrue);
      expect(
        diffCount(await engine.readback(), states[i]!),
        0,
        reason: 'redo to $i',
      );
    }
    expect(await engine.redo(), isFalse);
    // A commit after an undo drops the redo steps.
    await engine.undo();
    await engine.clear();
    expect(engine.canRedo, isFalse);
  });

  test(
    'undo stops after 30 steps; checkpoints stay within the bound',
    () async {
      final engine = await RasterEngine.create(
        sprites: sprites,
        width: 160,
        height: 120,
      );
      addTearDown(engine.dispose);
      final bound = (drawingMaxUndo / engine.checkpointEvery).ceil() + 1;
      for (var i = 0; i < 45; i++) {
        await engine.commit(
          stroke(DrawingTool.pencil, 160, 120, [(0.1, i / 45), (0.9, i / 45)]),
        );
        expect(engine.checkpointCount, lessThanOrEqualTo(bound));
      }
      var undos = 0;
      while (await engine.undo()) {
        undos++;
        expect(engine.checkpointCount, lessThanOrEqualTo(bound));
      }
      expect(undos, drawingMaxUndo);
      await engine.idle;
      // committed + checkpoints, nothing else.
      expect(engine.liveImageCount, lessThanOrEqualTo(bound + 1));
    },
  );

  test('flatten swaps in an equal, fully rasterized image', () async {
    final engine = await RasterEngine.create(
      sprites: sprites,
      width: 320,
      height: 240,
    );
    addTearDown(engine.dispose);
    for (var i = 0; i < defaultFlattenEvery - 1; i++) {
      await engine.commit(
        stroke(DrawingTool.felt, 320, 240, [
          (0.1, i / 10),
          (0.9, 0.5),
        ], seed: i),
      );
    }
    await engine.idle;
    var notified = 0;
    engine.addListener(() => notified++);
    await engine.commit(
      stroke(DrawingTool.watercolor, 320, 240, [(0.2, 0.2), (0.8, 0.8)]),
    );
    expect(notified, 1);
    final sync = engine.committed;
    final syncPixels = await pixelsOf(sync);
    await engine.idle;
    expect(notified, 2, reason: 'the flattened image is swapped in');
    expect(identical(engine.committed, sync), isFalse);
    expect(diffCount(await engine.readback(), syncPixels), 0);
  });

  test('a fill changes exactly the mask', () async {
    const w = 320, h = 240;
    final engine = await RasterEngine.create(
      sprites: sprites,
      width: w,
      height: h,
    );
    addTearDown(engine.dispose);
    for (final op in box(w, h, 0.2, 0.2, 0.7, 0.8)) {
      await engine.commit(op);
    }
    await engine.commit(
      stroke(DrawingTool.felt, w, h, [(0.3, 0.5), (0.6, 0.5)]),
    );
    final before = Uint8List.fromList(await engine.readback());
    const color = 0xFFF1C6A0;
    final mask = floodFill(before, w, h, [(w ~/ 2, (h * 0.3).round())], color)!;
    await engine.commit(FillOp(mask, color));
    final after = await engine.readback();
    final inMask = List.filled(w * h, false);
    for (var i = 0; i < mask.runs.length; i += 3) {
      for (var x = mask.runs[i + 1]; x < mask.runs[i + 2]; x++) {
        inMask[mask.runs[i] * w + x] = true;
      }
    }
    var filled = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final now = argbAt(after, w, x, y);
        if (inMask[y * w + x]) {
          filled++;
          expect(now, color, reason: '($x, $y) in the mask');
        } else {
          expect(now, argbAt(before, w, x, y), reason: '($x, $y) outside');
        }
      }
    }
    expect(filled, mask.pixelCount);
    expect(filled, greaterThan(1000));
  });

  test('the live layer bakes pre-opacity and shows the same stroke', () async {
    const w = 320, h = 240;
    final engine = await RasterEngine.create(
      sprites: sprites,
      width: w,
      height: h,
    );
    addTearDown(engine.dispose);
    final dabs = dabsOf(
      DrawingTool.marker,
      [(20, 120), (300, 60), (40, 40), (300, 200)],
      color: 0xFF3949AB,
      size: BrushSize.small,
    );
    expect(dabs.length, greaterThan(2 * liveBakeThreshold));
    final layer = engine.startStroke(DrawingTool.marker.spec);
    for (var i = 0; i < dabs.length; i += 10) {
      layer.add(dabs.sublist(i, i + 10 > dabs.length ? dabs.length : i + 10));
    }
    expect(layer.bakedCount, greaterThan(0));
    expect(layer.dabs, dabs);
    expect(engine.liveImageCount, 2, reason: 'committed + baked stroke');
    final live = await render(w, h, layer.paint);
    final direct = await render(
      w,
      h,
      (c) => composeStroke(
        c,
        dabs,
        DrawingTool.marker.spec,
        sprites,
        bounds: strokeBounds(dabs),
        stage: StrokeStage.live,
      ),
    );
    var maxDelta = 0;
    for (var i = 0; i < live.length; i++) {
      final d = (live[i] - direct[i]).abs();
      if (d > maxDelta) maxDelta = d;
    }
    expect(maxDelta, lessThanOrEqualTo(2));
    layer.dispose();
    expect(engine.liveImageCount, 1);
  });

  test('PNG round trip, and a smaller image is scaled to the canvas', () async {
    final small = await RasterEngine.create(
      sprites: sprites,
      width: 160,
      height: 120,
    );
    await small.commit(
      FillOp(
        floodFill(await small.readback(), 160, 120, [(0, 0)], 0xFF1E88E5)!,
        0xFF1E88E5,
      ),
    );
    await small.commit(
      stroke(DrawingTool.pencil, 160, 120, [
        (0.1, 0.5),
        (0.9, 0.5),
      ], color: 0xFFFFFFFF),
    );
    final png = await small.encodePng();
    final smallPixels = Uint8List.fromList(await small.readback());
    small.dispose();
    await small.idle;
    expect(small.liveImageCount, 0);

    final same = await RasterEngine.create(
      sprites: sprites,
      bytes: png,
      width: 160,
      height: 120,
    );
    addTearDown(same.dispose);
    expect(diffCount(await same.readback(), smallPixels), 0);

    final big = await RasterEngine.create(
      sprites: sprites,
      bytes: png,
      width: 320,
      height: 240,
    );
    addTearDown(big.dispose);
    expect(big.committed.width, 320);
    expect(big.committed.height, 240);
    final rgba = await big.readback();
    expect(argbAt(rgba, 320, 10, 10), 0xFF1E88E5);
    expect(argbAt(rgba, 320, 160, 120), 0xFFFFFFFF);

    await expectLater(
      RasterEngine.create(
        sprites: sprites,
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(anything),
    );
  });

  test('every image is released after dispose, even mid-flatten and '
      'mid-encode', () async {
    final engine = await RasterEngine.create(
      sprites: sprites,
      width: 320,
      height: 240,
    );
    for (var i = 0; i < 25; i++) {
      await engine.commit(
        stroke(DrawingTool.pastel, 320, 240, [
          (0.1, 0.1),
          (0.9, i / 25),
        ], seed: i),
      );
    }
    for (var i = 0; i < 7; i++) {
      await engine.undo();
    }
    expect(engine.liveImageCount, greaterThan(1));
    final snapshot = await engine.snapshot();
    final layer = engine.startStroke(DrawingTool.felt.spec)
      ..add(
        dabsOf(DrawingTool.felt, [
          (10, 10),
          (300, 200),
          (10, 200),
        ], size: BrushSize.small),
      );
    expect(layer.bakedCount, greaterThan(0));
    // An encode whose clone is taken, still encoding.
    final png = engine.encodePng();
    await engine.idle;
    // Cursor 18 → 20 is a checkpoint: its flatten is left running.
    expect(engine.checkpointEvery, 10);
    await engine.commit(stroke(DrawingTool.felt, 320, 240, [(0.5, 0.5)]));
    await engine.commit(stroke(DrawingTool.felt, 320, 240, [(0.6, 0.5)]));
    engine.dispose();
    await engine.idle;
    await expectLater(png, completes);
    expect(engine.liveImageCount, 0);
    expect(await engine.undo(), isFalse);
    unawaited(engine.commit(const ClearOp()));
    await engine.idle;
    expect(engine.liveImageCount, 0);
    // The snapshot belongs to the caller and outlives the engine.
    expect(snapshot.debugDisposed, isFalse);
    snapshot.dispose();
  });
}
