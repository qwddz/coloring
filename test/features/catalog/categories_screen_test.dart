import 'dart:async';

import 'package:coloring/app/theme.dart';
import 'package:coloring/features/catalog/categories_screen.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/progress/data/progress_store.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/features/subscription/domain/purchase_service.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/test_manifest.dart';

class _DelayedProgress extends ProgressController {
  _DelayedProgress(this.completer);

  final Completer<Set<String>> completer;

  @override
  Future<Set<String>> build() => completer.future;
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Completer<Set<String>> progress,
  ) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const CategoriesScreen(),
        ),
        GoRoute(
          path: '/works',
          builder: (context, state) => const Scaffold(body: Text('works stub')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          manifestProvider.overrideWith((ref) async => testManifest),
          progressProvider.overrideWith(() => _DelayedProgress(progress)),
          purchaseServiceProvider.overrideWithValue(FakePurchaseService()),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the counter shows after progress loads, not before', (
    tester,
  ) async {
    final progress = Completer<Set<String>>();
    await pumpScreen(tester, progress);
    expect(find.text('On the farm'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    progress.complete({'farm_piglet_picnic'});
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });

  testWidgets('an empty category has no counter and says coming soon', (
    tester,
  ) async {
    await pumpScreen(tester, Completer()..complete(const {}));
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('0/0'), findsNothing);
  });

  testWidgets('the My works button opens the works route', (tester) async {
    await pumpScreen(tester, Completer()..complete(const {}));
    final button = find.byTooltip('My works');
    expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('works stub'), findsOneWidget);
  });
}
