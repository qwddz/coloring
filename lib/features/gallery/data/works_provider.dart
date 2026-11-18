import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coloring/model/work.dart';
import '../../progress/data/work_repository.dart';

/// A saved work with its preview, as «Мои работы» shows it.
class WorkSummary {
  const WorkSummary(this.work, {this.preview});

  final Work work;
  final WorkPreview? preview;

  /// True when the work has no preview, or its preview was drawn from an
  /// older state of the work (compared in milliseconds, the precision of the
  /// preview file name).
  bool get previewStale {
    final preview = this.preview;
    return preview == null ||
        preview.sourceModified.millisecondsSinceEpoch !=
            work.modified.millisecondsSinceEpoch;
  }
}

/// Every saved work, newest first. Lists the works and the previews once
/// per build, then follows [WorkRepository.changes] in place, so a fill
/// never re-lists.
/// Only «Мои работы» watches it, and it is disposed when that screen leaves.
class WorksController extends AsyncNotifier<List<WorkSummary>> {
  @override
  Future<List<WorkSummary>> build() async {
    final repository = ref.watch(workRepositoryProvider);
    final subscription = repository.changes.listen(_apply);
    ref.onDispose(subscription.cancel);
    final works = await repository.list();
    final previews = await repository.previews();
    final summaries = [
      for (final work in works) WorkSummary(work, preview: previews[work.id]),
    ];
    return _sorted(summaries);
  }

  /// Changes that arrive while the folder is being listed wait for the
  /// listing, then apply on top of it; applying one twice changes nothing.
  Future<void> _apply(WorkChange change) async {
    try {
      await future;
    } on Object {
      return;
    }
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(switch (change) {
      WorkSaved(:final work) => _sorted([
        for (final s in current)
          if (s.work.id != work.id) s,
        WorkSummary(work, preview: _previewOf(current, work.id)),
      ]),
      PreviewSaved(:final workId, :final preview) => [
        for (final s in current)
          s.work.id == workId ? WorkSummary(s.work, preview: preview) : s,
      ],
    });
  }

  static WorkPreview? _previewOf(List<WorkSummary> works, String workId) {
    for (final s in works) {
      if (s.work.id == workId) return s.preview;
    }
    return null;
  }

  /// Newest first; equal times by id, so the order is stable.
  static List<WorkSummary> _sorted(List<WorkSummary> works) =>
      works..sort((a, b) {
        final byTime = b.work.modified.compareTo(a.work.modified);
        return byTime != 0 ? byTime : b.work.id.compareTo(a.work.id);
      });
}

final worksProvider =
    AsyncNotifierProvider.autoDispose<WorksController, List<WorkSummary>>(
      WorksController.new,
    );
