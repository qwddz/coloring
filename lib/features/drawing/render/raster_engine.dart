import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../model/drawing_history.dart';
import '../model/drawing_tool.dart';
import '../model/stroke.dart';
import 'brush_painter.dart';
import 'brush_sprites.dart';
import 'draw_op.dart';

/// Flatten interval F: every F-th new image (and every checkpoint) is
/// replaced by a fully rasterized copy, so the `toImageSync` chain never
/// keeps old pictures alive (spec §6.6, device spike).
const int defaultFlattenEvery = 10;

/// Live dabs beyond this many are baked into the live layer's image.
const int liveBakeThreshold = 128;

/// The drawing raster (spec §6.2–6.6): the committed image, undo/redo
/// through [DrawingHistory] checkpoints, live stroke layers, readback for
/// the flood fill and PNG encoding.
///
/// Every operation that changes or reads the committed image runs in one
/// queue, in call order. A commit is drawn with `toImageSync` and shown at
/// once; every [flattenEvery]-th new image and every checkpoint is then
/// copied with `await picture.toImage` (a picture of just that image, so the
/// copy has exactly its pixels and none of its source pictures) and swapped
/// in, and the queue waits for that before the next operation. Live strokes are drawn
/// outside the queue and are never delayed.
///
/// The engine owns every image it creates and disposes each one when no
/// longer referenced; [liveImageCount] counts them for tests.
class RasterEngine extends ChangeNotifier {
  RasterEngine._(
    this.sprites,
    ui.Image initial, {
    required this.width,
    required this.height,
    required this.flattenEvery,
    required int checkpointEvery,
  }) : _history = DrawingHistory(
         initial: initial,
         checkpointEvery: checkpointEvery,
       ) {
    _track(initial);
  }

  /// An engine with a white canvas, or with the image in [bytes] (PNG or
  /// any codec format) scaled to the canvas when its size differs. Throws
  /// when [bytes] cannot be decoded.
  static Future<RasterEngine> create({
    required BrushSprites sprites,
    Uint8List? bytes,
    int width = drawingCanvasWidth,
    int height = drawingCanvasHeight,
    int flattenEvery = defaultFlattenEvery,
    int checkpointEvery = defaultCheckpointEvery,
  }) async {
    final initial = bytes == null
        ? await _blank(width, height)
        : await _decode(bytes, width, height);
    return RasterEngine._(
      sprites,
      initial,
      width: width,
      height: height,
      flattenEvery: flattenEvery,
      checkpointEvery: checkpointEvery,
    );
  }

  final BrushSprites sprites;
  final int width;
  final int height;

  /// F, see [defaultFlattenEvery].
  final int flattenEvery;

  final DrawingHistory<DrawOp, ui.Image> _history;
  final Set<ui.Image> _images = Set.identity();
  final Set<LiveStrokeLayer> _liveLayers = Set.identity();

  Future<void> _tail = Future.value();
  Future<void> _flattening = Future.value();
  int _sinceFlatten = 0;
  Uint8List? _readback;
  bool _disposed = false;

  ui.Rect get _canvasRect =>
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  /// The image of the current state, to draw on screen. Changes (with a
  /// notification) after every commit, undo and redo.
  ui.Image get committed => _history.committed;

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;
  int get checkpointEvery => _history.checkpointEvery;

  /// Images owned by the engine and its live layers and not yet disposed.
  @visibleForTesting
  int get liveImageCount =>
      _images.length + _liveLayers.where((l) => l._baked != null).length;

  /// Number of checkpoint images besides [committed].
  @visibleForTesting
  int get checkpointCount => _history.checkpointCount;

  /// Completes when every queued operation and flatten has finished.
  @visibleForTesting
  Future<void> get idle async {
    Future<void> tail;
    do {
      tail = _tail;
      await tail;
      await _flattening;
    } while (!identical(tail, _tail));
  }

  /// Applies [op] on top of the committed image and records it for undo
  /// (dropping the redo steps).
  Future<void> commit(DrawOp op) => _enqueue(() {
    if (_disposed) return;
    final image = _draw(_history.committed, [op]);
    _history.push(op, image).forEach(_release);
    final checkpoint = _history.cursor % _history.checkpointEvery == 0;
    _changed(image, isNew: true, forceFlatten: checkpoint);
  });

  /// Commits a white canvas.
  Future<void> clear() => commit(ClearOp(width: width, height: height));

  /// One step back; false when there is nothing to undo.
  Future<bool> undo() => _enqueue(() => _move(_history.planUndo()));

  /// One step forward; false when there is nothing to redo.
  Future<bool> redo() => _enqueue(() => _move(_history.planRedo()));

  /// The committed image as RGBA bytes, R first ([width] × [height]; the
  /// canvas is opaque, so premultiplied equals straight), cached until the
  /// next change. Do not modify the result.
  Future<Uint8List> readback() => _enqueue(() async {
    final cached = _readback;
    if (cached != null) return cached;
    if (_disposed) throw StateError('RasterEngine disposed');
    final data = await _history.committed.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    return _readback = data!.buffer.asUint8List();
  });

  /// The committed image (after every operation queued so far) as PNG.
  /// Encodes a clone outside the queue, so it never delays strokes.
  Future<Uint8List> encodePng() {
    final clone = _enqueue(() {
      if (_disposed) throw StateError('RasterEngine disposed');
      return _track(_history.committed.clone());
    });
    return clone.then((image) async {
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally {
        _release(image);
      }
    });
  }

  /// A clone of the committed image (after every operation queued so far)
  /// that the caller owns and must dispose.
  Future<ui.Image> snapshot() => _enqueue(() {
    if (_disposed) throw StateError('RasterEngine disposed');
    return _history.committed.clone();
  });

  /// A display-only layer for a stroke of [spec] being drawn. Dispose it
  /// once the stroke is committed (after [commit] completes) or discarded.
  LiveStrokeLayer startStroke(BrushSpec spec) {
    final layer = LiveStrokeLayer._(this, spec);
    _liveLayers.add(layer);
    return layer;
  }

  /// Releases every image. Queued operations still complete (as no-ops),
  /// and images still being flattened or encoded are released when done.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final layer in _liveLayers.toList()) {
      layer.dispose();
    }
    for (final image in _history.images) {
      _release(image);
    }
    _readback = null;
    super.dispose();
  }

  bool _move(HistoryPlan<DrawOp, ui.Image>? plan) {
    if (_disposed || plan == null) return false;
    if (plan.ops.isEmpty) {
      _history.apply(plan, plan.base).forEach(_release);
      _changed(plan.base);
      return true;
    }
    final image = _draw(plan.base, plan.ops);
    _history.apply(plan, image).forEach(_release);
    _changed(image, isNew: true);
    return true;
  }

  /// After [image] became the committed image: drops the readback cache,
  /// notifies, and flattens a new image when due.
  void _changed(
    ui.Image image, {
    bool isNew = false,
    bool forceFlatten = false,
  }) {
    _readback = null;
    notifyListeners();
    if (!isNew) return;
    _sinceFlatten++;
    if (forceFlatten || _sinceFlatten >= flattenEvery) _flatten(image);
  }

  /// Swaps a fully rasterized copy of [image] in wherever the history holds
  /// it, which releases the pictures [image] was lazily drawn from.
  void _flatten(ui.Image image) {
    _sinceFlatten = 0;
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
      _canvasRect,
    ).drawImage(image, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    _flattening = picture
        .toImage(width, height)
        .then(
          (flat) {
            if (_disposed) {
              flat.dispose();
              return;
            }
            _track(flat);
            final released = _history.replace(image, flat);
            if (released.isEmpty) {
              _release(flat);
            } else {
              released.forEach(_release);
              notifyListeners();
            }
          },
          onError: (Object e) {
            debugPrint('Drawing: flatten failed: $e');
          },
        )
        .whenComplete(picture.dispose);
  }

  /// [base] with [ops] drawn on top, as a new (lazily rasterized) image of
  /// the canvas size. Commit and undo/redo replay both draw this way.
  ui.Image _draw(ui.Image base, List<DrawOp> ops) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, _canvasRect);
    canvas.drawImage(base, ui.Offset.zero, ui.Paint());
    for (final op in ops) {
      op.replay(canvas, sprites);
    }
    final picture = recorder.endRecording();
    try {
      return _track(picture.toImageSync(width, height));
    } finally {
      picture.dispose();
    }
  }

  /// Runs [task] after every earlier task and the pending flatten.
  Future<T> _enqueue<T>(FutureOr<T> Function() task) {
    final run = _tail.then((_) async {
      await _flattening;
      return task();
    });
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  ui.Image _track(ui.Image image) {
    _images.add(image);
    return image;
  }

  void _release(ui.Image image) {
    if (_images.remove(image)) image.dispose();
  }

  static Future<ui.Image> _blank(int width, int height) {
    final recorder = ui.PictureRecorder();
    final rect = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    ui.Canvas(
      recorder,
      rect,
    ).drawRect(rect, ui.Paint()..color = const ui.Color(drawingWhite));
    final picture = recorder.endRecording();
    return picture.toImage(width, height).whenComplete(picture.dispose);
  }

  /// Decodes [bytes]; an image of another size is scaled onto a white
  /// canvas of [width] × [height].
  static Future<ui.Image> _decode(
    Uint8List bytes,
    int width,
    int height,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final ui.Image decoded;
    try {
      decoded = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    if (decoded.width == width && decoded.height == height) return decoded;
    try {
      final recorder = ui.PictureRecorder();
      final rect = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      ui.Canvas(recorder, rect)
        ..drawRect(rect, ui.Paint()..color = const ui.Color(drawingWhite))
        ..drawImageRect(
          decoded,
          ui.Rect.fromLTWH(
            0,
            0,
            decoded.width.toDouble(),
            decoded.height.toDouble(),
          ),
          rect,
          ui.Paint()..filterQuality = ui.FilterQuality.medium,
        );
      final picture = recorder.endRecording();
      return await picture.toImage(width, height).whenComplete(picture.dispose);
    } finally {
      decoded.dispose();
    }
  }
}

/// The stroke being drawn, display only (spec §6.2). Holds the dabs so far;
/// beyond [liveBakeThreshold] unbaked dabs it bakes them, pre-opacity, into
/// an image the size of the stroke's bounds. [paint] shows the baked image
/// and the newer dabs through [composeStroke] at [StrokeStage.live]. Never
/// used for commit or replay: commit a [StrokeOp] of [dabs] instead.
class LiveStrokeLayer {
  LiveStrokeLayer._(this._engine, this.spec);

  final RasterEngine _engine;
  final BrushSpec spec;

  final List<Dab> _dabs = [];
  int _bakedCount = 0;
  ui.Image? _baked;
  ui.Rect _bakedRect = ui.Rect.zero;
  ui.Rect _bounds = ui.Rect.zero;
  bool _disposed = false;

  /// Every dab added so far, in order.
  List<Dab> get dabs => List.unmodifiable(_dabs);

  /// Area of the dabs so far (no bleed margin), in canvas pixels.
  ui.Rect get bounds => _bounds;

  /// Number of dabs already baked into the layer's image.
  @visibleForTesting
  int get bakedCount => _bakedCount;

  void add(List<Dab> dabs) {
    if (_disposed || dabs.isEmpty) return;
    _dabs.addAll(dabs);
    final b = strokeBounds(dabs);
    _bounds = _bounds.isEmpty ? b : _bounds.expandToInclude(b);
    if (_dabs.length - _bakedCount > liveBakeThreshold) _bake();
  }

  /// Draws the stroke in canvas pixels.
  void paint(ui.Canvas canvas) {
    if (_disposed || _dabs.isEmpty) return;
    composeStroke(
      canvas,
      _dabs.sublist(_bakedCount),
      spec,
      _engine.sprites,
      bounds: _bounds,
      stage: StrokeStage.live,
      baked: _baked,
      bakedAt: _bakedRect.topLeft,
    );
  }

  void _bake() {
    final rect = _bounds.intersect(_engine._canvasRect);
    final unbaked = _dabs.sublist(_bakedCount);
    _bakedCount = _dabs.length;
    if (rect.isEmpty) return;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..translate(-rect.left, -rect.top);
    composeStroke(
      canvas,
      unbaked,
      spec,
      _engine.sprites,
      bounds: rect,
      stage: StrokeStage.bake,
      baked: _baked,
      bakedAt: _bakedRect.topLeft,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(rect.width.ceil(), rect.height.ceil());
    picture.dispose();
    _baked?.dispose();
    _baked = image;
    _bakedRect = rect;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _baked?.dispose();
    _baked = null;
    _engine._liveLayers.remove(this);
  }
}
