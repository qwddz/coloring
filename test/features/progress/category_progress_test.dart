import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/progress/domain/category_progress.dart';
import 'package:flutter_test/flutter_test.dart';

CategoryEntry category(String id, List<String> pictures) => CategoryEntry(
  id: id,
  title: const LocalizedText({'en': 'T'}),
  pictures: [
    for (final p in pictures)
      PictureEntry(
        id: p,
        categoryId: id,
        title: const LocalizedText({'en': 'P'}),
        level: PictureLevel.simple,
        free: p != 'locked',
        asset: 'coloring/free/$p/',
      ),
  ],
);

void main() {
  test('counts only completed ids of that category, locked in total', () {
    final home = category('home', ['fox', 'cat', 'locked']);
    expect(categoryProgress(home, {'fox', 'locked', 'other', 'dog'}), (
      completed: 2,
      total: 3,
    ));
  });

  test('empty category → 0/0', () {
    expect(categoryProgress(category('empty', []), {'fox'}), (
      completed: 0,
      total: 0,
    ));
  });
}
