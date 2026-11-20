import 'dart:async';

import 'package:coloring/app/theme.dart';
import 'package:coloring/features/catalog/catalog_grid.dart';
import 'package:coloring/features/catalog/categories_screen.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/drawing/drawing_tile.dart';
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
import 'category_access_test.dart' show lockManifest;

class _DelayedProgress extends ProgressController {
  _DelayedProgress(this.completer);

  final Completer<Set<String>> completer;

  @override
  Future<Set<String>> build() => completer.future;
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Completer<Set<String>> progress, {
    Future<ContentManifest> Function()? manifest,
    bool fullAccess = false,
    bool settle = true,
  }) async {
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
        GoRoute(
          path: '/category/:id',
          builder: (context, state) => Scaffold(
            body: Text('category stub ${state.pathParameters['id']}'),
          ),
        ),
        GoRoute(
          path: '/draw',
          builder: (context, state) =>
              Scaffold(body: Text('draw stub ${state.uri}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          manifestProvider.overrideWith(
            (ref) => manifest?.call() ?? Future.value(testManifest),
          ),
          progressProvider.overrideWith(() => _DelayedProgress(progress)),
          purchaseServiceProvider.overrideWithValue(
            FakePurchaseService(fullAccess: fullAccess),
          ),
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
    if (settle) await tester.pumpAndSettle();
  }

  Finder cardOf(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(PictureCard));

  Finder lockOf(String title) => find.descendant(
    of: cardOf(title),
    matching: find.byIcon(Icons.lock_rounded),
  );

  void expectTileFirst(WidgetTester tester) {
    expect(find.byType(DrawingTile), findsOneWidget);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate = grid.childrenDelegate as SliverChildBuilderDelegate;
    final first = delegate.builder(tester.element(find.byType(GridView)), 0);
    expect(first, isA<DrawingTile>());
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

  testWidgets('the drawing tile comes first and opens /draw', (tester) async {
    await pumpScreen(tester, Completer()..complete(const {}));
    expectTileFirst(tester);
    expect(find.text('Drawing'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DrawingTile),
        matching: find.byIcon(Icons.lock_rounded),
      ),
      findsNothing,
    );
    await tester.tap(find.byType(DrawingTile));
    await tester.pumpAndSettle();
    expect(find.text('draw stub /draw'), findsOneWidget);
  });

  testWidgets('the drawing tile is there while the catalog loads', (
    tester,
  ) async {
    final manifest = Completer<ContentManifest>();
    await pumpScreen(
      tester,
      Completer()..complete(const {}),
      manifest: () => manifest.future,
      settle: false,
    );
    await tester.pump();
    expectTileFirst(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    manifest.complete(testManifest);
    await tester.pumpAndSettle();
    expectTileFirst(tester);
    expect(find.text('On the farm'), findsOneWidget);
  });

  testWidgets('the drawing tile is there when the catalog fails', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      Completer()..complete(const {}),
      manifest: () => Future.error(StateError('offline')),
    );
    expectTileFirst(tester);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.byType(DrawingTile));
    await tester.pumpAndSettle();
    expect(find.text('draw stub /draw'), findsOneWidget);
  });

  testWidgets('only the all-paid category shows a lock', (tester) async {
    await pumpScreen(
      tester,
      Completer()..complete(const {}),
      manifest: () async => lockManifest,
    );
    expect(lockOf('paid'), findsOneWidget);
    expect(
      find.descendant(
        of: cardOf('paid'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'In the full version',
        ),
      ),
      findsOneWidget,
    );
    expect(lockOf('mixed'), findsNothing);
    expect(lockOf('free'), findsNothing);
    expect(lockOf('empty'), findsNothing);
    expect(
      find.descendant(of: cardOf('empty'), matching: find.text('Coming soon')),
      findsOneWidget,
    );
    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('no category lock with the full version', (tester) async {
    await pumpScreen(
      tester,
      Completer()..complete(const {}),
      manifest: () async => lockManifest,
      fullAccess: true,
    );
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.text('paid'), findsOneWidget);
  });

  testWidgets('a locked category still opens', (tester) async {
    await pumpScreen(
      tester,
      Completer()..complete(const {}),
      manifest: () async => lockManifest,
    );
    await tester.tap(find.text('paid'));
    await tester.pumpAndSettle();
    expect(find.text('category stub paid'), findsOneWidget);
  });
}
