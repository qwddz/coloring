import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/drawing_record.dart';
import 'drawing_repository.dart';

/// A saved drawing with its preview, as «Мои работы» shows it.
class DrawingSummary {
  const DrawingSummary(this.record, {this.preview});

  final DrawingRecord record;
  final DrawingPreview? preview;

  /// True when the drawing has no preview, or its preview was drawn from an
  /// older state (compared in milliseconds, the precision of the preview
  /// file name).
  bool get previewStale {
    final preview = this.preview;
    return preview == null ||
        preview.sourceModified.millisecondsSinceEpoch !=
            record.modified.millisecondsSinceEpoch;
  }
}

/// Every saved drawing, newest first. Lists the drawings and the previews
/// once per build, then follows [DrawingRepository.changes] in place.
/// Disposed when nothing watches it.
class DrawingsController extends AsyncNotifier<List<DrawingSummary>> {
  @override
  Future<List<DrawingSummary>> build() async {
    final repository = ref.watch(drawingRepositoryProvider);
    final subscription = repository.changes.listen(_apply);
    ref.onDispose(subscription.cancel);
    final records = await repository.list();
    final previews = await repository.previews();
    return _sorted([
      for (final record in records)
        DrawingSummary(record, preview: previews[record.id]),
    ]);
  }

  /// Changes that arrive while the folder is being listed wait for the
  /// listing, then apply on top of it; applying one twice changes nothing.
  Future<void> _apply(DrawingChange change) async {
    try {
      await future;
    } on Object {
      return;
    }
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(switch (change) {
      DrawingSaved(:final record) => _sorted([
        for (final s in current)
          if (s.record.id != record.id) s,
        DrawingSummary(record, preview: _previewOf(current, record.id)),
      ]),
      DrawingPreviewSaved(:final drawingId, :final preview) => [
        for (final s in current)
          s.record.id == drawingId
              ? DrawingSummary(s.record, preview: preview)
              : s,
      ],
    });
  }

  static DrawingPreview? _previewOf(List<DrawingSummary> list, String id) {
    for (final s in list) {
      if (s.record.id == id) return s.preview;
    }
    return null;
  }

  /// Newest first; equal times by id, so the order is stable.
  static List<DrawingSummary> _sorted(List<DrawingSummary> list) =>
      list..sort((a, b) {
        final byTime = b.record.modified.compareTo(a.record.modified);
        return byTime != 0 ? byTime : b.record.id.compareTo(a.record.id);
      });
}

final drawingsProvider =
    AsyncNotifierProvider.autoDispose<DrawingsController, List<DrawingSummary>>(
      DrawingsController.new,
    );
