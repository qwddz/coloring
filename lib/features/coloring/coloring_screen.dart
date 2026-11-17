import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/widgets/paper_background.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/catalog_grid.dart';
import '../catalog/data/manifest_provider.dart';

String coloringRoute(String pictureId) => '/coloring/$pictureId';

/// Placeholder for the coloring screen; the Flame canvas comes in Stage 1.
class ColoringScreen extends ConsumerWidget {
  const ColoringScreen({super.key, required this.pictureId});

  final String pictureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final entry = ref.watch(manifestProvider).value?.pictureById(pictureId);
    void leave() => context.canPop() ? context.pop() : context.go('/');
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CatalogHeader(
                title: entry?.title.resolve(language) ?? '',
                leading: RoundIconButton(
                  tooltip: l10n.back,
                  icon: Icons.arrow_back_rounded,
                  onPressed: leave,
                ),
              ),
              Expanded(
                child: CatalogMessage(
                  text: l10n.coloringComingSoon,
                  actionLabel: l10n.back,
                  onAction: leave,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
