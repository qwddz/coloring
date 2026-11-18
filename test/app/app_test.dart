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
import 'package:coloring/features/coloring/coloring_canvas.dart';
import 'package:coloring/features/coloring/coloring_controller.dart';
import 'package:coloring/features/coloring/coloring_screen.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/gallery/my_works_screen.dart';
import 'package:coloring/features/gallery/work_actions_dialog.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/coloring/fakes.dart';
import '../features/coloring/model/fixtures.dart';
import '../features/gallery/fake_preview_service.dart';
import '../support/coloring_overrides.dart';
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
    InMemoryWorkRepository? works,
    FakePreviewService? previews,
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
          ...coloringScreenOverrides(works: works, previews: previews),
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
    await tester.tap(find.text('Free'));
    await pumpColoringFrames(tester);
    final screen = tester.widget<ColoringScreen>(find.byType(ColoringScreen));
    expect(
      screen.request,
      const ColoringRequest('farm_piglet_picnic', newMode: ColoringMode.free),
    );
    expect(find.byType(ColoringCanvas), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ColoringScreen), findsNothing);
    expect(find.text('Piglet'), findsOneWidget);
  });

  testWidgets('catalog → coloring → «My works» → continue the same work', (
    tester,
  ) async {
    final works = InMemoryWorkRepository();
    final previews = FakePreviewService();
    await pumpApp(
      tester,
      const [Locale('en', 'US')],
      manifest: testManifest,
      works: works,
      previews: previews,
    );
    await tester.tap(find.text('On the farm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Piglet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('By numbers'));
    await pumpColoringFrames(tester);
    final newWork = tester.widget<ColoringScreen>(find.byType(ColoringScreen));
    expect(
      newWork.request,
      const ColoringRequest(
        'farm_piglet_picnic',
        newMode: ColoringMode.numbers,
      ),
    );

    // One fill: numbers mode starts on red, the color of region 1.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ColoringScreen)),
    );
    final (x, y) = fixtureLabels[1]!;
    container
        .read(coloringControllerProvider(newWork.request).notifier)
        .tap(x, y, tolerance: 4);
    await tester.pump();
    final work = works.saves.last;
    expect(work.pictureId, 'farm_piglet_picnic');
    expect(work.mode, ColoringMode.numbers);
    expect(work.colors[1], red);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ColoringScreen), findsNothing);
    // Leaving the screen queued its preview.
    expect(previews.calls.single.workId, work.id);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesScreen), findsOneWidget);

    await tester.tap(find.byTooltip('My works'));
    await tester.pumpAndSettle();
    expect(find.byType(MyWorksScreen), findsOneWidget);
    expect(find.byType(PictureCard), findsOneWidget);
    expect(find.text('Piglet'), findsOneWidget);
    await tester.tap(find.byType(PictureCard));
    await tester.pumpAndSettle();
    expect(find.byType(WorkActionsDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(BookButton, 'Continue'));
    await pumpColoringFrames(tester);

    final continued = tester.widget<ColoringScreen>(
      find.byType(ColoringScreen),
    );
    expect(
      continued.request,
      ColoringRequest('farm_piglet_picnic', workId: work.id),
    );
    expect(router(tester).state.uri.toString(), contains('work=${work.id}'));
    final state = container
        .read(coloringControllerProvider(continued.request))
        .requireValue;
    expect(state.mode, ColoringMode.numbers);
    expect(state.filledFraction, greaterThan(0));
    expect(works.saves.last.id, work.id);
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
