import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/widgets/paper_background.dart';
import '../../app/widgets/passe_partout.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/catalog_grid.dart';
import '../content/content_config.dart';
import '../subscription/parental_gate.dart';
import 'data/about_links.dart';

/// Asks the parental gate, then opens [url] outside the app.
Future<void> openLinkThroughGate(
  BuildContext context,
  WidgetRef ref,
  Uri url,
) async {
  if (!await showParentalGate(context, ref)) return;
  if (!context.mounted) return;
  try {
    await ref.read(externalLinkLauncherProvider)(url);
  } catch (_) {
    // No app can open the link: nothing to show a child.
  }
}

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final version = ref.watch(appVersionProvider).value;
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CatalogHeader(
                title: l10n.about,
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
                                const SizedBox(height: 12),
                                Text(
                                  l10n.appTitle,
                                  style: textTheme.headlineSmall,
                                  textAlign: TextAlign.center,
                                ),
                                if (version != null)
                                  Text(
                                    l10n.appVersion(version),
                                    style: textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                const SizedBox(height: 8),
                                ListTile(
                                  leading: const Icon(
                                    Icons.privacy_tip_rounded,
                                  ),
                                  title: Text(l10n.privacyPolicy),
                                  onTap: () => openLinkThroughGate(
                                    context,
                                    ref,
                                    privacyPolicyUrl,
                                  ),
                                ),
                                ListTile(
                                  leading: const Icon(
                                    Icons.description_rounded,
                                  ),
                                  title: Text(l10n.termsOfUse),
                                  onTap: () => openLinkThroughGate(
                                    context,
                                    ref,
                                    termsOfUseUrl,
                                  ),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.mail_rounded),
                                  title: Text(l10n.contactUs),
                                  subtitle: const Text(contactEmail),
                                  onTap: () => openLinkThroughGate(
                                    context,
                                    ref,
                                    contactEmailUrl,
                                  ),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.favorite_rounded),
                                  title: Text(l10n.credits),
                                  subtitle: Text(l10n.creditsPictures),
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
