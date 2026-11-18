import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/data/manifest_provider.dart';
import '../content/data/manifest_source.dart';
import '../content/data/picture_store.dart';
import '../palette/data/recent_colors.dart';
import '../progress/data/progress_store.dart';
import '../progress/data/work_repository.dart';
import '../subscription/data/purchase_providers.dart';
import 'coloring_state.dart';
import 'data/picture_loader.dart';
import 'feedback.dart';
import 'model/canvas_sink.dart';
import 'model/coloring_mode.dart';
import 'model/coloring_session.dart';
import 'model/work.dart';

/// The picture is paid and the full version is not unlocked.
class ColoringLockedException implements Exception {
  const ColoringLockedException(this.pictureId);

  final String pictureId;

  @override
  String toString() => 'ColoringLockedException: $pictureId';
}

/// The manifest has no picture with this id.
class ColoringNotFoundException implements Exception {
  const ColoringNotFoundException(this.pictureId);

  final String pictureId;

  @override
  String toString() => 'ColoringNotFoundException: $pictureId';
}

/// At most one fill sound and vibration per this interval during a stroke.
const Duration strokeFeedbackInterval = Duration(milliseconds: 80);

/// The clock for work ids, modified times and the stroke feedback throttle;
/// tests fix it.
final coloringClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Owns one opened picture: loading, the coloring session, saving the work
/// and the side effects (canvas, sound, vibration, recent colors).
class ColoringController extends AsyncNotifier<ColoringState> {
  ColoringController(this.pictureId);

  final String pictureId;

  ColoringSession? _session;
  Work? _work;
  ColoringCanvasSink? _sink;

  /// The session holds changes not yet written: only an open magic stroke
  /// fills without saving. Pause and dispose write only then, so an
  /// untouched work and inactive → hidden → paused never rewrite the file.
  bool _dirty = false;

  /// When the last stroke fill feedback played; null outside a stroke.
  DateTime? _strokeFeedbackAt;
  int _completionSeq = 0;
  int _rejectSeq = 0;

  late WorkRepository _repository;
  late DateTime Function() _now;

  /// The opened picture, or null while loading or after an error.
  LoadedPicture? get picture => state.value?.picture;

  @override
  Future<ColoringState> build() async {
    _session = null;
    _work = null;
    _sink = null;
    _dirty = false;
    _strokeFeedbackAt = null;
    // Everything is read before the first await. Read, not watch: a
    // manifest refresh must not rebuild the picture being colored.
    final manifestFuture = ref.read(manifestProvider.future);
    // Listened, not read: an unlistened stream provider is paused and
    // would never deliver its first value. Not canColorProvider: it says
    // "locked" while the access status loads.
    final fullAccessFuture = ref
        .listen(fullAccessProvider.future, (_, _) {})
        .read();
    final loader = ref.read(pictureLoaderProvider);
    final repository = _repository = ref.read(workRepositoryProvider);
    final now = _now = ref.read(coloringClockProvider);
    final progress = ref.read(
      pictureDownloadProgressProvider(pictureId).notifier,
    );

    final entry = (await manifestFuture).pictureById(pictureId);
    if (entry == null) {
      fullAccessFuture.ignore();
      throw ColoringNotFoundException(pictureId);
    }
    if (!canColor(entry, fullAccess: await fullAccessFuture)) {
      throw ColoringLockedException(pictureId);
    }

    final LoadedPicture picture;
    try {
      picture = await loader.load(entry, onProgress: progress.report);
    } finally {
      progress.report(null);
    }
    final Work? saved;
    try {
      saved = await repository.latestFor(pictureId);
    } on Object {
      picture.dispose();
      rethrow;
    }
    final meta = picture.meta;
    final Work work;
    final ColoringSession session;
    try {
      work =
          saved?.fitTo(meta.regionCount) ??
          Work.create(
            pictureId: pictureId,
            regionCount: meta.regionCount,
            now: now,
          );
      session = ColoringSession(
        meta: meta,
        map: picture.map,
        fill: work.toFillState(meta.regionCount),
        mode: work.mode,
        completed: work.completed,
      );
    } on Object {
      picture.dispose();
      rethrow;
    }
    if (!ref.mounted) {
      picture.dispose();
      return _snapshot(picture, session);
    }
    _session = session;
    _work = work;

    final lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) {
          _flush();
        }
      },
    );
    ref.onDispose(() {
      lifecycle.dispose();
      _flush();
      _sink = null;
      picture.dispose();
    });
    return _snapshot(picture, session);
  }

  /// Loads again after an error. A picture the CDN refused may have moved
  /// in a newer manifest, so that one is fetched first.
  Future<void> retry() async {
    if (state.error case PictureLoadException(
      failure: PictureLoadFailure.unavailable,
    )) {
      state = const AsyncLoading();
      ref.invalidate(remoteManifestProvider);
      // A failed fetch leaves the current manifest; the reload reports.
      await ref.read(remoteManifestProvider.future).catchError((_) => null);
      if (!ref.mounted) return;
    }
    ref.invalidateSelf();
  }

  /// Connects the canvas and brings it up to date: fills, labels and the
  /// number highlight.
  void attachCanvas(ColoringCanvasSink sink) {
    _sink = sink;
    final session = _session;
    if (session == null) return;
    sink.showFill(session.fill, const []);
    _syncModeToCanvas(session);
  }

  /// Disconnects [sink] if it is the attached canvas.
  void detachCanvas(ColoringCanvasSink sink) {
    if (identical(_sink, sink)) _sink = null;
  }

  /// A tap at image point ([x], [y]); [tolerance] in image px.
  void tap(double x, double y, {required double tolerance}) {
    final session = _session;
    if (session == null) return;
    final color = session.selectedColor;
    final recent =
        session.mode == ColoringMode.free && session.tool == ColoringTool.brush;
    final result = session.tap(x, y, tolerance: tolerance);
    switch (result.outcome) {
      case FillOutcome.rejected:
        _rejectSeq++;
        _sink?.flashRejected(result.regionId);
        ref.read(coloringFeedbackProvider).rejected();
        _emit();
      case FillOutcome.changed:
        _sink?.showFill(session.fill, result.changes, waveX: x, waveY: y);
        if (recent) ref.read(recentColorsProvider.notifier).add(color);
        _changed(result);
        return;
      case FillOutcome.unchanged:
      case FillOutcome.miss:
        break;
    }
    // The tap committed an open stroke that completed the picture.
    if (result.justCompleted) {
      _save();
      _completedNow();
      _emit();
    }
  }

  /// Starts a magic-brush stroke.
  void beginStroke() {
    _strokeFeedbackAt = null;
    _session?.beginStroke();
  }

  /// Extends the stroke; regions fill at once, the work is saved at
  /// [endStroke]. The fill sound and vibration play at most once per
  /// [strokeFeedbackInterval], so a fast swipe does not buzz per region.
  void strokeTo(double x, double y, {required double tolerance}) {
    final session = _session;
    if (session == null) return;
    final result = session.strokeTo(x, y, tolerance: tolerance);
    if (!result.changed) return;
    _dirty = true;
    _sink?.showFill(session.fill, result.changes);
    final t = _now();
    final last = _strokeFeedbackAt;
    if (last == null || t.difference(last) >= strokeFeedbackInterval) {
      _strokeFeedbackAt = t;
      ref.read(coloringFeedbackProvider).fill();
    }
    _emit();
  }

  /// Ends the stroke: one undo step and one save.
  void endStroke() {
    _strokeFeedbackAt = null;
    final session = _session;
    if (session == null) return;
    final result = session.endStroke();
    if (!result.changed) return;
    _save();
    if (result.justCompleted) _completedNow();
    _emit();
  }

  /// Free-mode long press: shows the region's correct color for a moment.
  void hint(double x, double y, {required double tolerance}) {
    final hint = _session?.hintColorAt(x, y, tolerance: tolerance);
    if (hint == null) return;
    _sink?.showHint(hint.regionId, hint.color);
    ref.read(coloringFeedbackProvider).hint();
  }

  void undo() => _bulk(_session?.undo());

  void clearAll() => _bulk(_session?.clearAll());

  /// The "Done" button.
  void finish() {
    final result = _session?.finish();
    if (result == null || !result.justCompleted) return;
    _save();
    _completedNow();
    _emit();
  }

  void setMode(ColoringMode mode) {
    final session = _session;
    if (session == null || session.mode == mode) return;
    final strokeCompleted = session.setMode(mode);
    _syncModeToCanvas(session);
    _save();
    if (strokeCompleted) _completedNow();
    _emit();
  }

  /// Selects a brush color. In numbers mode only picture colors count; any
  /// other color is ignored.
  void selectColor(int color) {
    final session = _session;
    if (session == null) return;
    if (session.mode == ColoringMode.numbers) {
      final index = session.meta.palette.indexOf(color);
      if (index >= 0) selectPaletteIndex(index);
      return;
    }
    session.selectColor(color);
    _emit();
  }

  void selectPaletteIndex(int index) {
    final session = _session;
    if (session == null) return;
    session.selectPaletteIndex(index);
    _syncModeToCanvas(session);
    _emit();
  }

  void selectEraser() {
    final session = _session;
    if (session == null) return;
    session.selectEraser();
    _emit();
  }

  /// Undo and clear: the canvas updates without a wave.
  void _bulk(FillResult? result) {
    final session = _session;
    if (session == null || result == null || !result.changed) return;
    _sink?.showFill(session.fill, result.changes);
    _changed(result);
  }

  /// After a fill-changing command: sound, save, completion, new state.
  void _changed(FillResult result) {
    _save();
    if (result.justCompleted) {
      _completedNow();
    } else {
      ref.read(coloringFeedbackProvider).fill();
    }
    _emit();
  }

  /// The fanfare replaces the fill sound of the last region.
  void _completedNow() {
    _completionSeq++;
    ref.read(coloringFeedbackProvider).completed();
    unawaited(ref.read(progressProvider.notifier).markCompleted(pictureId));
  }

  void _syncModeToCanvas(ColoringSession session) {
    final sink = _sink;
    if (sink == null) return;
    final numbers = session.mode == ColoringMode.numbers;
    sink.setLabelsEnabled(numbers);
    sink.setHighlight(numbers ? session.selectedPaletteIndex : null);
  }

  /// Saves on pause and dispose, only when something changed since the
  /// last save.
  void _flush() {
    if (_dirty) _save();
  }

  void _save() {
    final session = _session;
    final work = _work;
    if (session == null || work == null) return;
    final next = work.withSession(session, now: _now);
    _work = next;
    _dirty = false;
    unawaited(_repository.save(next));
  }

  void _emit() {
    final picture = this.picture;
    final session = _session;
    if (picture == null || session == null) return;
    state = AsyncData(_snapshot(picture, session));
  }

  ColoringState _snapshot(LoadedPicture picture, ColoringSession session) =>
      ColoringState(
        picture: picture,
        mode: session.mode,
        tool: session.tool,
        selectedColor: session.selectedColor,
        selectedPaletteIndex: session.selectedPaletteIndex,
        canUndo: session.canUndo,
        canFinish: session.canFinish,
        filledFraction: session.filledFraction,
        paletteProgress: List.unmodifiable(session.paletteProgress),
        completed: session.completed,
        completionSeq: _completionSeq,
        rejectSeq: _rejectSeq,
      );
}

/// One controller per opened picture id; disposed when the screen leaves.
/// No automatic retry: errors go to the screen, which offers [retry].
final coloringControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ColoringController, ColoringState, String>(
      ColoringController.new,
      retry: (_, _) => null,
    );
