import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/coloring/perf/fill_latency_probe.dart';
import '../features/settings/data/settings_controller.dart';
import '../l10n/app_localizations.dart';
import 'locale.dart';
import 'router.dart';
import 'theme.dart';

class ColoringApp extends ConsumerWidget {
  const ColoringApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageCode = ref.watch(
      settingsProvider.select((s) => s.languageCode),
    );
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildAppTheme(),
      routerConfig: ref.watch(routerProvider),
      locale: languageCode == null ? null : Locale(languageCode),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      showPerformanceOverlay: coloringPerfOverlay,
    );
  }
}
