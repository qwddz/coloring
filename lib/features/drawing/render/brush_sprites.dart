import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/drawing_tool.dart';

/// Side of one sprite cell in pixels. A dab of radius r is drawn by scaling
/// a cell to 2r; 128 keeps hard edges crisp up to the huge brush.
const int spriteCellSize = 128;

/// The atlas holds one row of cells, one per [BrushSprite] in enum order.
final int spriteAtlasWidth = spriteCellSize * BrushSprite.values.length;
const int spriteAtlasHeight = spriteCellSize;

/// Radius, in texels, of the shape in each cell (the unit circle of the
/// dab). The antialiased rim and a 2-texel transparent margin lie outside
/// it, so bilinear sampling never reads a neighbor cell. A dab of radius r
/// scales the cell by `r / spriteShapeRadius`.
const double spriteShapeRadius = spriteCellSize / 2 - 3;

/// Seed of the sprite noise: the atlas is the same on every run.
const int _spriteSeed = 0x5EED;

/// The sprite atlas: premultiplied white with the brush shape in alpha, so
/// `BlendMode.modulate` with a per-dab color gives that color at the
/// sprite's coverage.
class BrushSprites {
  BrushSprites(this.atlas)
    : assert(atlas.width == spriteAtlasWidth),
      assert(atlas.height == spriteAtlasHeight);

  final ui.Image atlas;

  /// Builds the atlas from [brushSpritePixels].
  static Future<BrushSprites> create() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(brushSpritePixels());
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: spriteAtlasWidth,
      height: spriteAtlasHeight,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        final frame = await codec.getNextFrame();
        return BrushSprites(frame.image);
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  /// The atlas cell of [sprite]; [variant] steps to the following cells
  /// (pastel's grain variants).
  ui.Rect cell(BrushSprite sprite, [int variant = 0]) {
    final index = (sprite.index + variant).clamp(
      0,
      BrushSprite.values.length - 1,
    );
    return ui.Rect.fromLTWH(
      (index * spriteCellSize).toDouble(),
      0,
      spriteCellSize.toDouble(),
      spriteCellSize.toDouble(),
    );
  }

  void dispose() => atlas.dispose();
}

/// Generated once per run and kept; the image is released with the
/// container.
final brushSpritesProvider = FutureProvider<BrushSprites>((ref) async {
  final sprites = await BrushSprites.create();
  ref.onDispose(sprites.dispose);
  return sprites;
});

/// The atlas pixels, deterministic: premultiplied RGBA (white, so every
/// channel equals the alpha), which is what `ImageDescriptor.raw` expects.
///
/// Every shape fits the circle of [spriteShapeRadius] in its cell, so a dab
/// of radius r never paints farther than r from its center.
Uint8List brushSpritePixels() {
  final pixels = Uint8List(spriteAtlasWidth * spriteAtlasHeight * 4);
  final random = Random(_spriteSeed);
  for (final sprite in BrushSprite.values) {
    final coverage = _coverage(sprite, random);
    final x0 = sprite.index * spriteCellSize;
    for (var y = 0; y < spriteCellSize; y++) {
      for (var x = 0; x < spriteCellSize; x++) {
        final o = (y * spriteAtlasWidth + x0 + x) * 4;
        final a = (coverage[y * spriteCellSize + x] * 255).round().clamp(
          0,
          255,
        );
        pixels
          ..[o] = a
          ..[o + 1] = a
          ..[o + 2] = a
          ..[o + 3] = a;
      }
    }
  }
  return pixels;
}

/// Alpha 0..1 of one cell, row-major.
Float64List _coverage(BrushSprite sprite, Random random) {
  const n = spriteCellSize;
  const c = n / 2;
  const r = spriteShapeRadius;
  final out = Float64List(n * n);

  // Per-cell random inputs are drawn up front, in a fixed order.
  final grain = switch (sprite) {
    BrushSprite.grain0 ||
    BrushSprite.grain1 ||
    BrushSprite.grain2 ||
    BrushSprite.grain3 => _grain(random),
    _ => null,
  };
  final phases = sprite == BrushSprite.blot
      ? [for (var i = 0; i < 4; i++) random.nextDouble() * 2 * pi]
      : null;

  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final dx = x + 0.5 - c;
      final dy = y + 0.5 - c;
      final d = sqrt(dx * dx + dy * dy) / r;
      out[y * n + x] = switch (sprite) {
        BrushSprite.hard || BrushSprite.dot => _edge(d, 1.2 / r),
        // Solid core, smooth falloff over the outer 40 %.
        BrushSprite.soft => 1 - _smoothstep(0.6, 1, d),
        BrushSprite.grain0 ||
        BrushSprite.grain1 ||
        BrushSprite.grain2 ||
        BrushSprite.grain3 =>
          _edge(d, 1.2 / r) * grain![(y ~/ 2) * (n ~/ 2) + x ~/ 2],
        BrushSprite.blot => _blot(d, atan2(dy, dx), phases!),
        BrushSprite.flat => _flat(dx, dy, r),
      };
    }
  }
  return out;
}

/// Coarse (2 × 2 px) paper grain, 0.15..1.
Float64List _grain(Random random) {
  const half = spriteCellSize ~/ 2;
  final g = Float64List(half * half);
  for (var i = 0; i < g.length; i++) {
    final v = random.nextDouble();
    g[i] = 0.15 + 0.85 * v * v;
  }
  return g;
}

/// A wobbly disk, lighter inside with a darker rim (pigment pooling at the
/// edge of a wet blot).
double _blot(double d, double angle, List<double> phases) {
  final wobble =
      0.06 * sin(3 * angle + phases[0]) +
      0.04 * sin(5 * angle + phases[1]) +
      0.03 * sin(7 * angle + phases[2]) +
      0.02 * sin(11 * angle + phases[3]);
  final edge = 0.85 + wobble; // ≤ 1, so the blot stays inside the circle
  final rd = d / edge;
  final inside = 1 - _smoothstep(0.9, 1, rd);
  final rim = 0.55 + 0.45 * _smoothstep(0.55, 0.95, rd);
  return inside * rim;
}

/// Half-height of the flat nib relative to the unit radius.
const double _flatAspect = 0.22;

/// A thin horizontal capsule across the full width of the unit disk (the
/// calligraphy nib): straight long sides and round ends, so dabs spaced
/// along a stroke leave smooth edges. The rim is a 1.2-texel ramp of the
/// exact distance to the capsule.
double _flat(double dx, double dy, double r) {
  final half = _flatAspect * r;
  final ex = max(0.0, dx.abs() - (r - half));
  final distance = sqrt(ex * ex + dy * dy) - half;
  return (-distance / 1.2 + 0.5).clamp(0.0, 1.0);
}

/// 1 inside the unit disk, 0 outside, a linear ramp of [width] at the edge.
double _edge(double d, double width) => ((1 - d) / width + 0.5).clamp(0.0, 1.0);

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}
