import 'dart:math';
import 'dart:typed_data';

import 'package:coloring/features/drawing/model/brush_size.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/drawing/model/stroke.dart';
import 'package:coloring/features/drawing/render/brush_painter.dart';
import 'package:coloring/features/drawing/render/brush_sprites.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_helpers.dart';

const int w = 256;
const int h = 192;
const int black = 0xFF000000;

/// A horizontal line through the middle of the canvas.
const List<(double, double)> line = [(40, 96), (90, 96), (140, 96), (216, 96)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BrushSprites sprites;
  setUpAll(() async => sprites = await BrushSprites.create());
  tearDownAll(() => sprites.dispose());

  Future<Uint8List> paint(
    DrawingTool tool,
    List<Dab> dabs, {
    StrokeStage stage = StrokeStage.commit,
    int background = drawingWhite,
  }) => render(
    w,
    h,
    (c) => composeStroke(
      c,
      dabs,
      tool.spec,
      sprites,
      bounds: strokeBounds(dabs, bleed: tool.spec.bleed),
      stage: stage,
    ),
    background: background,
  );

  for (final tool in DrawingTool.values) {
    if (tool == DrawingTool.fill) continue;
    test('${tool.name} paints, only inside its bounds', () async {
      final background = tool == DrawingTool.eraser ? black : drawingWhite;
      final dabs = dabsOf(tool, line);
      expect(dabs, isNotEmpty);
      final bounds = strokeBounds(dabs, bleed: tool.spec.bleed);
      final rgba = await paint(tool, dabs, background: background);
      var changed = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (argbAt(rgba, w, x, y) == background) continue;
          changed++;
          expect(
            bounds.contains(Offset(x + 0.5, y + 0.5)),
            isTrue,
            reason: 'pixel ($x, $y) outside $bounds',
          );
        }
      }
      expect(changed, greaterThan(100));
      if (tool == DrawingTool.pencil || tool == DrawingTool.felt) {
        // Opaque dabs show the exact color (sprite alpha premultiplied right).
        expect(argbAt(rgba, w, 128, 96), 0xFF1E88E5);
      }
      if (tool == DrawingTool.eraser) {
        expect(argbAt(rgba, w, 128, 96), drawingWhite);
      }
    });
  }

  test(
    'marker: one layer at about half alpha, however often dabs overlap',
    () async {
      // Back and forth over the same line: dabs overlap many times.
      final dabs = dabsOf(
        DrawingTool.marker,
        [...line, ...line.reversed, ...line],
        color: black,
        size: BrushSize.large,
      );
      final rgba = await paint(DrawingTool.marker, dabs);
      final center = argbAt(rgba, w, 128, 96);
      for (final channel in [red(center), green(center), blue(center)]) {
        expect(channel, closeTo(128, 3));
      }
      // Baking is pre-opacity: the dabs alone are solid.
      final baked = await paint(
        DrawingTool.marker,
        dabs,
        stage: StrokeStage.bake,
      );
      expect(argbAt(baked, w, 128, 96), black);
    },
  );

  test('neon: the core is lighter than the glow', () async {
    const color = 0xFF2060FF;
    final dabs = dabsOf(DrawingTool.neon, line, color: color);
    final rgba = await paint(DrawingTool.neon, dabs, background: black);
    final radius = BrushSize.medium.width / 2;
    final core = argbAt(rgba, w, 128, 96);
    final glow = argbAt(rgba, w, 128, 96 + (radius * 1.5).round());
    expect(brightness(glow), greaterThan(0), reason: 'the glow shows');
    expect(brightness(core), greaterThan(brightness(glow)));
    // The core is the color mixed with white: lighter than the color.
    expect(brightness(core), greaterThan(brightness(color)));
  });

  test('watercolor bleeds only when committing', () async {
    final dabs = dabsOf(DrawingTool.watercolor, line, color: black);
    final maxRadius = dabs.map((d) => d.radius).reduce(max);
    final committed = await paint(DrawingTool.watercolor, dabs);
    final live = await paint(
      DrawingTool.watercolor,
      dabs,
      stage: StrokeStage.live,
    );
    var outsideCommit = 0;
    var outsideLive = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final inDab = dabs.any(
          (d) =>
              (Offset(x + 0.5, y + 0.5) - Offset(d.x, d.y)).distance <=
              d.radius + 1,
        );
        if (inDab) continue;
        if (argbAt(committed, w, x, y) != drawingWhite) {
          outsideCommit++;
        }
        if (argbAt(live, w, x, y) != drawingWhite) outsideLive++;
      }
    }
    expect(outsideLive, 0, reason: 'no blur in the live preview');
    expect(outsideCommit, greaterThan(0), reason: 'the bleed spreads');
    expect(maxRadius, greaterThan(0));
    // Both are translucent (layer opacity 0.35).
    final c = argbAt(committed, w, 128, 96);
    expect(red(c), inExclusiveRange(100, 255));
  });

  test('dab colors multiply alpha', () {
    expect(dabColor(0xFF123456, 1), 0xFF123456);
    expect(dabColor(0xFF123456, 0.5), 0x80123456);
    expect(dabColor(0x80123456, 0.5), 0x40123456);
    expect(dabColor(0xFF123456, 0), 0x00123456);
  });
}
