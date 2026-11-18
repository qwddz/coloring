import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/paper_background.dart';
import '../../app/widgets/passe_partout.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/catalog_grid.dart';
import '../subscription/data/purchase_providers.dart';
import 'data/settings_controller.dart';

/// Stage 6 brings music; until then the switch would do nothing, so hide it.
/// The setting, its storage and the ARB key stay.
const showMusicSetting = false;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final fullAccess = ref.watch(fullAccessProvider).value ?? false;
    final purchaseStatus = ref.watch(purchaseControllerProvider);
    ref.listen(purchaseControllerProvider, (_, status) {
      final message = switch (status) {
        PurchaseStatus.restored => l10n.purchasesRestored,
        PurchaseStatus.nothingToRestore => l10n.nothingToRestore,
        PurchaseStatus.restoreFailed => l10n.restoreFailed,
        _ => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });
    final languages = {
      null: l10n.languageSystem,
      'uk': l10n.languageUkrainian,
      'en': l10n.languageEnglish,
      'ru': l10n.languageRussian,
    };
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CatalogHeader(
                title: l10n.settings,
                leading: RoundIconButton(
                  tooltip: l10n.back,
                  icon: Icons.arrow_back_rounded,
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/'),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        PassePartout(
                          child: Material(
                            type: MaterialType.transparency,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SwitchListTile(
                                  secondary: const Icon(
                                    Icons.volume_up_rounded,
                                  ),
                                  title: Text(l10n.soundEffects),
                                  value: settings.soundEnabled,
                                  onChanged: controller.setSoundEnabled,
                                ),
                                if (showMusicSetting)
                                  SwitchListTile(
                                    secondary: const Icon(
                                      Icons.music_note_rounded,
                                    ),
                                    title: Text(l10n.music),
                                    value: settings.musicEnabled,
                                    onChanged: controller.setMusicEnabled,
                                  ),
                                SwitchListTile(
                                  secondary: const Icon(
                                    Icons.vibration_rounded,
                                  ),
                                  title: Text(l10n.vibration),
                                  value: settings.vibrationEnabled,
                                  onChanged: controller.setVibrationEnabled,
                                ),
                                ListTile(
                                  leading: const Icon(Icons.language_rounded),
                                  title: Text(l10n.language),
                                  trailing: _LanguagePicker(
                                    value: settings.languageCode,
                                    languages: languages,
                                    onChanged: controller.setLanguage,
                                  ),
                                ),
                                if (fullAccess)
                                  ListTile(
                                    leading: const Icon(
                                      Icons.lock_open_rounded,
                                    ),
                                    title: Text(l10n.fullVersionUnlocked),
                                  )
                                else
                                  ListTile(
                                    leading: const Icon(Icons.restore_rounded),
                                    title: Text(l10n.restorePurchases),
                                    enabled:
                                        purchaseStatus != PurchaseStatus.busy,
                                    trailing:
                                        purchaseStatus == PurchaseStatus.busy
                                        ? const SizedBox.square(
                                            dimension: 24,
                                            child: CircularProgressIndicator(),
                                          )
                                        : null,
                                    onTap: ref
                                        .read(
                                          purchaseControllerProvider.notifier,
                                        )
                                        .restore,
                                  ),
                                ListTile(
                                  leading: const Icon(
                                    Icons.info_outline_rounded,
                                  ),
                                  title: Text(l10n.about),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                  ),
                                  onTap: () => context.push('/about'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Language dropdown on a paper field with a card-coloured menu.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.value,
    required this.languages,
    required this.onChanged,
  });

  final String? value;
  final Map<String?, String> languages;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(12);
    return Theme(
      // The open menu highlights the chosen item with these colours.
      data: theme.copyWith(
        focusColor: BookPalette.paper,
        hoverColor: BookPalette.paper,
        highlightColor: BookPalette.paperDark,
        splashColor: Colors.transparent,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: BookPalette.paperLight,
          borderRadius: radius,
          border: Border.all(color: BookPalette.outline, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: value,
              onChanged: onChanged,
              dropdownColor: BookPalette.card,
              borderRadius: radius,
              elevation: 4,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: BookPalette.text,
              ),
              icon: const Icon(
                Icons.expand_more_rounded,
                color: BookPalette.textMuted,
              ),
              items: [
                for (final MapEntry(:key, :value) in languages.entries)
                  DropdownMenuItem(value: key, child: Text(value)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
