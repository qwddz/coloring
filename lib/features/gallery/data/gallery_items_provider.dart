import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../drawing/data/drawings_provider.dart';
import 'works_provider.dart';

/// One card of «Мои работы»: a coloring work or a drawing.
sealed class GalleryItem {
  const GalleryItem();

  String get id;
  DateTime get modified;
}

final class ColoringItem extends GalleryItem {
  const ColoringItem(this.summary);

  final WorkSummary summary;

  @override
  String get id => summary.work.id;

  @override
  DateTime get modified => summary.work.modified;
}

final class DrawingItem extends GalleryItem {
  const DrawingItem(this.summary);

  final DrawingSummary summary;

  @override
  String get id => summary.record.id;

  @override
  DateTime get modified => summary.record.modified;
}

/// Coloring works and drawings in one list, newest first (equal times by
/// id). Loading while either list loads; an error when either fails.
final galleryItemsProvider =
    Provider.autoDispose<AsyncValue<List<GalleryItem>>>((ref) {
      final works = ref.watch(worksProvider);
      final drawings = ref.watch(drawingsProvider);
      for (final list in [works, drawings]) {
        if (list.hasError) return AsyncError(list.error!, list.stackTrace!);
      }
      final workList = works.value;
      final drawingList = drawings.value;
      if (workList == null || drawingList == null) return const AsyncLoading();
      final items = <GalleryItem>[
        for (final s in workList) ColoringItem(s),
        for (final s in drawingList) DrawingItem(s),
      ];
      items.sort((a, b) {
        final byTime = b.modified.compareTo(a.modified);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
      return AsyncData(items);
    });
