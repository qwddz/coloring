import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/data/manifest_provider.dart';
import '../../catalog/domain/content_manifest.dart';
import '../../coloring/model/work.dart';
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
  const MyWorksState({this.exporting = false, this.backfilling = false});

  /// An export is running: the screen blocks input under a progress overlay.
  final bool exporting;

  /// Missing previews are being drawn: their cards show a small spinner.
  final bool backfilling;

  MyWorksState copyWith({bool? exporting, bool? backfilling}) => MyWorksState(
    exporting: exporting ?? this.exporting,
    backfilling: backfilling ?? this.backfilling,
  );
}

/// «Мои работы» screen state: clears leftover shared PNGs, draws missing
/// previews once the works are listed (cancelled when the screen leaves) and
/// runs one export at a time.
class MyWorksController extends Notifier<MyWorksState> {
  late WorkPreviewService _previews;
  bool _backfillStarted = false;

  @override
  MyWorksState build() {
    final previews = _previews = ref.watch(workPreviewServiceProvider);
    _backfillStarted = false;
    ref.onDispose(previews.cancelBackfill);
    unawaited(ref.read(workExporterProvider).clearShareDirectory());
    ref.listen(worksProvider, (_, next) {
      if (next.value case final works?) _startBackfill(works);
    });
    // Already listed (kept alive elsewhere): start after build returns.
    if (ref.read(worksProvider).value case final works?) {
      scheduleMicrotask(() {
        if (ref.mounted) _startBackfill(works);
      });
    }
    return const MyWorksState();
  }

  void _startBackfill(List<WorkSummary> works) {
    if (_backfillStarted) return;
    _backfillStarted = true;
    if (!works.any((s) => s.previewStale)) return;
    unawaited(_backfill(works));
  }

  Future<void> _backfill(List<WorkSummary> works) async {
    state = state.copyWith(backfilling: true);
    try {
      await _previews.backfill(works);
    } finally {
      if (ref.mounted) state = state.copyWith(backfilling: false);
    }
  }

  /// Saves [work] into the gallery (no parental gate, S2-D4).
  Future<WorkMessage?> saveToGallery(Work work) =>
      _export((exporter) => exporter.saveToGallery(work));

  /// Opens the share sheet with [work]. Call it only after the parental
  /// gate (`shareWorkThroughGate`).
  Future<WorkMessage?> share(Work work) =>
      _export((exporter) => exporter.share(work));

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
