import 'dart:convert';
import 'dart:io';

import 'package:coloring/app/app.dart';
import 'package:coloring/app/router.dart';
import 'package:coloring/app/widgets/book_button.dart';
import 'package:coloring/app/widgets/paper_background.dart';
import 'package:coloring/features/catalog/catalog_grid.dart';
import 'package:coloring/features/catalog/categories_screen.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/coloring/coloring_screen.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_manifest.dart';

void main() {
  final bundled = ContentManifest.fromJson(
    jsonDecode(File('assets/manifest.json').readAsStringSync()),
  );

  Future<void> pumpApp(
    WidgetTester tester,
    List<Locale> deviceLocales, {
    Map<String, Object> preferences = const {},
    ContentManifest? manifest,
  }) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = deviceLocales;
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    SharedPreferences.setMockInitialValues(preferences);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // rootBundle caches loads across tests; read the file directly.
          manifestProvider.overrideWith((ref) async => manifest ?? bundled),
        ],
        child: const ColoringApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PictureCard), findsWidgets);
  }

  GoRouter router(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ColoringApp)))
          .read(routerProvider);

  testWidgets('all ten categories in English, empty ones coming soon', (
    tester,
  ) async {
    await pumpApp(tester, const [Locale('en', 'US')]);
    expect(find.text('Animosaic Colors'), findsOneWidget);
    expect(find.text('Cozy home'), findsOneWidget);
    for (final category in bundled.categories) {
      final title = category.title.resolve('en');
      await tester.scrollUntilVisible(find.text(title), 200);
      final card = find.ancestor(
        of: find.text(title),
        matching: find.byType(PictureCard),
      );
      expect(
        find.descendant(of: card, matching: find.text('Coming soon')),
        category.pictures.isEmpty ? findsOneWidget : findsNothing,
        reason: title,
      );
    }
    expect(bundled.categories, hasLength(10));
  });

  testWidgets('an empty category says pictures are coming', (tester) async {
    // The bundled manifest fills up as pictures are exported, so empty the
    // first category here instead of relying on one being empty.
    final json = jsonDecode(
      File('assets/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final first = (json['categories'] as List).first as Map<String, dynamic>;
    first['pictures'] = <Object>[];
    await pumpApp(tester, const [
      Locale('en', 'US'),
    ], manifest: ContentManifest.fromJson(json));
    await tester.tap(find.text('Cozy home'));
    await tester.pumpAndSettle();
    expect(find.byType(PaperBackground), findsWidgets);
    expect(
      find.text('New pictures for this category are coming soon'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(BookButton, 'Back'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesScreen), findsOneWidget);
  });

  testWidgets('first launch opens the catalog straight away', (tester) async {
    await pumpApp(tester, const [Locale('en', 'US')]);
    expect(router(tester).state.matchedLocation, '/');
    expect(find.byType(CategoriesScreen), findsOneWidget);
  });

  testWidgets('device language Ukrainian', (tester) async {
    await pumpApp(tester, const [Locale('uk', 'UA')]);
    expect(find.text('Animosaic Розмальовки'), findsOneWidget);
    expect(find.text('Затишний дім'), findsOneWidget);
  });

  testWidgets('unsupported device language falls back to English', (
    tester,
  ) async {
    await pumpApp(tester, const [Locale('de', 'DE')]);
    expect(find.text('Animosaic Colors'), findsOneWidget);
  });

  testWidgets('language chosen in settings beats the device language', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const [Locale('en', 'US')],
      preferences: {'settings.language': 'ru'},
    );
    expect(find.text('Animosaic Раскраски'), findsOneWidget);
    expect(find.text('Уютный дом'), findsOneWidget);
  });

  testWidgets('a free picture opens the coloring screen and goes back', (
    tester,
  ) async {
    await pumpApp(tester, const [Locale('en', 'US')], manifest: testManifest);
    await tester.tap(find.text('On the farm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Piglet'));
    await tester.pumpAndSettle();
    final screen = tester.widget<ColoringScreen>(find.byType(ColoringScreen));
    expect(screen.pictureId, 'farm_piglet_picnic');
    expect(find.text('Coloring is coming soon'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ColoringScreen), findsNothing);
    expect(find.text('Piglet'), findsOneWidget);
  });

  testWidgets('settings screen switches the language', (tester) async {
    await pumpApp(tester, const [Locale('en', 'US')]);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Same as device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Українська').last);
    await tester.pumpAndSettle();
    expect(find.text('Налаштування'), findsOneWidget);
    expect(find.text('Мова'), findsOneWidget);
  });

  testWidgets('an unknown category offers a way back', (tester) async {
    await pumpApp(tester, const [Locale('en', 'US')]);
    router(tester).push('/category/nope');
    await tester.pumpAndSettle();
    expect(find.text('This category is not available'), findsOneWidget);
    await tester.tap(find.widgetWithText(BookButton, 'Back'));
    await tester.pumpAndSettle();
    expect(find.text('Cozy home'), findsOneWidget);
  });
}
