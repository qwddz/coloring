import 'dart:math';

import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/drawing/render/brush_sprites.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int alphaAt(List<int> pixels, BrushSprite sprite, int x, int y) =>
      pixels[(y * spriteAtlasWidth + sprite.index * spriteCellSize + x) * 4 +
          3];

  test('the atlas bytes are deterministic', () {
    final a = brushSpritePixels();
    final b = brushSpritePixels();
    expect(a, hasLength(spriteAtlasWidth * spriteAtlasHeight * 4));
    expect(a, b);
  });

  test('every cell is premultiplied white with a transparent border', () {
    final pixels = brushSpritePixels();
    for (var i = 0; i < pixels.length; i += 4) {
      expect(pixels[i], pixels[i + 3]);
      expect(pixels[i + 1], pixels[i + 3]);
      expect(pixels[i + 2], pixels[i + 3]);
    }
    for (final sprite in BrushSprite.values) {
      for (var t = 0; t < spriteCellSize; t++) {
        for (final (x, y) in [
          (t, 0),
          (t, 1),
          (t, spriteCellSize - 1),
          (t, spriteCellSize - 2),
          (0, t),
          (1, t),
          (spriteCellSize - 1, t),
          (spriteCellSize - 2, t),
        ]) {
          expect(alphaAt(pixels, sprite, x, y), 0, reason: '$sprite ($x, $y)');
        }
      }
    }
  });

  test('shapes: solid hard center, soft falloff, distinct grains', () {
    final pixels = brushSpritePixels();
    const c = spriteCellSize ~/ 2;
    expect(alphaAt(pixels, BrushSprite.hard, c, c), 255);
    expect(alphaAt(pixels, BrushSprite.hard, c + 50, c), 255);
    expect(alphaAt(pixels, BrushSprite.soft, c, c), 255);
    final softEdge = alphaAt(pixels, BrushSprite.soft, c + 50, c);
    expect(softEdge, inExclusiveRange(0, 255));
    List<int> cell(BrushSprite s) => [
      for (var y = 0; y < spriteCellSize; y++)
        for (var x = 0; x < spriteCellSize; x++) alphaAt(pixels, s, x, y),
    ];
    final grains = [
      cell(BrushSprite.grain0),
      cell(BrushSprite.grain1),
      cell(BrushSprite.grain2),
      cell(BrushSprite.grain3),
    ];
    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        expect(grains[i], isNot(grains[j]));
      }
    }
  });

  test('the atlas has one cell per sprite', () {
    expect(spriteAtlasWidth, spriteCellSize * BrushSprite.values.length);
    expect(BrushSprite.values.last, BrushSprite.flat);
  });

  test('the flat nib fits the unit circle and is wider than tall', () {
    final pixels = brushSpritePixels();
    const c = spriteCellSize / 2;
    var minX = spriteCellSize, maxX = -1, minY = spriteCellSize, maxY = -1;
    for (var y = 0; y < spriteCellSize; y++) {
      for (var x = 0; x < spriteCellSize; x++) {
        if (alphaAt(pixels, BrushSprite.flat, x, y) == 0) continue;
        final d = sqrt(pow(x + 0.5 - c, 2) + pow(y + 0.5 - c, 2));
        expect(d, lessThanOrEqualTo(spriteShapeRadius + 1), reason: '($x, $y)');
        minX = min(minX, x);
        maxX = max(maxX, x);
        minY = min(minY, y);
        maxY = max(maxY, y);
      }
    }
    expect(alphaAt(pixels, BrushSprite.flat, c.toInt(), c.toInt()), 255);
    final width = maxX - minX + 1;
    final height = maxY - minY + 1;
    expect(width, greaterThan(spriteShapeRadius * 1.9));
    expect(height, lessThan(width / 3));
  });

  test('the image matches the bytes', () async {
    final sprites = await BrushSprites.create();
    addTearDown(sprites.dispose);
    expect(sprites.atlas.width, spriteAtlasWidth);
    expect(sprites.atlas.height, spriteAtlasHeight);
    // `rawRgba` reads premultiplied bytes back, as they were given.
    expect(await pixelsOf(sprites.atlas), brushSpritePixels());
    expect(
      sprites.cell(BrushSprite.grain0, 3),
      sprites.cell(BrushSprite.grain3),
    );
  });
}
