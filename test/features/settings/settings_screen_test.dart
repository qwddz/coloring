import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/app/app.dart';
import 'package:coloring/app/book_palette.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:coloring/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final manifest = ContentManifest.fromJson(
    jsonDecode(File('assets/manifest.json').readAsStringSync()),
  );

  Future<ProviderContainer> openSettings(WidgetTester tester) async {
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
          manifestProvider.overrideWith((ref) async => manifest),
        ],
        child: const ColoringApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(ColoringApp)));
  }

  testWidgets('settings screen hides the music switch', (tester) async {
    await openSettings(tester);
    expect(showMusicSetting, isFalse);
    expect(find.widgetWithText(SwitchListTile, 'Music'), findsNothing);
    expect(find.widgetWithText(SwitchListTile, 'Sounds'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Vibration'), findsOneWidget);
    expect(find.byType(DropdownButton<String?>), findsOneWidget);
  });

  testWidgets('settings screen toggles sound and vibration', (tester) async {
    final container = await openSettings(tester);
    for (final (label, value) in [
      ('Sounds', () => container.read(settingsProvider).soundEnabled),
      ('Vibration', () => container.read(settingsProvider).vibrationEnabled),
    ]) {
      expect(value(), isTrue, reason: label);
      final row = find.widgetWithText(SwitchListTile, label);
      await tester.scrollUntilVisible(row, 100);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(value(), isFalse, reason: label);
    }
  });

  testWidgets('language picker is in the book style', (tester) async {
    await openSettings(tester);
    final dropdown = find.byType(DropdownButton<String?>);
    await tester.scrollUntilVisible(dropdown, 100);
    final button = tester.widget<DropdownButton<String?>>(dropdown);
    expect(button.dropdownColor, BookPalette.card);
    expect(button.borderRadius, BorderRadius.circular(12));
    expect(button.style?.color, BookPalette.text);
    expect(button.style?.fontFamily, 'Nunito');
    final box = tester.widget<DecoratedBox>(
      find.ancestor(of: dropdown, matching: find.byType(DecoratedBox)).first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, BookPalette.paperLight);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect((decoration.border! as Border).top.color, BookPalette.outline);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский').last);
    await tester.pumpAndSettle();
    expect(find.text('Язык'), findsOneWidget);
  });
}
