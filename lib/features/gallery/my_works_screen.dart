import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/paper_background.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/catalog_grid.dart';
import 'data/my_works_controller.dart';
import 'data/works_provider.dart';
import 'work_actions_dialog.dart';
import 'work_preview_image.dart';

/// «Мои работы»: every saved work, newest first. A tap opens its actions.
class MyWorksScreen extends ConsumerWidget {
  const MyWorksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final works = ref.watch(worksProvider);
    final state = ref.watch(myWorksControllerProvider);
    void leave() => context.canPop() ? context.pop() : context.go('/');
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          PaperBackground(
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CatalogHeader(
                    title: l10n.myWorks,
                    leading: RoundIconButton(
                      tooltip: l10n.back,
                      icon: Icons.arrow_back_rounded,
                      onPressed: leave,
                    ),
                  ),
                  Expanded(
                    child: switch (works) {
                      AsyncValue(:final value?) when value.isEmpty =>
                        CatalogMessage(
                          text: l10n.myWorksEmpty,
                          actionLabel: l10n.myWorksToPictures,
                          onAction: () => context.go('/'),
                        ),
                      AsyncValue(:final value?) => CatalogGrid(
                        itemCount: value.length,
                        itemBuilder: (context, index) => _WorkCard(
                          index: index,
                          summary: value[index],
                          backfilling: state.backfilling,
                        ),
                      ),
                      AsyncError() => CatalogMessage(
                        text: l10n.catalogLoadError,
                        actionLabel: l10n.retry,
                        onAction: () => ref.invalidate(worksProvider),
                      ),
                      _ => const Center(child: CircularProgressIndicator()),
                    },
                  ),
                ],
              ),
            ),
          ),
          if (state.exporting) const _ExportOverlay(),
        ],
      ),
    );
  }
}

class _WorkCard extends ConsumerWidget {
  const _WorkCard({
    required this.index,
    required this.summary,
    required this.backfilling,
  });

  final int index;
  final WorkSummary summary;
  final bool backfilling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final work = summary.work;
    final entry = ref.watch(workPictureProvider(work.pictureId)).value;
    final preview = summary.preview;
    return LayoutBuilder(
      builder: (context, constraints) => PictureCard(
        index: index,
        image: preview == null
            ? null
            : workPreviewImage(
                preview.file,
                logicalWidth: constraints.maxWidth,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
        badge: preview == null && backfilling
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: () => openWorkActions(context, ref, summary),
        caption: Row(
          children: [
            Expanded(
              child: Text(
                entry?.title.resolve(language) ?? '',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: BookPalette.text),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (work.completed)
              Icon(
                Icons.star_rounded,
                size: 20,
                color: BookPalette.star,
                semanticLabel: l10n.workCompleted,
              ),
          ],
        ),
      ),
    );
  }
}

/// Blocks input while an export renders the full-size picture.
class _ExportOverlay extends StatelessWidget {
  const _ExportOverlay();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Positioned.fill(
      child: Stack(
        children: [
          ModalBarrier(
            dismissible: false,
            color: BookPalette.scrim.withValues(alpha: .3),
          ),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: BookPalette.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      l10n.workExporting,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: BookPalette.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
