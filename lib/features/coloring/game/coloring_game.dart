import 'dart:math' show Point, max, min;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';

import '../data/picture_loader.dart';
import '../model/canvas_sink.dart';
import '../model/fill_state.dart';
import '../model/label_layout.dart';
import '../model/picture_meta.dart';
import '../model/viewport.dart';
import '../perf/fill_latency_probe.dart';
import 'fill_animations.dart';
import 'fill_renderer.dart';
import 'labels_component.dart';
import 'picture_component.dart';
import 'state_texture.dart';

/// Builds the renderer for the game's own copy of `regions.png`.
typedef FillRendererFactory = FillRenderer Function(ui.Image regions);

/// The coloring canvas (spec §4): fills, lines and numbers under a zoomable
/// [Viewport]. It has no business logic: the controller pushes changes in
/// through [ColoringCanvasSink], and `ColoringCanvas` reports touches out.
///
/// The game keeps its own `clone()` of the picture images and its own state
/// textures, and disposes them in [onRemove]; the [LoadedPicture] handles
/// stay with their owner. A removed game ignores every further call, so it
/// is never re-attached: create a new game for a new `GameWidget`.
class ColoringGame extends FlameGame implements ColoringCanvasSink {
  ColoringGame({
    required LoadedPicture picture,
    required FillRendererFactory createRenderer,
    FillState? fill,
    this.labelsEnabled = false,
    int? highlightPalette,
    this.reducedMotion = false,
  }) : meta = picture.meta,
       regionsImage = picture.regionsImage.clone(),
       linesImage = picture.linesImage.clone(),
       _smallestLabelRadius = picture.meta.regions.fold(
         double.infinity,
         (r, region) => min(r, region.labelRadius),
       ) {
    renderer = createRenderer(regionsImage);
    _fill = fill ?? FillState(meta.regionCount);
    uniforms
      ..fill = _fill
      ..stateTexture = buildStateTexture(_fill, meta)
      ..highlightPalette = highlightPalette ?? -1;
  }

  final PictureMeta meta;

  /// The game's own handles; disposed in [onRemove].
  final ui.Image regionsImage;
  final ui.Image linesImage;

  late final FillRenderer renderer;

  /// Shared with the renderer; updated in place, never reallocated.
  final FillUniforms uniforms = FillUniforms();

  final WaveAnimation wave = WaveAnimation();
  final FlashAnimation flash = FlashAnimation();

  /// System "remove animations": instant fills, a still pulse, no wiggle.
  bool reducedMotion;

  /// Numbers are drawn (numbers mode).
  bool labelsEnabled;

  /// Length of the "find" move.
  static const Duration focusDuration = Duration(milliseconds: 400);

  /// "Find" zooms in until the label radius is this many times the
  /// visibility threshold.
  static const double focusLabelMargin = 1.5;

  /// Image px; sets the per-picture max zoom ([maxZoomFor]).
  final double _smallestLabelRadius;

  late FillState _fill;
  double _pulseTime = 0;
  bool _removed = false;
  Viewport? _viewport;
  ui.Rect _imageRect = ui.Rect.zero;
  late final LabelsComponent _labels = LabelsComponent();
  _FocusMove? _focus;
  int _focusedId = 0;

  /// Regions "find" already went to in this round.
  final Set<int> _visited = {};
  bool _gestureActive = false;

  FillState get fill => _fill;

  /// True once [onRemove] released the images.
  bool get isDisposed => _removed;

  /// Palette index highlighted in numbers mode, null = none.
  int? get highlightPalette =>
      uniforms.highlightPalette < 0 ? null : uniforms.highlightPalette;

  /// Null until the game has a size.
  Viewport? get viewport => _viewport;

  set viewport(Viewport? value) {
    _viewport = value;
    _imageRect = value == null
        ? ui.Rect.zero
        : ui.Rect.fromLTWH(
            value.origin.x,
            value.origin.y,
            value.imageWidth * value.scale,
            value.imageHeight * value.scale,
          );
  }

  /// The whole image in canvas coordinates.
  ui.Rect get imageRect => _imageRect;

  /// A finger is on the canvas: "find" is ignored, and a running move stops,
  /// so it never fights a pan or pinch. Set by `ColoringCanvas`.
  bool get gestureActive => _gestureActive;

  set gestureActive(bool value) {
    _gestureActive = value;
    if (value) _focus = null;
  }

  /// A "find" move is running.
  @visibleForTesting
  bool get focusing => _focus != null;

  /// The region "find" went to last, 0 = none.
  @visibleForTesting
  int get focusedRegion => _focusedId;

  /// Labels drawn in the last frame. For tests.
  @visibleForTesting
  int get drawnLabels => _labels.drawnCount;

  @override
  ui.Color backgroundColor() => const ui.Color(0x00000000);

  @override
  Future<void> onLoad() async {
    add(PictureComponent());
    add(_labels..priority = 1);
    if (coloringPerfOverlay) {
      add(FpsTextComponent(position: Vector2.all(8))..priority = 2);
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final old = _viewport;
    final baseScale = min(size.x / meta.width, size.y / meta.height);
    viewport = Viewport(
      canvasWidth: size.x,
      canvasHeight: size.y,
      imageWidth: meta.width.toDouble(),
      imageHeight: meta.height.toDouble(),
      // Enough zoom for the smallest number to show, within the cap.
      maxZoom: maxZoomFor(_smallestLabelRadius, baseScale),
      zoom: old?.zoom ?? minZoom,
      pan: old?.pan ?? const Point(0, 0),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    wave.advance(dt);
    flash.advance(dt);
    _advanceFocus(dt);
    if (uniforms.highlightPalette >= 0 && !reducedMotion) {
      _pulseTime += dt;
    }
    _syncUniforms();
  }

  void _advanceFocus(double dt) {
    final f = _focus;
    final v = _viewport;
    if (f == null || v == null) return;
    f.t = min(
      1.0,
      f.t + dt * Duration.microsecondsPerSecond / focusDuration.inMicroseconds,
    );
    final e = Curves.easeInOut.transform(f.t);
    // Recomputed every frame, so a resize mid-move uses the new fit scale
    // and max zoom.
    final toZoom = _focusZoom(v, f.fromZoom, f.labelRadius);
    viewport = v.focusOn(
      Point(
        f.from.x + (f.to.x - f.from.x) * e,
        f.from.y + (f.to.y - f.from.y) * e,
      ),
      f.fromZoom + (toZoom - f.fromZoom) * e,
    );
    if (f.t >= 1) _focus = null;
  }

  /// "Find" zoom for a label of [labelRadius] image px: enough for the
  /// number to show with a margin, never below [startZoom].
  static double _focusZoom(Viewport v, double startZoom, double labelRadius) =>
      max(
        startZoom,
        labelMinVisibleRadiusDp *
            focusLabelMargin /
            (labelRadius * v.baseScale),
      ).clamp(minZoom, v.maxZoom).toDouble();

  /// Stops a running "find" move where it is.
  void cancelFocus() => _focus = null;

  void _syncUniforms() {
    uniforms
      ..waveId = wave.regionId
      ..waveX = wave.x
      ..waveY = wave.y
      ..waveRadius = wave.radius
      ..waveOldColor = wave.oldColor
      ..waveNewColor = wave.newColor
      ..flashId = flash.regionId
      ..flashAmount = flash.amount
      ..pulse = reducedMotion ? 0.5 : pulseAt(_pulseTime);
  }

  @override
  void showFill(
    FillState state,
    List<RegionChange> changes, {
    double? waveX,
    double? waveY,
  }) {
    if (_removed) return;
    _fill = state;
    // Installed in the same frame as the change; the wave only animates
    // the transition on top of it.
    final old = uniforms.stateTexture;
    uniforms
      ..fill = state
      ..stateTexture = buildStateTexture(state, meta);
    old?.dispose();
    if (waveX != null && waveY != null && changes.length == 1) {
      final change = changes.single;
      final r = meta.region(change.id);
      wave.startWave(
        regionId: change.id,
        x: waveX,
        y: waveY,
        maxRadius: waveMaxRadius(
          waveX,
          waveY,
          r.bboxX,
          r.bboxY,
          r.bboxWidth,
          r.bboxHeight,
        ),
        oldColor: change.before,
        newColor: change.after,
        instant: reducedMotion,
      );
    } else {
      // A running wave or hint finishes at once: the texture is current.
      wave.stop();
    }
    _syncUniforms();
  }

  @override
  void setHighlight(int? paletteIndex) {
    if (_removed) return;
    uniforms.highlightPalette = paletteIndex ?? -1;
    _pulseTime = 0;
    _syncUniforms();
  }

  @override
  void setLabelsEnabled(bool enabled) {
    if (_removed) return;
    labelsEnabled = enabled;
  }

  @override
  void flashRejected(int regionId) {
    if (_removed) return;
    flash.start(regionId);
    _syncUniforms();
  }

  @override
  void showHint(int regionId, int color) {
    if (_removed) return;
    wave.startHint(
      regionId: regionId,
      oldColor: _fill.colorOf(regionId),
      color: color,
    );
    _syncUniforms();
  }

  /// Goes to the not yet visited candidate whose label is nearest to the
  /// view center, so repeated taps visit every region before any repeats.
  /// Once all are visited a new round starts, without the current region
  /// when there is a choice. Ignored while a finger is on the canvas.
  @override
  void focusOn(List<int> regionIds) {
    final v = _viewport;
    if (_removed || _gestureActive || v == null || regionIds.isEmpty) return;
    // Colored regions drop out of the candidates, and out of the round.
    _visited.retainAll(regionIds);
    if (regionIds.every(_visited.contains)) {
      _visited.clear();
      if (regionIds.length > 1) _visited.add(_focusedId);
    }
    final center = v.screenToImage(
      Point(v.canvasWidth / 2, v.canvasHeight / 2),
    );
    var best = 0;
    var bestDistance = double.infinity;
    for (final id in regionIds) {
      if (_visited.contains(id)) continue;
      final r = meta.region(id);
      final dx = r.labelX - center.x;
      final dy = r.labelY - center.y;
      final d = dx * dx + dy * dy;
      if (d < bestDistance) {
        best = id;
        bestDistance = d;
      }
    }
    if (best == 0) return;
    _focusedId = best;
    _visited.add(best);
    final r = meta.region(best);
    final to = Point(r.labelX, r.labelY);
    if (reducedMotion) {
      _focus = null;
      viewport = v.focusOn(to, _focusZoom(v, v.zoom, r.labelRadius));
      return;
    }
    _focus = _FocusMove(
      from: center,
      fromZoom: v.zoom,
      to: to,
      labelRadius: r.labelRadius,
    );
  }

  @override
  void onRemove() {
    if (!_removed) {
      _removed = true;
      final r = renderer;
      if (r is ShaderFillRenderer) r.dispose();
      uniforms.stateTexture?.dispose();
      uniforms.stateTexture = null;
      regionsImage.dispose();
      linesImage.dispose();
      _labels.disposeCache();
    }
    super.onRemove();
  }
}

/// A running "find" move: view center (image px) and zoom, eased over
/// [ColoringGame.focusDuration]. The target zoom comes from [labelRadius].
class _FocusMove {
  _FocusMove({
    required this.from,
    required this.fromZoom,
    required this.to,
    required this.labelRadius,
  });

  final Point<double> from;
  final double fromZoom;
  final Point<double> to;

  /// The target label's radius, image px.
  final double labelRadius;

  /// Progress 0..1.
  double t = 0;
}
