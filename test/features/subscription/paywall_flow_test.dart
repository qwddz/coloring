import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:coloring/app/app.dart';
import 'package:coloring/app/book_palette.dart';
import 'package:coloring/app/router.dart';
import 'package:coloring/app/theme.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:coloring/features/catalog/catalog_grid.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/coloring/coloring_canvas.dart';
import 'package:coloring/features/coloring/coloring_route.dart';
import 'package:coloring/features/coloring/coloring_screen.dart'
    hide coloringRoute;
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/features/subscription/data/review_access.dart';
import 'package:coloring/features/subscription/domain/parental_challenge.dart';
import 'package:coloring/features/subscription/domain/purchase_service.dart';
import 'package:coloring/features/subscription/paywall_screen.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/coloring/fakes.dart';
import '../../support/coloring_overrides.dart';
import '../../support/test_manifest.dart';

void main() {
  late FakePurchaseService store;
  late InMemoryWorkRepository works;

  setUp(() {
    store = FakePurchaseService();
    works = InMemoryWorkRepository();
  });

  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    String reviewCodeSha256 = '',
  }) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          manifestProvider.overrideWith((ref) async => testManifest),
          purchaseServiceProvider.overrideWithValue(store),
          reviewCodeSha256Provider.overrideWithValue(reviewCodeSha256),
          parentalChallengeProvider.overrideWithValue(
            () => const ParentalChallenge(7, 8),
          ),
          ...coloringScreenOverrides(),
        ],
        child: const ColoringApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(ColoringApp)))
        .read(routerProvider);
  }

  Finder lockOf(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(PictureCard)),
    matching: find.byIcon(Icons.lock_rounded),
  );

  Future<void> openFarm(WidgetTester tester) async {
    await tester.tap(find.text('On the farm'));
    await tester.pumpAndSettle();
  }

  Future<void> tapCard(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> pickMode(WidgetTester tester, String name) async {
    expect(find.text('How do you want to color?'), findsOneWidget);
    await tester.tap(find.text(name));
    // The coloring screen may follow and never settles.
    await tester.pump();
  }

  Future<void> answerGate(WidgetTester tester, String answer) async {
    expect(find.text('For grown-ups'), findsOneWidget);
    expect(find.textContaining('7 × 8'), findsOneWidget);
    await tester.enterText(find.byType(TextField), answer);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('free cards are open, paid ones are locked', (tester) async {
    await pumpApp(tester);
    await openFarm(tester);
    expect(lockOf('Piglet'), findsNothing);
    await tester.ensureVisible(find.text('Goat'));
    expect(lockOf('Goat'), findsOneWidget);
  });

  testWidgets('locked card has a warm lock and still opens the gate', (
    tester,
  ) async {
    await pumpApp(tester);
    await openFarm(tester);
    await tester.ensureVisible(find.text('Goat'));
    final icon = tester.widget<Icon>(lockOf('Goat'));
    expect(icon.color, BookPalette.card);
    await tapCard(tester, 'Goat');
    expect(find.text('For grown-ups'), findsOneWidget);
  });

  testWidgets('a wrong answer closes the parental gate', (tester) async {
    await pumpApp(tester);
    await openFarm(tester);
    await tapCard(tester, 'Goat');
    await answerGate(tester, '54');
    expect(find.text('For grown-ups'), findsNothing);
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text('On the farm'), findsOneWidget);
  });

  testWidgets('after a wrong answer the gate waits 10 seconds', (tester) async {
    await pumpApp(tester);
    await openFarm(tester);
    await tapCard(tester, 'Goat');
    await answerGate(tester, '54');
    await tapCard(tester, 'Goat');
    expect(find.text('For grown-ups'), findsNothing);
    expect(
      find.text('Please wait a few seconds and try again.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tapCard(tester, 'Goat');
    expect(find.text('For grown-ups'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapCard(tester, 'Goat');
    await answerGate(tester, '56');
    expect(find.byType(PaywallScreen), findsOneWidget);
  });

  testWidgets('a cancelled gate does not start the cooldown', (tester) async {
    await pumpApp(tester);
    await openFarm(tester);
    await tapCard(tester, 'Goat');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tapCard(tester, 'Goat');
    expect(find.text('For grown-ups'), findsOneWidget);
  });

  testWidgets('a double tap opens one gate and one paywall', (tester) async {
    await pumpApp(tester);
    await openFarm(tester);
    await tester.ensureVisible(find.text('Goat'));
    await tester.pumpAndSettle();
    // Both taps land before the gate is drawn.
    final card = tester.widget<PictureCard>(
      find.ancestor(of: find.text('Goat'), matching: find.byType(PictureCard)),
    );
    card.onTap();
    card.onTap();
    await tester.pumpAndSettle();
    expect(find.text('For grown-ups'), findsOneWidget);
    await answerGate(tester, '56');
    expect(find.byType(PaywallScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('a paywall opened without the gate asks it first', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.push(paywallRoute());
    await tester.pumpAndSettle();
    expect(find.text('For grown-ups'), findsOneWidget);
    expect(find.text(r'Buy for $4.99'), findsNothing);
    expect(find.text('Privacy policy'), findsNothing);
    expect(find.text('Terms of use'), findsNothing);
    await answerGate(tester, '54');
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text('Cozy home'), findsOneWidget);
    await tester.pump(ParentalGateController.cooldown);

    router.push(paywallRoute());
    await tester.pumpAndSettle();
    await answerGate(tester, '56');
    expect(find.text(r'Buy for $4.99'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
  });

  testWidgets('the right answer opens the paywall; buying opens the picture', (
    tester,
  ) async {
    await pumpApp(tester);
    await openFarm(tester);
    await tapCard(tester, 'Goat');
    await answerGate(tester, '56');
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.text('One-time purchase, no subscription'), findsOneWidget);
    expect(
      find.text(
        'All ${testManifest.pictures.length} pictures in every category, '
        'and new ones as they arrive',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text(r'Buy for $4.99'));
    await tester.pumpAndSettle();
    // The tapped picture opens right away: the mode picker, then coloring.
    await pickMode(tester, 'Free');
    await pumpColoringFrames(tester);
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.byType(ColoringCanvas), findsOneWidget);
  });

  testWidgets('a locked card opens the paywall for that picture', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    await openFarm(tester);
    await tapCard(tester, 'Goat');
    await answerGate(tester, '56');
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(
      router.state.uri.toString(),
      paywallRoute(pictureId: 'farm_goat_swing'),
    );
    expect(
      tester.widget<PaywallScreen>(find.byType(PaywallScreen)).pictureId,
      'farm_goat_swing',
    );
  });

  // The paywall opened for a picture, with a stub coloring route that shows
  // the URL it was given: the coloring screen itself is not part of this flow.
  Future<void> pumpPaywallFor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('home'))),
          routes: [
            GoRoute(
              path: 'paywall',
              builder: (context, state) => PaywallScreen(
                pictureId: state.uri.queryParameters['from'],
                gatePassed: true,
              ),
            ),
            GoRoute(
              path: 'coloring/:id',
              builder: (context, state) =>
                  Scaffold(body: Text('stub ${state.uri}')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          purchaseServiceProvider.overrideWithValue(store),
          manifestProvider.overrideWith((ref) async => testManifest),
          workRepositoryProvider.overrideWithValue(works),
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
    router.push(paywallRoute(pictureId: 'farm_goat_swing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Buy for $4.99'));
    await tester.pumpAndSettle();
  }

  testWidgets('after a purchase a new work asks for its mode', (tester) async {
    await pumpPaywallFor(tester);
    await pickMode(tester, 'By numbers');
    await tester.pumpAndSettle();
    expect(
      find.text('stub /coloring/farm_goat_swing?mode=numbers'),
      findsOneWidget,
    );
    expect(find.byType(PaywallScreen), findsNothing);
  });

  testWidgets('after a purchase an unfinished work opens without a picker', (
    tester,
  ) async {
    await works.save(
      Work(
        id: 'goat-1',
        pictureId: 'farm_goat_swing',
        mode: ColoringMode.free,
        colors: Uint32List(3),
        modified: DateTime.utc(2026, 11, 1),
      ),
    );
    await pumpPaywallFor(tester);
    expect(find.text('How do you want to color?'), findsNothing);
    expect(
      find.text('stub /coloring/farm_goat_swing?work=goat-1'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the mode picker after a purchase goes back', (
    tester,
  ) async {
    await pumpPaywallFor(tester);
    expect(find.text('How do you want to color?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a cancelled purchase stays on the paywall', (tester) async {
    store.purchaseBehavior = FakePurchaseBehavior.cancel;
    final router = await pumpApp(tester);
    router.push(paywallRoute(), extra: paywallGatePassed);
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Buy for $4.99'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase cancelled'), findsOneWidget);
    expect(find.byType(PaywallScreen), findsOneWidget);
  });

  testWidgets('a store error is shown', (tester) async {
    store.purchaseBehavior = FakePurchaseBehavior.fail;
    final router = await pumpApp(tester);
    router.push(paywallRoute(), extra: paywallGatePassed);
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Buy for $4.99'));
    await tester.pumpAndSettle();
    expect(
      find.text("The purchase didn't go through. Try again."),
      findsOneWidget,
    );
    expect(find.byType(PaywallScreen), findsOneWidget);
  });

  testWidgets('a pending payment is not shown as a failure', (tester) async {
    store.purchaseBehavior = FakePurchaseBehavior.pending;
    final router = await pumpApp(tester);
    router.push(paywallRoute(), extra: paywallGatePassed);
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Buy for $4.99'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Payment is pending. The full version opens as soon as it completes.',
      ),
      findsOneWidget,
    );
    expect(
      find.text("The purchase didn't go through. Try again."),
      findsNothing,
    );
    expect(find.byType(PaywallScreen), findsOneWidget);
    // The payment clears later: the paywall closes by itself.
    store.setFullAccess(true);
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsNothing);
  });

  testWidgets('an already owned version unlocks through a restore', (
    tester,
  ) async {
    store
      ..purchaseBehavior = FakePurchaseBehavior.alreadyOwned
      ..restorable = true;
    final router = await pumpApp(tester);
    router.push(paywallRoute(), extra: paywallGatePassed);
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Buy for $4.99'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text('Cozy home'), findsOneWidget);
  });

  testWidgets('a failed restore says so', (tester) async {
    store.restoreFails = true;
    final router = await pumpApp(tester);
    router.push(paywallRoute(), extra: paywallGatePassed);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't restore purchases. Try again."), findsOneWidget);
    expect(
      find.text("The purchase didn't go through. Try again."),
      findsNothing,
    );
  });

  testWidgets('the price failing to load offers a retry', (tester) async {
    store.offerFails = true;
    final router = await pumpApp(tester);
    router.push(paywallRoute(), extra: paywallGatePassed);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't reach the store"), findsOneWidget);
    store.offerFails = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text(r'Buy for $4.99'), findsOneWidget);
  });

  testWidgets('the paywall lists the drawing tools', (tester) async {
    final router = await pumpApp(tester);
    router.push(paywallRoute(), extra: paywallGatePassed);
    await tester.pumpAndSettle();
    expect(
      find.text('All brushes, stamps, fill and mirror in Drawing'),
      findsOneWidget,
    );
  });

  testWidgets('restore on the paywall: nothing, then a purchase', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.push(paywallRoute(), extra: paywallGatePassed);
    await tester.pumpAndSettle();
    // The paywall card is taller than a phone screen.
    await tester.ensureVisible(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(find.text('No purchases to restore'), findsOneWidget);
    store.restorable = true;
    await tester.ensureVisible(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text('Cozy home'), findsOneWidget);
  });

  testWidgets(
    'a locked coloring route opens the gated paywall, then the picture',
    (tester) async {
      final router = await pumpApp(tester);
      router.push(coloringRoute('farm_goat_swing'));
      await tester.pumpAndSettle();
      expect(find.byType(ColoringScreen), findsNothing);
      expect(find.text(r'Buy for $4.99'), findsNothing);
      await answerGate(tester, '56');
      final paywall = tester.widget<PaywallScreen>(find.byType(PaywallScreen));
      expect(paywall.pictureId, 'farm_goat_swing');
      await tester.tap(find.text(r'Buy for $4.99'));
      await tester.pumpAndSettle();
      await pickMode(tester, 'Free');
      await tester.pump();
      await tester.pump();
      // Let the page transition finish.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PaywallScreen), findsNothing);
      final screen = tester.widget<ColoringScreen>(find.byType(ColoringScreen));
      expect(screen.request.pictureId, 'farm_goat_swing');
    },
  );

  testWidgets('a free coloring route opens without the gate', (tester) async {
    final router = await pumpApp(tester);
    router.push(coloringRoute('farm_piglet_picnic'));
    await pumpColoringFrames(tester);
    expect(find.text('For grown-ups'), findsNothing);
    expect(find.byType(ColoringCanvas), findsOneWidget);
  });

  testWidgets('a refund locks the paid cards again', (tester) async {
    store.setFullAccess(true);
    await pumpApp(tester);
    await openFarm(tester);
    await tester.ensureVisible(find.text('Goat'));
    expect(lockOf('Goat'), findsNothing);
    store.setFullAccess(false);
    await tester.pumpAndSettle();
    expect(lockOf('Goat'), findsOneWidget);
  });

  testWidgets('settings restore purchases and show the full version', (
    tester,
  ) async {
    store.restorable = true;
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Restore purchases'), 100);
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(find.text('Full version restored'), findsOneWidget);
    expect(find.text('Full version unlocked'), findsOneWidget);
  });

  group('reviewer access code', () {
    final codeHash = hashReviewCode('ABCD-EFGH-2345');

    testWidgets('is hidden when the build has no code', (tester) async {
      final router = await pumpApp(tester);
      router.push(paywallRoute(), extra: paywallGatePassed);
      await tester.pumpAndSettle();
      expect(find.text('I have an access code'), findsNothing);
    });

    Future<void> enterCode(WidgetTester tester, String code) async {
      await tester.ensureVisible(find.text('I have an access code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I have an access code'));
      await tester.pumpAndSettle();
      expect(find.text('Access code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), code);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('a wrong code keeps the paywall', (tester) async {
      final router = await pumpApp(tester, reviewCodeSha256: codeHash);
      router.push(paywallRoute(), extra: paywallGatePassed);
      await tester.pumpAndSettle();
      await enterCode(tester, 'ABCD-EFGH-2346');
      expect(find.text("This code doesn't work"), findsOneWidget);
      expect(find.byType(PaywallScreen), findsOneWidget);
    });

    testWidgets('the right code unlocks paid cards without a purchase', (
      tester,
    ) async {
      await pumpApp(tester, reviewCodeSha256: codeHash);
      await openFarm(tester);
      await tapCard(tester, 'Goat');
      await answerGate(tester, '56');
      await enterCode(tester, 'abcd efgh 2345');
      // The tapped picture opens right away, with no purchase.
      await pickMode(tester, 'Free');
      await pumpColoringFrames(tester);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byType(ColoringCanvas), findsOneWidget);
    });
  });
}
