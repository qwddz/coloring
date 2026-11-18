import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/data/manifest_provider.dart';
import '../../catalog/domain/content_manifest.dart';
import '../../coloring/data/picture_loader.dart';
import '../../coloring/model/region_map.dart';
import '../../progress/data/work_repository.dart';
import 'work_renderer.dart';
import 'works_provider.dart';

/// Size of the preview shown in «Мои работы».
const previewWidth = 640;
const previewHeight = 480;

/// Draws work previews and saves them through
/// [WorkRepository.savePreview]. Renders run on the UI isolate one at a
/// time; a failure is logged and never thrown.
class WorkPreviewService {
  WorkPreviewService({
    required this._repository,
    required this._loader,
    required this._manifest,
  });

  final WorkRepository _repository;
  final PictureLoader _loader;
  final Future<ContentManifest> Function() _manifest;

  Future<void> _tail = Future.value();
  int _backfillRun = 0;
  bool _disposed = false;

  /// Completes when every render queued so far has finished.
  @visibleForTesting
  Future<void> get idle => _tail;

  /// Queues a preview of [workId] as it was at [sourceModified]. Takes
  /// ownership of [linesClone] and disposes it after the render, also on
  /// failure.
  void renderAfterLeave({
    required String workId,
    required DateTime sourceModified,
    required RegionMap map,
    required Uint32List colors,
    required ui.Image linesClone,
  }) {
    _enqueue('preview of $workId', () async {
      try {
        await _render(workId, sourceModified, map, colors, linesClone);
      } finally {
        linesClone.dispose();
      }
    });
  }

  /// Draws the missing and stale previews of [works], one at a time, for
  /// bundled pictures only: works of CDN pictures and of pictures missing
  /// from the manifest are skipped, so this never downloads. A newer call,
  /// [cancelBackfill] or [dispose] stops it before the next work.
  Future<void> backfill(List<WorkSummary> works) async {
    final run = ++_backfillRun;
    bool cancelled() => _disposed || run != _backfillRun;
    final stale = [
      for (final s in works)
        if (s.previewStale) s.work.id,
    ];
    if (stale.isEmpty || cancelled()) return;
    final ContentManifest manifest;
    try {
      manifest = await _manifest();
    } on Object catch (e) {
      debugPrint('Preview backfill: no manifest: $e');
      return;
    }
    // One listing of the previews per run; previews saved during the run
    // arrive as changes and replace what the listing found.
    final previews = <String, WorkPreview>{};
    final subscription = _repository.changes.listen((change) {
      if (change is PreviewSaved) previews[change.workId] = change.preview;
    });
    try {
      final Map<String, WorkPreview> listed;
      try {
        listed = await _repository.previews();
      } on Object catch (e) {
        debugPrint('Preview backfill: cannot list previews: $e');
        return;
      }
      for (final MapEntry(:key, :value) in listed.entries) {
        previews.putIfAbsent(key, () => value);
      }
      for (final workId in stale) {
        if (cancelled()) return;
        await _enqueue('backfill of $workId', () async {
          if (cancelled()) return;
          // Read the work again: it may have changed since the list was made.
          final work = await _repository.byId(workId);
          if (work == null) return;
          final current = WorkSummary(work, preview: previews[workId]);
          if (!current.previewStale || cancelled()) return;
          final entry = manifest.pictureById(work.pictureId);
          if (entry == null || entry.asset == null) return;
          final picture = await _loader.load(entry);
          try {
            await _render(
              work.id,
              work.modified,
              picture.map,
              work.colors,
              picture.linesImage,
            );
          } finally {
            picture.dispose();
          }
        });
      }
    } finally {
      await subscription.cancel();
    }
  }

  /// Stops a running [backfill] before its next work.
  void cancelBackfill() => _backfillRun++;

  /// Stops backfill. Queued [renderAfterLeave] calls still finish.
  void dispose() {
    _disposed = true;
    _backfillRun++;
  }

  Future<void> _render(
    String workId,
    DateTime sourceModified,
    RegionMap map,
    Uint32List colors,
    ui.Image lines,
  ) async {
    final png = await renderWorkPng(
      map: map,
      colors: colors,
      lines: lines,
      width: previewWidth,
      height: previewHeight,
    );
    await _repository.savePreview(workId, sourceModified, png);
  }

  Future<void> _enqueue(String what, Future<void> Function() task) {
    final run = _tail.then((_) => task()).catchError((Object e) {
      debugPrint('Work preview: $what failed: $e');
    });
    _tail = run;
    return run;
  }
}

final workPreviewServiceProvider = Provider<WorkPreviewService>((ref) {
  final service = WorkPreviewService(
    repository: ref.watch(workRepositoryProvider),
    loader: ref.watch(pictureLoaderProvider),
    manifest: () => ref.read(manifestProvider.future),
  );
  ref.onDispose(service.dispose);
  return service;
});
