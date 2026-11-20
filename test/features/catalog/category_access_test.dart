import 'package:coloring/features/catalog/data/category_access.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> picture(String id, {required bool free}) => {
  'id': id,
  'title': {'uk': id, 'en': id, 'ru': id},
  'characters': <String>[],
  'level': 'simple',
  'free': free,
  if (free) 'asset': 'coloring/free/$id/' else 'url': 'x/$id.zip',
  if (!free) 'sha256': '${'0' * 63}1',
};

Map<String, Object> category(String id, List<Map<String, Object>> pictures) => {
  'id': id,
  'title': {'uk': id, 'en': id, 'ru': id},
  'pictures': pictures,
};

/// One category of each kind: all paid, mixed, all free and empty.
final lockManifest = ContentManifest.fromJson({
  'version': 1,
  'categories': [
    category('paid', [
      picture('paid_a', free: false),
      picture('paid_b', free: false),
    ]),
    category('mixed', [
      picture('mixed_a', free: true),
      picture('mixed_b', free: false),
    ]),
    category('free', [picture('free_a', free: true)]),
    category('empty', []),
  ],
});

void main() {
  CategoryEntry byId(String id) => lockManifest.categoryById(id)!;

  test('only an all-paid category is locked, and only without access', () {
    expect(isCategoryLocked(byId('paid'), fullAccess: false), isTrue);
    expect(isCategoryLocked(byId('paid'), fullAccess: true), isFalse);
    for (final id in ['mixed', 'free', 'empty']) {
      expect(isCategoryLocked(byId(id), fullAccess: false), isFalse);
      expect(isCategoryLocked(byId(id), fullAccess: true), isFalse);
    }
  });

  Future<ProviderContainer> containerWith(bool? fullAccess) async {
    final c = ProviderContainer(
      overrides: [
        manifestProvider.overrideWith((ref) async => lockManifest),
        fullAccessProvider.overrideWith(
          (ref) => fullAccess == null
              ? const Stream<bool>.empty()
              : Stream.value(fullAccess),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(fullAccessProvider, (_, _) {});
    await c.read(manifestProvider.future);
    if (fullAccess != null) await c.read(fullAccessProvider.future);
    return c;
  }

  test('the provider follows the manifest and the access', () async {
    final locked = await containerWith(false);
    expect(locked.read(categoryLockedProvider('paid')), isTrue);
    expect(locked.read(categoryLockedProvider('mixed')), isFalse);
    expect(locked.read(categoryLockedProvider('unknown')), isFalse);

    final owned = await containerWith(true);
    expect(owned.read(categoryLockedProvider('paid')), isFalse);
  });

  test('paid categories look locked while the access loads', () async {
    final loading = await containerWith(null);
    expect(loading.read(categoryLockedProvider('paid')), isTrue);
    expect(loading.read(categoryLockedProvider('empty')), isFalse);
  });
}
