import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../subscription/data/purchase_providers.dart';
import '../domain/content_manifest.dart';
import 'manifest_provider.dart';

/// A category is locked when it has pictures and none of them can be
/// colored ([canColor]): all paid, no full version. An empty category is
/// "coming soon", never locked.
bool isCategoryLocked(CategoryEntry category, {required bool fullAccess}) =>
    category.pictures.isNotEmpty &&
    !category.pictures.any((p) => canColor(p, fullAccess: fullAccess));

/// [isCategoryLocked] for the category with this id in the current
/// manifest; paid categories look locked while the access status loads.
final categoryLockedProvider = Provider.autoDispose.family<bool, String>((
  ref,
  categoryId,
) {
  final category = ref.watch(manifestProvider).value?.categoryById(categoryId);
  if (category == null) return false;
  return isCategoryLocked(
    category,
    fullAccess: ref.watch(fullAccessProvider).value ?? false,
  );
});
