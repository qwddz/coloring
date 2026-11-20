import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../coloring/feedback.dart';
import '../palette/data/recent_colors.dart';
import '../subscription/data/purchase_providers.dart';
import 'data/drawing_preview_service.dart';
import 'data/drawing_repository.dart';
import 'drawing_route.dart';
import 'drawing_state.dart';
import 'live_stroke.dart';
import 'model/brush_size.dart';
import 'model/dab_generator.dart';
import 'model/drawing_record.dart';
import 'model/drawing_tool.dart';
import 'model/flood_fill.dart';
import 'model/stroke.dart';
import 'model/symmetry.dart';
import 'model/tool_rules.dart';
import 'render/brush_sprites.dart';
import 'render/draw_op.dart';
import 'render/raster_engine.dart';

/// Autosave runs this long after the last change (spec R8).
const Duration drawingSaveDelay = Duration(seconds: 2);

/// The color selected when the drawing screen opens.
const int defaultDrawingColor = 0xFF4A86C5;

/// The clock for drawing ids, created and modified times; tests fix it.
final drawingClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Starts the autosave timer; tests replace it to fire it by hand.
typedef DrawingTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

final drawingSaveTimerProvider = Provider<DrawingTimerFactory>(
  (ref) => Timer.new,
);

/// Owns one opened drawing (spec §10–11): loading it, the raster engine,
/// the live stroke, the tool selection with its access checks, the op
/// queue, autosave and the preview.
///
/// Every pixel change (stroke commit, fill, undo, redo, clear) runs in one
/// queue in call order; drawing on screen continues while it runs, and a
/// finished stroke stays visible until its commit lands. Saving reads the
/// image after every change queued before it, so a save always holds the
/// strokes drawn so far.
class DrawingController extends AsyncNotifier<DrawingState> {
  DrawingController(this.request);

  /// Which drawing to open.
  final DrawingRequest request;

  _Session? _session;
  final Random _random = Random();
  int _toolSeq = 0;
  int _symmetrySeq = 0;

  late DrawingRepository _repository;
  late DrawingPreviewService _previews;
  late DateTime Function() _now;
  late DrawingTimerFactory _timer;
  late Future<bool> _firstAccess;

  /// The committed image and its history; null while loading or after an
  /// error. The canvas paints [RasterEngine.committed] and listens to it.
  RasterEngine? get engine => _session?.engine;

  /// The strokes on screen not yet committed; paint over [engine].
  LiveStroke? get liveStroke => _session?.live;

  /// The last stroke handed to the engine.
  @visibleForTesting
  StrokeOp? debugLastStroke;

  /// Completes when every change queued so far has been applied.
  @visibleForTesting
  Future<void> get idle async {
    final session = _session;
    if (session == null) return;
    Future<void> tail;
    do {
      tail = session.tail;
      await tail;
    } while (!identical(tail, session.tail));
  }

  @override
  Future<DrawingState> build() async {
    _session = null;
    // Everything is read before the first await.
    final repository = _repository = ref.read(drawingRepositoryProvider);
    _previews = ref.read(drawingPreviewServiceProvider);
    final now = _now = ref.read(drawingClockProvider);
    _timer = ref.read(drawingSaveTimerProvider);
    final spritesFuture = ref.read(brushSpritesProvider.future);
    // Listened, not read: an unlistened stream provider is paused and would
    // never deliver its first value. Not canUseToolProvider: it says
    // "locked" while the access status loads.
    ref.listen<AsyncValue<bool>>(fullAccessProvider, (_, next) {
      if (next.value == false) _accessLost();
    });
    _firstAccess = ref
        .read(fullAccessProvider.future)
        .then((value) => value, onError: (Object _) => false);

    // Its own handle on the atlas: queued commits still draw after the
    // provider (and with it the shared atlas) is gone.
    final sprites = BrushSprites((await spritesFuture).atlas.clone());
    final DrawingRecord? record;
    final RasterEngine engine;
    try {
      (record, engine) = await _open(repository, sprites);
    } on Object {
      sprites.dispose();
      rethrow;
    }
    final String id;
    try {
      id =
          record?.id ??
          (request.newId != null && !await _exists(repository, request.newId!)
              ? request.newId!
              : newDrawingId(now()));
    } on Object {
      engine.dispose();
      sprites.dispose();
      rethrow;
    }
    final session = _Session(
      engine: engine,
      live: LiveStroke(),
      id: id,
      created: record?.created,
      loaded: record != null,
    );
    final initial = _snapshot(session);
    if (!ref.mounted) {
      session.live.dispose();
      engine.dispose();
      sprites.dispose();
      return initial;
    }
    _session = session;

    final lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) {
          _flush(session);
        }
        if (state == AppLifecycleState.paused) _renderPreview(session);
      },
    );
    ref.onDispose(() {
      lifecycle.dispose();
      // A finger still down when the screen goes keeps its stroke.
      _endStroke(session);
      _flush(session);
      _renderPreview(session);
      if (identical(_session, session)) _session = null;
      // The engine goes once the queue, the save and the preview have
      // taken what they need from it.
      Future.wait([
        session.tail,
        _quiet(session.lastPng),
        _quiet(session.lastSnapshot),
      ]).whenComplete(() {
        session.live.dispose();
        engine.dispose();
        sprites.dispose();
      });
    });
    return initial;
  }

  /// The saved drawing to open and an engine with its pixels; no record and
  /// a white engine for a new drawing, an unknown id or a raster that
  /// cannot be read (the old files stay untouched).
  Future<(DrawingRecord?, RasterEngine)> _open(
    DrawingRepository repository,
    BrushSprites sprites,
  ) async {
    final DrawingRecord? record;
    if (request.workId case final workId?) {
      record = await repository.byId(workId);
    } else if (request.newId case final newId?) {
      // A new sheet whose route comes back (process restart) continues
      // what was drawn on it.
      record = await repository.byId(newId);
    } else {
      record = await repository.latest();
    }
    if (record != null) {
      final bytes = await repository.rasterOf(record.id);
      if (bytes != null) {
        try {
          return (
            record,
            await RasterEngine.create(sprites: sprites, bytes: bytes),
          );
        } on Object catch (e) {
          debugPrint('Drawing ${record.id}: cannot decode the raster: $e');
        }
      }
    }
    return (null, await RasterEngine.create(sprites: sprites));
  }

  static Future<bool> _exists(DrawingRepository repository, String id) async =>
      await repository.byId(id) != null;

  /// Loads again after an error.
  void retry() => ref.invalidateSelf();

  // Strokes. Points are in canvas pixels.

  /// Starts a stroke of the selected tool at [point]; with [erases] (an
  /// inverted stylus) the stroke uses the eraser. Ignored with the fill
  /// tool, which taps through [fillAt].
  void strokeBegin(StrokePoint point, {bool erases = false}) {
    final session = _session;
    final current = state.value;
    if (session == null || current == null) return;
    _endStroke(session);
    final tool = erases ? DrawingTool.eraser : current.tool;
    if (tool.spec.kind == BrushKind.fill) return;
    final stroke = _ActiveStroke(
      tool: tool,
      color: current.color,
      size: current.size,
      seed: _random.nextInt(0x7FFFFFFF),
      symmetry: current.symmetry,
      layer: session.engine.startStroke(tool.spec),
    );
    session.stroke = stroke;
    session.live.add(stroke.layer);
    stroke.add(point);
    session.live.changed();
  }

  void strokeAdd(StrokePoint point) {
    final session = _session;
    final stroke = session?.stroke;
    if (session == null || stroke == null) return;
    stroke.add(point);
    session.live.changed();
  }

  /// Commits the stroke: one undo step.
  void strokeEnd() {
    final session = _session;
    if (session != null) _endStroke(session);
  }

  /// Drops the stroke being drawn; nothing is recorded.
  void strokeDiscard() {
    final session = _session;
    final stroke = session?.stroke;
    if (session == null || stroke == null) return;
    session.stroke = null;
    session.live.remove(stroke.layer);
  }

  void _endStroke(_Session session) {
    final stroke = session.stroke;
    if (stroke == null) return;
    session.stroke = null;
    stroke.finish();
    session.live.changed();
    final op = StrokeOp(stroke.input, dabs: stroke.dabs);
    debugLastStroke = op;
    final recent = stroke.tool.spec.colorMode == BrushColorMode.selected
        ? stroke.color
        : null;
    _change(
      session,
      (engine) async {
        await engine.commit(op);
        return true;
      },
      whenDone: () => session.live.remove(stroke.layer),
      onApplied: () {
        if (recent != null) ref.read(recentColorsProvider.notifier).add(recent);
      },
    );
  }

  /// Fill tool: flood fills the area at canvas point ([x], [y]) with the
  /// selected color, and its mirror point when mirroring is on.
  void fillAt(double x, double y) {
    final session = _session;
    final current = state.value;
    if (session == null || current == null) return;
    if (current.tool.spec.kind != BrushKind.fill) return;
    final engine = session.engine;
    final px = x.floor();
    final py = y.floor();
    if (px < 0 || py < 0 || px >= engine.width || py >= engine.height) return;
    final seeds = [
      (px, py),
      if (current.symmetry == SymmetryMode.vertical)
        (engine.width - 1 - px, py),
    ];
    final color = current.color;
    session.fills++;
    _emit(session, (s) => s.copyWith(busy: true));
    _change(
      session,
      (engine) async {
        final rgba = await engine.readback();
        final mask = await _floodFill(
          rgba,
          engine.width,
          engine.height,
          seeds,
          color,
        );
        if (mask == null) return false;
        await engine.commit(FillOp(mask, color));
        return true;
      },
      whenDone: () {
        session.fills--;
        if (session.fills == 0) {
          _emit(session, (s) => s.copyWith(busy: false));
        }
      },
      onApplied: () {
        ref.read(coloringFeedbackProvider).fill();
        ref.read(recentColorsProvider.notifier).add(color);
      },
    );
  }

  void undo() {
    final session = _session;
    if (session != null) _change(session, (engine) => engine.undo());
  }

  void redo() {
    final session = _session;
    if (session != null) _change(session, (engine) => engine.redo());
  }

  /// Paints the sheet white; one undo step. Nothing happens on a sheet
  /// with nothing on it yet.
  void clear() {
    final session = _session;
    if (session == null || !session.hasContent) return;
    _change(session, (engine) async {
      await engine.clear();
      return true;
    });
  }

  // Selection.

  /// Selects [tool]. A free tool is selected at once; a paid one waits for
  /// the first access status, so a buyer whose status is still loading is
  /// never sent to the paywall, then resolves [ToolSelection.locked]
  /// without the full version.
  Future<ToolSelection> selectTool(DrawingTool tool) async {
    final seq = ++_toolSeq;
    if (!tool.isFree) {
      final fullAccess = await _access();
      if (seq != _toolSeq || !ref.mounted) return ToolSelection.superseded;
      if (!canUseTool(tool, fullAccess: fullAccess)) {
        return ToolSelection.locked;
      }
    }
    return _select((s) => s.copyWith(tool: tool));
  }

  /// Mirror on ↔ off. Turning it on needs the full version, checked like
  /// [selectTool].
  Future<ToolSelection> toggleSymmetry() async {
    final seq = ++_symmetrySeq;
    final current = state.value;
    if (current == null) return ToolSelection.superseded;
    if (current.symmetry != SymmetryMode.off) {
      return _select((s) => s.copyWith(symmetry: SymmetryMode.off));
    }
    final fullAccess = await _access();
    if (seq != _symmetrySeq || !ref.mounted) return ToolSelection.superseded;
    if (!canUseSymmetry(fullAccess: fullAccess)) return ToolSelection.locked;
    return _select((s) => s.copyWith(symmetry: SymmetryMode.vertical));
  }

  void selectColor(int color) {
    final session = _session;
    if (session != null) _emit(session, (s) => s.copyWith(color: color));
  }

  void selectSize(BrushSize size) {
    final session = _session;
    if (session != null) _emit(session, (s) => s.copyWith(size: size));
  }

  ToolSelection _select(DrawingState Function(DrawingState) update) {
    final session = _session;
    if (session == null || state.value == null) {
      return ToolSelection.superseded;
    }
    _emit(session, update);
    return ToolSelection.selected;
  }

  /// The current access, or the first value once it arrives.
  Future<bool> _access() async {
    final current = ref.read(fullAccessProvider);
    if (current.hasValue) return current.requireValue;
    return _firstAccess;
  }

  /// The full version went away: a paid tool becomes the pencil and the
  /// mirror turns off. The pixels stay.
  void _accessLost() {
    final session = _session;
    if (session == null) return;
    _emit(
      session,
      (s) => s.copyWith(
        tool: fallbackTool(s.tool, fullAccess: false),
        symmetry: fallbackSymmetry(s.symmetry, fullAccess: false),
      ),
    );
  }

  // Saving.

  /// Saves now if anything changed since the last save; the save is queued
  /// before this returns (spec §12.2), so a screen opened right after reads
  /// it. Completes with whether a save was written.
  Future<bool> flushNow() {
    final session = _session;
    if (session == null) return Future.value(false);
    return _flush(session);
  }

  Future<bool> _flush(_Session session) =>
      session.dirty ? _save(session) : Future.value(false);

  /// Queues a save of the image after every change queued so far. A
  /// drawing nothing was ever drawn on is not written (its raster future
  /// fails, which the repository treats as "nothing saved").
  Future<bool> _save(_Session session) {
    session.saveTimer?.cancel();
    session.saveTimer = null;
    session.dirty = false;
    final engine = session.engine;
    final modified = _now().toUtc();
    final created = session.created ??= modified;
    final record = DrawingRecord(
      id: session.id,
      created: created,
      modified: modified,
      width: engine.width,
      height: engine.height,
      raster: DrawingRecord.rasterName(session.id, modified),
    );
    final png = session.tail.then((_) {
      if (!session.hasContent) throw StateError('nothing drawn yet');
      return engine.encodePng();
    });
    session.lastPng = png;
    final saved = _repository.save(record, png);
    session.lastSave = (record, saved);
    session.previewDirty = true;
    return saved;
  }

  void _scheduleSave(_Session session) {
    session.saveTimer?.cancel();
    session.saveTimer = _timer(drawingSaveDelay, () {
      session.saveTimer = null;
      _flush(session);
    });
  }

  /// Queues a preview of the last save when one happened since the last
  /// preview. The image is taken after every queued change, i.e. the saved
  /// state, and dropped when that save failed.
  void _renderPreview(_Session session) {
    final last = session.lastSave;
    if (!session.previewDirty || last == null) return;
    session.previewDirty = false;
    final (record, saved) = last;
    final previews = _previews;
    final snapshot = session.tail.then((_) => session.engine.snapshot());
    session.lastSnapshot = snapshot;
    snapshot.then(
      (image) async {
        if (await saved) {
          previews.renderAfterLeave(
            drawingId: record.id,
            sourceModified: record.modified,
            imageClone: image,
          );
        } else {
          image.dispose();
        }
      },
      onError: (Object e) {
        debugPrint('Drawing ${record.id}: no preview: $e');
      },
    );
  }

  // The op queue.

  /// Queues [change] after every earlier one. It completes with whether the
  /// pixels changed; [whenDone] runs after it either way, [onApplied] only
  /// when they changed and the screen is still open.
  void _change(
    _Session session,
    Future<bool> Function(RasterEngine engine) change, {
    void Function()? whenDone,
    void Function()? onApplied,
  }) {
    session.dirty = true;
    _scheduleSave(session);
    session.tail = session.tail.then((_) async {
      var changed = false;
      try {
        changed = await change(session.engine);
      } on Object catch (e) {
        debugPrint('Drawing ${session.id}: a change failed: $e');
      } finally {
        whenDone?.call();
      }
      if (!changed) return;
      session.applied++;
      session.revision++;
      if (!_isCurrent(session)) return;
      onApplied?.call();
      _emit(session, (s) => _snapshot(session, s));
    });
  }

  bool _isCurrent(_Session session) =>
      ref.mounted && identical(_session, session);

  void _emit(_Session session, DrawingState Function(DrawingState) update) {
    if (!_isCurrent(session)) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(update(current));
  }

  DrawingState _snapshot(_Session session, [DrawingState? previous]) {
    final engine = session.engine;
    return DrawingState(
      drawingId: session.id,
      tool: previous?.tool ?? DrawingTool.pencil,
      color: previous?.color ?? defaultDrawingColor,
      size: previous?.size ?? BrushSize.medium,
      symmetry: previous?.symmetry ?? SymmetryMode.off,
      canUndo: engine.canUndo,
      canRedo: engine.canRedo,
      busy: session.fills > 0,
      isEmpty: !session.hasContent,
      revision: session.revision,
    );
  }
}

/// One opened drawing: the engine, the live stroke and the save state.
/// Queued work captures it, so it never touches a later build's drawing.
class _Session {
  _Session({
    required this.engine,
    required this.live,
    required this.id,
    required this.created,
    required this.loaded,
  });

  final RasterEngine engine;
  final LiveStroke live;
  final String id;
  DateTime? created;

  /// Opened from a saved drawing.
  final bool loaded;

  _ActiveStroke? stroke;
  Future<void> tail = Future.value();

  /// Changes applied since opening.
  int applied = 0;
  int revision = 0;
  int fills = 0;

  /// Changes queued since the last save.
  bool dirty = false;

  /// A save happened since the last preview.
  bool previewDirty = false;
  Timer? saveTimer;
  (DrawingRecord, Future<bool>)? lastSave;
  Future<Uint8List>? lastPng;
  Future<ui.Image>? lastSnapshot;

  /// Something to save: a saved drawing, or a change on a new one.
  bool get hasContent => loaded || applied > 0;
}

/// The stroke under the finger: its input so far, one dab generator per
/// copy (two with the mirror) and the live layer showing the dabs.
class _ActiveStroke {
  _ActiveStroke({
    required this.tool,
    required this.color,
    required this.size,
    required this.seed,
    required this.symmetry,
    required this.layer,
  }) : _generators = [
         for (var i = 0; i < (symmetry == SymmetryMode.off ? 1 : 2); i++)
           DabGenerator(
             tool: tool,
             color: color,
             size: size,
             seed: seed,
             mirrored: i == 1,
           ),
       ];

  final DrawingTool tool;
  final int color;
  final BrushSize size;
  final int seed;
  final SymmetryMode symmetry;
  final LiveStrokeLayer layer;
  final List<DabGenerator> _generators;
  final List<StrokePoint> _points = [];

  /// The dabs drawn so far, one list per copy.
  late final List<List<Dab>> _dabs = [for (final _ in _generators) <Dab>[]];

  /// Every dab in [DabGenerator.generate] order (the original copy, then
  /// the mirror copy), so the commit needs no second generation.
  List<Dab> get dabs => [for (final copy in _dabs) ...copy];

  StrokeInput get input => StrokeInput(
    tool: tool,
    color: color,
    size: size,
    seed: seed,
    symmetry: symmetry,
    points: _points,
  );

  void add(StrokePoint point) {
    _points.add(point);
    for (var i = 0; i < _generators.length; i++) {
      _draw(i, _generators[i].add(i == 0 ? point : mirrorPoint(point)));
    }
  }

  void finish() {
    for (var i = 0; i < _generators.length; i++) {
      _draw(i, _generators[i].finish());
    }
  }

  void _draw(int copy, List<Dab> dabs) {
    _dabs[copy].addAll(dabs);
    layer.add(dabs);
  }
}

/// [floodFill] on another isolate. Top level, so the closure captures only
/// the arguments, never the controller or an image.
Future<FillMask?> _floodFill(
  Uint8List rgba,
  int width,
  int height,
  List<(int, int)> seeds,
  int color,
) => Isolate.run(() => floodFill(rgba, width, height, seeds, color));

Future<void> _quiet(Future<Object?>? future) =>
    future?.then<void>((_) {}, onError: (Object _) {}) ?? Future.value();

/// One controller per [DrawingRequest]; disposed when the screen leaves.
/// No automatic retry: errors go to the screen, which offers
/// [DrawingController.retry].
final drawingControllerProvider = AsyncNotifierProvider.autoDispose
    .family<DrawingController, DrawingState, DrawingRequest>(
      DrawingController.new,
      retry: (_, _) => null,
    );
