import 'dart:math';

import 'stamp_shapes.dart';

export 'stamp_shapes.dart' show StampShape;

/// Drawing canvas size in pixels (4:3, same as the coloring layers). Saved
/// drawings of another size are scaled into it on load.
const int drawingCanvasWidth = 2048;
const int drawingCanvasHeight = 1536;

/// Opaque white, the canvas background and the eraser color.
const int drawingWhite = 0xFFFFFFFF;

/// Cells of the generated brush sprite atlas.
enum BrushSprite { hard, soft, grain0, grain1, grain2, grain3, blot, dot }

/// Where a dab's color comes from.
enum BrushColorMode { selected, white, rainbow }

/// What a tool produces: sprite dabs, filled stamp outlines, or a flood fill
/// (no dabs at all).
enum BrushKind { dabs, stamps, fill }

/// One `drawAtlas` pass of a stroke. Every sample point of the stroke yields
/// one dab per pass.
class BrushPass {
  const BrushPass({
    required this.sprite,
    this.radiusScale = 1,
    this.alpha = 1,
    this.tint = 0,
  });

  final BrushSprite sprite;

  /// Dab radius relative to the stroke radius at that point.
  final double radiusScale;

  /// Multiplies the tool's `dabAlpha`.
  final double alpha;

  /// How much the color is mixed with white (0 = the color, 1 = white).
  final double tint;
}

/// How a tool turns stroke points into dabs (spec §5, table §8).
class BrushSpec {
  const BrushSpec({
    required this.passes,
    this.radiusFactor = 1,
    this.spacing = 0.12,
    this.dabAlpha = 1,
    this.layerOpacity = 1,
    this.minPressureScale = 0.7,
    this.maxPressureScale = 1,
    this.spriteVariants = 1,
    this.rotationJitter = 0,
    this.sizeJitter = 0,
    this.scatter = 0,
    this.colorMode = BrushColorMode.selected,
    this.kind = BrushKind.dabs,
    this.bleed = false,
    this.sprayDensity = 0,
    this.dotScale = 0,
    this.stamp,
  });

  /// Stroke radius = `BrushSize.width / 2 × radiusFactor` (before pressure).
  final double radiusFactor;

  /// Distance between dabs as a fraction of the dab diameter.
  final double spacing;
  final double dabAlpha;

  /// Opacity of the bounded layer the whole stroke is drawn into
  /// (1 = no layer).
  final double layerOpacity;

  /// Pressure 0 → [minPressureScale] × radius, pressure 1 →
  /// [maxPressureScale] × radius (touch input has pressure 1).
  final double minPressureScale;
  final double maxPressureScale;

  /// Number of consecutive sprite cells starting at the pass sprite that a
  /// dab picks from at random (pastel: the 4 grain cells).
  final int spriteVariants;

  /// Max rotation offset in radians, uniform in ±[rotationJitter].
  final double rotationJitter;

  /// Max relative size change, uniform in ±[sizeJitter].
  final double sizeJitter;

  /// Max offset of a dab from the path, as a fraction of its radius.
  final double scatter;
  final BrushColorMode colorMode;
  final List<BrushPass> passes;
  final BrushKind kind;

  /// Blur the stroke layer (σ = 0.25 r) when committing (watercolor).
  final bool bleed;

  /// Airbrush: each sample point sprays `round(sprayDensity × radius)` dots
  /// (at least 1) of radius `max(1, dotScale × radius)` uniformly in the
  /// disk of the stroke radius. 0 = no spray.
  final double sprayDensity;
  final double dotScale;

  /// The outline for [BrushKind.stamps].
  final StampShape? stamp;

  /// The main sprite (of the first pass).
  BrushSprite get sprite => passes.first.sprite;

  double pressureScale(double pressure) =>
      minPressureScale +
      (maxPressureScale - minPressureScale) * pressure.clamp(0.0, 1.0);
}

/// Tool groups of the drawing panel (spec §0).
enum ToolGroup { basic, fun, artistic, magic }

const double _deg20 = 20 * pi / 180;

/// The drawing tools in panel order; persisted by [name].
enum DrawingTool {
  pencil(
    ToolGroup.basic,
    isFree: true,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.hard)],
      radiusFactor: 0.5,
      spacing: 0.15,
      minPressureScale: 0.5,
      maxPressureScale: 1.2,
    ),
  ),
  felt(
    ToolGroup.basic,
    isFree: true,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.soft)],
      spacing: 0.12,
    ),
  ),
  marker(
    ToolGroup.basic,
    isFree: true,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.hard)],
      radiusFactor: 1.4,
      spacing: 0.1,
      layerOpacity: 0.5,
    ),
  ),
  eraser(
    ToolGroup.basic,
    isFree: true,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.hard)],
      radiusFactor: 1.2,
      spacing: 0.1,
      colorMode: BrushColorMode.white,
    ),
  ),
  rainbow(
    ToolGroup.fun,
    isFree: true,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.soft)],
      spacing: 0.12,
      colorMode: BrushColorMode.rainbow,
    ),
  ),
  pastel(
    ToolGroup.artistic,
    isFree: false,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.grain0)],
      spacing: 0.2,
      dabAlpha: 0.55,
      spriteVariants: 4,
      rotationJitter: pi,
      sizeJitter: 0.1,
      scatter: 0.08,
    ),
  ),
  watercolor(
    ToolGroup.artistic,
    isFree: false,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.blot)],
      radiusFactor: 1.2,
      spacing: 0.15,
      dabAlpha: 0.8,
      layerOpacity: 0.35,
      rotationJitter: pi,
      sizeJitter: 0.1,
      bleed: true,
    ),
  ),
  airbrush(
    ToolGroup.artistic,
    isFree: false,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.dot)],
      radiusFactor: 1.6,
      spacing: 0.25,
      dabAlpha: 0.25,
      sprayDensity: 0.6,
      dotScale: 0.06,
    ),
  ),
  neon(
    ToolGroup.fun,
    isFree: false,
    spec: BrushSpec(
      passes: [
        BrushPass(sprite: BrushSprite.soft, radiusScale: 2.2, alpha: 0.35),
        BrushPass(sprite: BrushSprite.hard, radiusScale: 0.45, tint: 0.7),
      ],
      spacing: 0.12,
    ),
  ),
  stampStar(
    ToolGroup.fun,
    isFree: false,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.hard)],
      radiusFactor: 1,
      spacing: 1.6,
      minPressureScale: 1,
      rotationJitter: _deg20,
      sizeJitter: 0.15,
      kind: BrushKind.stamps,
      stamp: StampShape.star,
    ),
  ),
  stampHeart(
    ToolGroup.fun,
    isFree: false,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.hard)],
      radiusFactor: 1,
      spacing: 1.6,
      minPressureScale: 1,
      rotationJitter: _deg20,
      sizeJitter: 0.15,
      kind: BrushKind.stamps,
      stamp: StampShape.heart,
    ),
  ),
  fill(
    ToolGroup.magic,
    isFree: false,
    spec: BrushSpec(
      passes: [BrushPass(sprite: BrushSprite.hard)],
      kind: BrushKind.fill,
    ),
  );

  const DrawingTool(this.group, {required this.isFree, required this.spec});

  final ToolGroup group;

  /// Usable without the full version (D4: the basic group and rainbow).
  final bool isFree;
  final BrushSpec spec;

  /// The tool with [name], or null.
  static DrawingTool? fromName(Object? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }
}
