import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/data/manifest_provider.dart';
import '../../catalog/domain/content_manifest.dart';
import '../../coloring/model/work.dart';
import '../../drawing/data/drawing_preview_service.dart';
import '../../drawing/data/drawings_provider.dart';
import '../../drawing/model/drawing_record.dart';
import 'work_exporter.dart';
import 'work_preview_service.dart';
import 'works_provider.dart';

/// What «Мои работы» tells the player after an export.
enum WorkMessage {
  savedToGallery,
  saveDenied,
  exportFailed,
  pictureUnavailable,
}

/// The message for [outcome]; null when the share sheet said it already.
WorkMessage? workMessageFor(ExportOutcome outcome) => switch (outcome) {
  ExportOutcome.saved => WorkMessage.savedToGallery,
  ExportOutcome.denied => WorkMessage.saveDenied,
  ExportOutcome.unavailable => WorkMessage.pictureUnavailable,
  ExportOutcome.failed => WorkMessage.exportFailed,
  ExportOutcome.shared => null,
};

@immutable
class MyWorksState {
  const MyWorksState({this.exporting = false, this.backfills = 0});

  /// An export is running: the screen blocks input under a progress overlay.
  final bool exporting;

  /// How many preview backfills are running (coloring works and drawings
  /// run their own).
  final int backfills;

  /// Missing previews are being drawn: their cards show a small spinner.
  bool get backfilling => backfills > 0;

  MyWorksState copyWith({bool? exporting, int? backfills}) => MyWorksState(
    exporting: exporting ?? this.exporting,
    backfills: backfills ?? this.backfills,
  );
}

/// «Мои работы» screen state: clears leftover shared PNGs, draws missing
/// previews of works and drawings once they are listed (cancelled when the
/// screen leaves) and runs one export at a time.
class MyWorksController extends Notifier<MyWorksState> {
  late WorkPreviewService _previews;
  late DrawingPreviewService _drawingPreviews;
  bool _backfillStarted = false;
  bool _drawingBackfillStarted = false;

  @override
  MyWorksState build() {
    final previews = _previews = ref.watch(workPreviewServiceProvider);
    final drawingPreviews = _drawingPreviews = ref.watch(
      drawingPreviewServiceProvider,
    );
    _backfillStarted = false;
    _drawingBackfillStarted = false;
    ref.onDispose(previews.cancelBackfill);
    ref.onDispose(drawingPreviews.cancelBackfill);
    unawaited(ref.read(workExporterProvider).clearShareDirectory());
    ref.listen(worksProvider, (_, next) {
      if (next.value case final works?) _startBackfill(works);
    });
    ref.listen(drawingsProvider, (_, next) {
      if (next.value case final drawings?) _startDrawingBackfill(drawings);
    });
    // Already listed (kept alive elsewhere): start after build returns.
    if (ref.read(worksProvider).value case final works?) {
      scheduleMicrotask(() {
        if (ref.mounted) _startBackfill(works);
      });
    }
    if (ref.read(drawingsProvider).value case final drawings?) {
      scheduleMicrotask(() {
        if (ref.mounted) _startDrawingBackfill(drawings);
      });
    }
    return const MyWorksState();
  }

  void _startBackfill(List<WorkSummary> works) {
    if (_backfillStarted) return;
    _backfillStarted = true;
    if (!works.any((s) => s.previewStale)) return;
    unawaited(_counted(_previews.backfill(works)));
  }

  void _startDrawingBackfill(List<DrawingSummary> drawings) {
    if (_drawingBackfillStarted) return;
    _drawingBackfillStarted = true;
    if (!drawings.any((s) => s.previewStale)) return;
    unawaited(_counted(_drawingPreviews.backfill(drawings)));
  }

  /// Counts [backfill] in [MyWorksState.backfills] while it runs.
  Future<void> _counted(Future<void> backfill) async {
    state = state.copyWith(backfills: state.backfills + 1);
    try {
      await backfill;
    } finally {
      if (ref.mounted) state = state.copyWith(backfills: state.backfills - 1);
    }
  }

  /// Saves [work] into the gallery (no parental gate, S2-D4).
  Future<WorkMessage?> saveToGallery(Work work) =>
      _export((exporter) => exporter.saveToGallery(work));

  /// Opens the share sheet with [work]. Call it only after the parental
  /// gate (`shareWorkThroughGate`).
  Future<WorkMessage?> share(Work work) =>
      _export((exporter) => exporter.share(work));

  /// Saves [drawing] into the gallery (no parental gate, no access check).
  Future<WorkMessage?> saveDrawingToGallery(DrawingRecord drawing) =>
      _export((exporter) => exporter.saveDrawingToGallery(drawing));

  /// Opens the share sheet with [drawing]. Call it only after the parental
  /// gate (`shareDrawingThroughGate`).
  Future<WorkMessage?> shareDrawing(DrawingRecord drawing) =>
      _export((exporter) => exporter.shareDrawing(drawing));

  Future<WorkMessage?> _export(
    Future<ExportOutcome> Function(WorkExporter exporter) run,
  ) async {
    if (state.exporting) return null;
    final exporter = ref.read(workExporterProvider);
    state = state.copyWith(exporting: true);
    ExportOutcome outcome;
    try {
      outcome = await run(exporter);
    } on Object catch (e) {
      debugPrint('Exporting a work failed: $e');
      outcome = ExportOutcome.failed;
    } finally {
      if (ref.mounted) state = state.copyWith(exporting: false);
    }
    return workMessageFor(outcome);
  }
}

final myWorksControllerProvider =
    NotifierProvider.autoDispose<MyWorksController, MyWorksState>(
      MyWorksController.new,
    );

/// The manifest entry of a work's picture: loading while the manifest
/// loads, then the entry, or null when the picture is no longer in it.
final workPictureProvider = Provider.autoDispose
    .family<AsyncValue<PictureEntry?>, String>(
      (ref, pictureId) => ref
          .watch(manifestProvider)
          .whenData((manifest) => manifest.pictureById(pictureId)),
    );
