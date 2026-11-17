import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/paper_background.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../coloring/coloring_screen.dart';
import '../content/content_config.dart';
import '../content/thumb_image.dart';
import '../subscription/data/purchase_providers.dart';
import '../subscription/paywall_screen.dart';
import 'catalog_grid.dart';
import 'data/manifest_provider.dart';
import 'domain/content_manifest.dart';

/// Pictures of one category.
class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key, required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final manifest = ref.watch(manifestProvider);
    final category = manifest.value?.categoryById(categoryId);
    final cdnBaseUrl = ref.watch(cdnBaseUrlProvider);
    final bundledAssets = ref.watch(bundledAssetsProvider).value;
    void leave() => context.canPop() ? context.pop() : context.go('/');
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CatalogHeader(
                title: category?.title.resolve(language) ?? '',
                leading: RoundIconButton(
                  tooltip: l10n.back,
                  icon: Icons.arrow_back_rounded,
                  onPressed: leave,
                ),
              ),
              Expanded(
                // Data first: a reload keeps the previous catalog on screen.
                child: switch (manifest) {
                  AsyncValue(hasValue: true) when category == null =>
                    CatalogMessage(
                      text: l10n.categoryMissing,
                      actionLabel: l10n.back,
                      onAction: leave,
                    ),
                  AsyncValue(hasValue: true) when category!.pictures.isEmpty =>
                    CatalogMessage(
                      text: l10n.categoryComingSoon,
                      actionLabel: l10n.back,
                      onAction: leave,
                    ),
                  AsyncValue(hasValue: true) => CatalogGrid(
                    itemCount: category!.pictures.length,
                    itemBuilder: (context, index) {
                      final entry = category.pictures[index];
                      return _PictureCard(
                        index: index,
                        entry: entry,
                        thumb: thumbImage(entry, cdnBaseUrl, bundledAssets),
                      );
                    },
                  ),
                  AsyncError() => CatalogMessage(
                    text: l10n.catalogLoadError,
                    actionLabel: l10n.retry,
                    onAction: () => ref.invalidate(manifestProvider),
                  ),
                  _ => const Center(child: CircularProgressIndicator()),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PictureCard extends ConsumerWidget {
  const _PictureCard({
    required this.index,
    required this.entry,
    required this.thumb,
  });

  final int index;
  final PictureEntry entry;
  final ImageProvider? thumb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final locked = !ref.watch(canColorProvider(entry));
    return PictureCard(
      index: index,
      image: thumb,
      lockedLabel: locked ? l10n.lockedPicture : null,
      onTap: locked
          ? () => openPaywallThroughGate(context, ref)
          : () => context.push(coloringRoute(entry.id)),
      caption: Text(
        entry.title.resolve(language),
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: BookPalette.text),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
