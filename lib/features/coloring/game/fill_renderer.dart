import 'dart:ui' as ui;

import '../model/fill_state.dart';
import '../model/picture_meta.dart';

/// Asset path of the fill shader, declared under `flutter: shaders:`.
const fillShaderAsset = 'shaders/coloring.frag';

/// Everything a [FillRenderer] needs besides the destination rect. Mutable
/// on purpose: the game keeps one instance and updates its fields, so a
/// frame allocates nothing.
///
/// Colors are ARGB ints; 0 means unfilled and is drawn white.
class FillUniforms {
  /// Current state texture from `buildStateTexture`. The renderer only
  /// borrows it; whoever built it disposes it.
  ui.Image? stateTexture;

  /// Current fill state, used by [FlatFillRenderer].
  FillState? fill;

  /// Region of the running wave, 0 = none.
  int waveId = 0;

  /// Wave center, image px.
  double waveX = 0;
  double waveY = 0;

  /// Wave radius, image px. Use a huge value (not infinity) for an
  /// instant fill.
  double waveRadius = 0;

  /// Color outside the wave front (the region's previous color).
  int waveOldColor = 0;

  /// Color inside the wave front (the region's new color).
  int waveNewColor = 0;

  /// Palette index tinted where not yet correct, -1 = none.
  int highlightPalette = -1;

  /// Highlight pulse 0..1.
  double pulse = 0.5;

  /// Region of the reject flash, 0 = none.
  int flashId = 0;

  /// Flash strength 0..1.
  double flashAmount = 0;
}

/// Draws the fills of a picture into [imageRect] (the whole image in canvas
/// coordinates, `scale` = canvas px per image px). Lines are drawn on top
/// by the caller.
abstract interface class FillRenderer {
  void paint(ui.Canvas canvas, ui.Rect imageRect, double scale, FillUniforms u);
}

/// Renders with `shaders/coloring.frag` (spec §3). Borrows [regions]; the
/// owner of the image keeps it alive while this renderer is used.
class ShaderFillRenderer implements FillRenderer {
  ShaderFillRenderer(ui.FragmentProgram program, this.regions)
    : _shader = program.fragmentShader();

  /// Loads the shader program; the engine caches it per asset.
  static Future<ui.FragmentProgram> loadProgram() =>
      ui.FragmentProgram.fromAsset(fillShaderAsset);

  /// Number of float uniforms, in the order documented in the shader.
  static const uniformCount = 24;

  final ui.Image regions;
  final ui.FragmentShader _shader;
  final _paint = ui.Paint();

  @override
  void paint(
    ui.Canvas canvas,
    ui.Rect imageRect,
    double scale,
    FillUniforms u,
  ) {
    final state = u.stateTexture;
    if (state == null) return;
    final s = _shader;
    s
      ..setFloat(0, imageRect.width)
      ..setFloat(1, imageRect.height)
      ..setFloat(2, imageRect.left)
      ..setFloat(3, imageRect.top)
      ..setFloat(4, scale)
      ..setFloat(5, regions.width.toDouble())
      ..setFloat(6, regions.height.toDouble())
      ..setFloat(7, state.width.toDouble())
      ..setFloat(8, u.waveId.toDouble())
      ..setFloat(9, u.waveX)
      ..setFloat(10, u.waveY)
      ..setFloat(11, u.waveRadius);
    _setColor(12, u.waveOldColor);
    _setColor(16, u.waveNewColor);
    s
      ..setFloat(20, u.highlightPalette.toDouble())
      ..setFloat(21, u.pulse)
      ..setFloat(22, u.flashId.toDouble())
      ..setFloat(23, u.flashAmount)
      ..setImageSampler(0, regions, filterQuality: ui.FilterQuality.none)
      ..setImageSampler(1, state, filterQuality: ui.FilterQuality.none);
    // Assigned after the samplers: the engine rejects a shader without them.
    _paint.shader = s;
    canvas.drawRect(imageRect, _paint);
  }

  void _setColor(int index, int argb) {
    final c = argb == 0 ? 0xFFFFFFFF : argb;
    _shader
      ..setFloat(index, (c >> 16 & 0xFF) / 255)
      ..setFloat(index + 1, (c >> 8 & 0xFF) / 255)
      ..setFloat(index + 2, (c & 0xFF) / 255)
      ..setFloat(index + 3, (c >> 24 & 0xFF) / 255);
  }

  /// Releases the shader. [regions] stays with its owner.
  void dispose() => _shader.dispose();
}

/// Fallback without a shader, for widget tests: a white rect plus each
/// filled region's bounding box in its color.
class FlatFillRenderer implements FillRenderer {
  FlatFillRenderer(this.meta);

  final PictureMeta meta;
  final _paint = ui.Paint();

  @override
  void paint(
    ui.Canvas canvas,
    ui.Rect imageRect,
    double scale,
    FillUniforms u,
  ) {
    _paint.color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(imageRect, _paint);
    final fill = u.fill;
    if (fill == null) return;
    for (final region in meta.regions) {
      final color = fill.colorOf(region.id);
      if (color == 0) continue;
      _paint.color = ui.Color(color);
      canvas.drawRect(
        ui.Rect.fromLTWH(
          imageRect.left + region.bboxX * scale,
          imageRect.top + region.bboxY * scale,
          region.bboxWidth * scale,
          region.bboxHeight * scale,
        ),
        _paint,
      );
    }
  }
}
