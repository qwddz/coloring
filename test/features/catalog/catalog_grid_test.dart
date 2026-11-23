import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/app/app.dart';
import 'package:coloring/app/book_palette.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:coloring/features/audio/audio_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coloring/app/theme.dart';
import 'package:coloring/features/catalog/catalog_grid.dart';

import '../../support/fake_audio_backend.dart';

void main() {
  test('3 columns on phones, 4–5 on tablets', () {
    expect(catalogColumns(width: 915, shortestSide: 411), 3);
    expect(catalogColumns(width: 640, shortestSide: 360), 3);
    // 8-inch tablet in landscape is narrower than 1000 dp but still a tablet.
    expect(catalogColumns(width: 960, shortestSide: 600), 4);
    expect(catalogColumns(width: 1280, shortestSide: 800), 4);
    expect(catalogColumns(width: 1600, shortestSide: 1000), 5);
  });

  Future<void> pumpGrid(
    WidgetTester tester, {
    bool disableAnimations = false,
    String? lockedLabel,
    Size size = const Size(800, 360),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: CatalogGrid(
              itemCount: 6,
              itemBuilder: (context, index) => PictureCard(
                index: index,
                image: null,
                lockedLabel: lockedLabel,
                onTap: () {},
                caption: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Затишний дім',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.star_rounded, color: BookPalette.star),
                    Text('0 of 27', style: TextStyle(color: BookPalette.star)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpRealCatalog(
    WidgetTester tester, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final json = jsonDecode(
      File('assets/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final categories = json['categories'] as List;
    (categories[0]['title'] as Map)['en'] = 'Home sweet home';
    (categories[1]['title'] as Map)['en'] =
        'An extremely long category name that cannot fit';
    // Keep one empty category so the coming-soon badge is on screen.
    categories[1]['pictures'] = <dynamic>[];
    final manifest = ContentManifest.fromJson(json);
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          audioBackendProvider.overrideWithValue(FakeAudioBackend()),
          manifestProvider.overrideWith((ref) async => manifest),
        ],
        child: const ColoringApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('card caption ellipsizes; the coming-soon badge stays in', (
    tester,
  ) async {
    await pumpRealCatalog(tester);
    expect(tester.takeException(), isNull);
    final longTitle = find.text(
      'An extremely long category name that cannot fit',
    );
    expect(
      tester.renderObject<RenderParagraph>(longTitle).didExceedMaxLines,
      isTrue,
    );
    final card = find.ancestor(
      of: longTitle,
      matching: find.byType(PictureCard),
    );
    final badge = find.descendant(of: card, matching: find.text('Coming soon'));
    expect(badge, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(badge).didExceedMaxLines,
      isFalse,
    );
    final cardRect = tester.getRect(card);
    final badgeRect = tester.getRect(badge);
    expect(badgeRect.right, lessThanOrEqualTo(cardRect.right));
    expect(badgeRect.left, greaterThan(cardRect.left));
    final style = tester.widget<Text>(badge).style;
    expect(style?.color, BookPalette.textMuted);
    expect(find.text('Home sweet home'), findsOneWidget);
  });

  testWidgets('captions fit at 1.5x system text scale', (tester) async {
    await pumpRealCatalog(tester, textScale: 1.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked card shows a warm lock', (tester) async {
    await pumpGrid(tester, lockedLabel: 'Locked');
    final icon = tester.widget<Icon>(find.byIcon(Icons.lock_rounded).first);
    expect(icon.color, BookPalette.card);
    final circle = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.byIcon(Icons.lock_rounded).first,
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((circle.decoration as BoxDecoration).color, BookPalette.primary);
  });

  testWidgets('cards tilt in alternating directions', (tester) async {
    await pumpGrid(tester);
    final angles = tester
        .widgetList<Transform>(
          find.descendant(
            of: find.byType(PictureCard),
            matching: find.byType(Transform),
          ),
        )
        .map((t) => t.transform.getRotation().storage[1])
        .where((a) => a != 0)
        .toList();
    expect(angles.take(2).map((a) => a.sign), [-1, 1]);
  });

  testWidgets('tilt does not shift the hit area', (tester) async {
    var taps = 0;
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 220,
            child: PictureCard(
              index: 0,
              image: null,
              caption: const Text('x'),
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(PictureCard));
    await tester.tapAt(rect.topLeft + const Offset(2, 2));
    await tester.tapAt(rect.bottomRight - const Offset(2, 2));
    expect(taps, 2);
  });

  testWidgets('card has no press animation with reduced motion', (
    tester,
  ) async {
    await pumpGrid(tester, disableAnimations: true);
    expect(find.byType(AnimatedScale), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PictureCard).first),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(AnimatedScale), findsNothing);
    await gesture.up();
    await pumpGrid(tester);
    expect(find.byType(AnimatedScale), findsWidgets);
  });
}
