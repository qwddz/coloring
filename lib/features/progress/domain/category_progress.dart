import '../../catalog/domain/content_manifest.dart';

/// Stars of a category: [completedIds] that are pictures of [category], out
/// of all its pictures (locked ones included).
({int completed, int total}) categoryProgress(
  CategoryEntry category,
  Set<String> completedIds,
) => (
  completed: category.pictures.where((p) => completedIds.contains(p.id)).length,
  total: category.pictures.length,
);
