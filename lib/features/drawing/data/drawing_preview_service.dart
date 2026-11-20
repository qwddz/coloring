import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gallery/data/work_preview_service.dart'
    show previewHeight, previewWidth;
import 'drawing_repository.dart';
import 'drawings_provider.dart';

/// Draws drawing previews (640 × 480, like coloring works) and saves them
/// through [DrawingRepository.savePreview]. Renders run on the UI isolate
/// one at a time; a failure is logged and never thrown.
class DrawingPreviewService {
  DrawingPreviewService(this._repository);

  final DrawingRepository _repository;

  Future<void> _tail = Future.value();
  int _backfillRun = 0;
  bool _disposed = false;

  /// Completes when every render queued so far has finished.
  @visibleForTesting
  Future<void> get idle => _tail;

  /// Queues a preview of [drawingId] as it was at [sourceModified], scaled
  /// from [imageClone]. Takes ownership of [imageClone] and disposes it
  /// after the render, also on failure.
  void renderAfterLeave({
    required String drawingId,
    required DateTime sourceModified,
    required ui.Image imageClone,
  }) {
    _enqueue('preview of $drawingId', () async {
      try {
        final png = await _scaledPng(imageClone);
        await _repository.savePreview(drawingId, sourceModified, png);
      } finally {
        imageClone.dispose();
      }
    });
  }

  /// Draws the missing and stale previews of [drawings] from their rasters,
  /// one at a time. A newer call, [cancelBackfill] or [dispose] stops it
  /// before the next drawing.
  Future<void> backfill(List<DrawingSummary> drawings) async {
    final run = ++_backfillRun;
    bool cancelled() => _disposed || run != _backfillRun;
    final stale = [
      for (final s in drawings)
        if (s.previewStale) s.record.id,
    ];
    if (stale.isEmpty || cancelled()) return;
    // One listing of the previews per run; previews saved during the run
    // arrive as changes and replace what the listing found.
    final previews = <String, DrawingPreview>{};
    final subscription = _repository.changes.listen((change) {
      if (change is DrawingPreviewSaved) {
        previews[change.drawingId] = change.preview;
      }
    });
    try {
      final Map<String, DrawingPreview> listed;
      try {
        listed = await _repository.previews();
      } on Object catch (e) {
        debugPrint('Drawing preview backfill: cannot list previews: $e');
        return;
      }
      for (final MapEntry(:key, :value) in listed.entries) {
        previews.putIfAbsent(key, () => value);
      }
      for (final drawingId in stale) {
        if (cancelled()) return;
        await _enqueue('backfill of $drawingId', () async {
          if (cancelled()) return;
          // Read the drawing again: it may have changed since the list.
          final record = await _repository.byId(drawingId);
          if (record == null) return;
          final current = DrawingSummary(record, preview: previews[drawingId]);
          if (!current.previewStale || cancelled()) return;
          final raster = await _repository.rasterOf(drawingId);
          if (raster == null || cancelled()) return;
          final png = await _pngFromRaster(raster);
          await _repository.savePreview(drawingId, record.modified, png);
        });
      }
    } finally {
      await subscription.cancel();
    }
  }

  /// Stops a running [backfill] before its next drawing.
  void cancelBackfill() => _backfillRun++;

  /// Stops backfill. Queued [renderAfterLeave] calls still finish.
  void dispose() {
    _disposed = true;
    _backfillRun++;
  }

  /// [raster] decoded straight at the preview size, then encoded as PNG.
  static Future<Uint8List> _pngFromRaster(Uint8List raster) async {
    final codec = await ui.instantiateImageCodec(
      raster,
      targetWidth: previewWidth,
      targetHeight: previewHeight,
    );
    ui.Image? image;
    try {
      image = (await codec.getNextFrame()).image;
      return await _encode(image);
    } finally {
      image?.dispose();
      codec.dispose();
    }
  }

  static Future<Uint8List> _scaledPng(ui.Image source) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, previewWidth.toDouble(), previewHeight.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    ui.Image? scaled;
    try {
      scaled = await picture.toImage(previewWidth, previewHeight);
      return await _encode(scaled);
    } finally {
      picture.dispose();
      scaled?.dispose();
    }
  }

  static Future<Uint8List> _encode(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG encoding failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> _enqueue(String what, Future<void> Function() task) {
    final run = _tail.then((_) => task()).catchError((Object e) {
      debugPrint('Drawing preview: $what failed: $e');
    });
    _tail = run;
    return run;
  }
}

final drawingPreviewServiceProvider = Provider<DrawingPreviewService>((ref) {
  final service = DrawingPreviewService(ref.watch(drawingRepositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});
