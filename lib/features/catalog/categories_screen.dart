import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/paper_background.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../content/content_config.dart';
import '../drawing/drawing_tile.dart';
import '../content/thumb_image.dart';
import '../gallery/gallery_routes.dart';
import '../progress/data/progress_store.dart';
import '../progress/domain/category_progress.dart';
import 'catalog_grid.dart';
import 'data/category_access.dart';
import 'data/manifest_provider.dart';
import 'domain/content_manifest.dart';

/// Start screen: one card per category.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final manifest = ref.watch(manifestProvider);
    final cdnBaseUrl = ref.watch(cdnBaseUrlProvider);
    final bundledAssets = ref.watch(bundledAssetsProvider).value;
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CatalogHeader(
                title: l10n.appTitle,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RoundIconButton(
                      tooltip: l10n.myWorks,
                      icon: Icons.photo_library_rounded,
                      onPressed: () => context.push(myWorksRoute),
                    ),
                    const SizedBox(width: 8),
                    RoundIconButton(
                      tooltip: l10n.settings,
                      icon: Icons.settings_rounded,
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
              ),
              Expanded(
                // Data first: a reload keeps the previous catalog on screen.
                child: switch (manifest) {
                  AsyncValue(:final value?) => CatalogGrid(
                    itemCount: value.categories.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return const DrawingTile();
                      final category = value.categories[index - 1];
                      return _CategoryCard(
                        index: index,
                        category: category,
                        thumb: thumbImage(
                          category.pictures.firstOrNull,
                          cdnBaseUrl,
                          bundledAssets,
                        ),
                      );
                    },
                  ),
                  // The drawing tile stays reachable while the catalog
                  // loads or fails.
                  AsyncError() => CatalogGrid(
                    itemCount: 2,
                    itemBuilder: (context, index) => index == 0
                        ? const DrawingTile()
                        : SingleChildScrollView(
                            child: CatalogMessage(
                              text: l10n.catalogLoadError,
                              actionLabel: l10n.retry,
                              onAction: () => ref.invalidate(manifestProvider),
                            ),
                          ),
                  ),
                  _ => CatalogGrid(
                    itemCount: 2,
                    itemBuilder: (context, index) => index == 0
                        ? const DrawingTile()
                        : const Center(child: CircularProgressIndicator()),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  const _CategoryCard({
    required this.index,
    required this.category,
    required this.thumb,
  });

  final int index;
  final CategoryEntry category;
  final ImageProvider? thumb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final progress = ref.watch(progressProvider).value;
    final stars = progress == null || category.pictures.isEmpty
        ? null
        : categoryProgress(category, progress);
    final language = Localizations.localeOf(context).languageCode;
    final locked = ref.watch(categoryLockedProvider(category.id));
    return PictureCard(
      index: index,
      image: thumb,
      onTap: () => context.push('/category/${category.id}'),
      caption: Row(
        children: [
          Expanded(
            child: Text(
              category.title.resolve(language),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: BookPalette.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (stars != null)
            Semantics(
              label: l10n.categoryStars(stars.completed, stars.total),
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 20,
                    color: BookPalette.star,
                  ),
                  Text(
                    '${stars.completed}/${stars.total}',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: BookPalette.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
      // A category without pictures yet says so on its card; one with only
      // full-version pictures shows a lock (it still opens).
      badge: category.pictures.isEmpty
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: BookPalette.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  l10n.comingSoon,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: BookPalette.textMuted),
                ),
              ),
            )
          : locked
          ? Semantics(
              label: l10n.lockedPicture,
              excludeSemantics: true,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: BookPalette.primary,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(5),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 18,
                    color: BookPalette.card,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
