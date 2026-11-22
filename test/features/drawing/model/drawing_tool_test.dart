import 'package:coloring/features/drawing/model/brush_size.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canvas is 2048 × 1536 (4:3)', () {
    expect(drawingCanvasWidth, 2048);
    expect(drawingCanvasHeight, 1536);
    expect(drawingCanvasWidth * 3, drawingCanvasHeight * 4);
  });

  test('tools are in panel order', () {
    expect(DrawingTool.values, [
      DrawingTool.pencil,
      DrawingTool.felt,
      DrawingTool.marker,
      DrawingTool.eraser,
      DrawingTool.rainbow,
      DrawingTool.pastel,
      DrawingTool.crayon,
      DrawingTool.chalk,
      DrawingTool.watercolor,
      DrawingTool.airbrush,
      DrawingTool.calligraphy,
      DrawingTool.neon,
      DrawingTool.dotted,
      DrawingTool.glitter,
      DrawingTool.stampStar,
      DrawingTool.stampHeart,
      DrawingTool.fill,
    ]);
  });

  test('tools and sizes round-trip by name', () {
    for (final t in DrawingTool.values) {
      expect(DrawingTool.fromName(t.name), t);
    }
    expect(DrawingTool.fromName('brush'), isNull);
    for (final s in BrushSize.values) {
      expect(BrushSize.fromName(s.name), s);
    }
    expect(BrushSize.fromName(3), isNull);
  });

  test('sizes grow', () {
    final widths = BrushSize.values.map((s) => s.width).toList();
    for (var i = 1; i < widths.length; i++) {
      expect(widths[i], greaterThan(widths[i - 1]));
    }
  });

  test('every spec is well formed', () {
    for (final t in DrawingTool.values) {
      final s = t.spec;
      expect(s.passes, isNotEmpty, reason: t.name);
      expect(s.radiusFactor, greaterThan(0), reason: t.name);
      expect(s.spacing, greaterThan(0), reason: t.name);
      expect(s.dabAlpha, inInclusiveRange(0.01, 1), reason: t.name);
      expect(s.layerOpacity, inInclusiveRange(0.01, 1), reason: t.name);
      expect(s.spriteVariants, greaterThanOrEqualTo(1), reason: t.name);
      expect(
        s.sprite.index + s.spriteVariants,
        lessThanOrEqualTo(BrushSprite.values.length),
        reason: t.name,
      );
      expect(s.stamp != null, s.kind == BrushKind.stamps, reason: t.name);
    }
  });

  test('brush table (spec §8)', () {
    expect(DrawingTool.pencil.spec.radiusFactor, 0.5);
    expect(DrawingTool.pencil.spec.pressureScale(0), 0.5);
    expect(DrawingTool.pencil.spec.pressureScale(1), 1.2);
    expect(DrawingTool.felt.spec.sprite, BrushSprite.soft);
    expect(DrawingTool.marker.spec.layerOpacity, 0.5);
    expect(DrawingTool.marker.spec.radiusFactor, 1.4);
    expect(DrawingTool.eraser.spec.colorMode, BrushColorMode.white);
    expect(DrawingTool.rainbow.spec.colorMode, BrushColorMode.rainbow);
    expect(DrawingTool.pastel.spec.dabAlpha, 0.55);
    expect(DrawingTool.pastel.spec.spriteVariants, 4);
    expect(DrawingTool.pastel.spec.sprite, BrushSprite.grain0);
    expect(DrawingTool.watercolor.spec.layerOpacity, 0.35);
    expect(DrawingTool.watercolor.spec.bleed, isTrue);
    expect(DrawingTool.airbrush.spec.dabAlpha, 0.25);
    expect(DrawingTool.airbrush.spec.sprayDensity, greaterThan(0));
    final neon = DrawingTool.neon.spec.passes;
    expect(neon, hasLength(2));
    expect(neon[0].sprite, BrushSprite.soft);
    expect(neon[0].radiusScale, 2.2);
    expect(neon[0].alpha, 0.35);
    expect(neon[1].sprite, BrushSprite.hard);
    expect(neon[1].radiusScale, 0.45);
    expect(neon[1].tint, 0.7);
    expect(DrawingTool.stampStar.spec.stamp, StampShape.star);
    expect(DrawingTool.stampHeart.spec.stamp, StampShape.heart);
    expect(DrawingTool.fill.spec.kind, BrushKind.fill);
    for (final t in DrawingTool.values) {
      if (t != DrawingTool.watercolor) {
        expect(t.spec.bleed, isFalse, reason: t.name);
      }
      if (t != DrawingTool.neon) {
        expect(t.spec.passes, hasLength(1), reason: t.name);
      }
    }
  });

  test('the new paid tools', () {
    for (final t in [
      DrawingTool.crayon,
      DrawingTool.chalk,
      DrawingTool.dotted,
      DrawingTool.glitter,
      DrawingTool.calligraphy,
    ]) {
      expect(t.isFree, isFalse, reason: t.name);
    }
    final crayon = DrawingTool.crayon.spec;
    final pastel = DrawingTool.pastel.spec;
    expect(crayon.sprite, BrushSprite.grain0);
    expect(crayon.spriteVariants, 4);
    // Denser than pastel, but capped below solid so the grain shows.
    expect(
      crayon.dabAlpha * crayon.layerOpacity,
      greaterThan(pastel.dabAlpha * pastel.layerOpacity),
    );
    expect(crayon.spacing, lessThan(pastel.spacing));
    expect(crayon.layerOpacity, lessThan(1));
    expect(DrawingTool.chalk.spec.layerOpacity, lessThan(1));
    expect(DrawingTool.chalk.spec.passes.single.tint, greaterThan(0));
    expect(DrawingTool.chalk.spec.scatter, greaterThan(pastel.scatter));
    final dotted = DrawingTool.dotted.spec;
    expect(dotted.pressureScale(0), dotted.pressureScale(1));
    expect(dotted.spacing, greaterThanOrEqualTo(1));
    final glitter = DrawingTool.glitter.spec;
    expect(glitter.sprayDensity, greaterThan(0));
    expect(glitter.colorJitter, greaterThan(0));
    expect(glitter.sparkle, inExclusiveRange(0, 1));
    expect(glitter.minSprayDots, greaterThanOrEqualTo(3));
    final calligraphy = DrawingTool.calligraphy.spec;
    expect(calligraphy.sprite, BrushSprite.flat);
    expect(calligraphy.fixedRotation, isNot(0));
    expect(calligraphy.rotationJitter, 0);
    for (final t in DrawingTool.values) {
      if (t != DrawingTool.glitter) {
        expect(t.spec.colorJitter, 0, reason: t.name);
        expect(t.spec.sparkle, 0, reason: t.name);
      }
      if (t != DrawingTool.calligraphy) {
        expect(t.spec.fixedRotation, 0, reason: t.name);
      }
    }
  });

  test('groups', () {
    expect(DrawingTool.values.where((t) => t.group == ToolGroup.basic), [
      DrawingTool.pencil,
      DrawingTool.felt,
      DrawingTool.marker,
      DrawingTool.eraser,
    ]);
    expect(DrawingTool.fill.group, ToolGroup.magic);
  });
}
