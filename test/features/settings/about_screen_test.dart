import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/app/app.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/content/content_config.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/features/subscription/domain/parental_challenge.dart';
import 'package:coloring/features/settings/about_screen.dart';
import 'package:coloring/features/settings/data/about_links.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:coloring/features/audio/audio_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio_backend.dart';

void main() {
  final manifest = ContentManifest.fromJson(
    jsonDecode(File('assets/manifest.json').readAsStringSync()),
  );
  late List<Uri> launched;

  setUp(() => launched = []);

  Future<void> openAbout(WidgetTester tester) async {
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
          audioBackendProvider.overrideWithValue(FakeAudioBackend()),
          manifestProvider.overrideWith((ref) async => manifest),
          parentalChallengeProvider.overrideWithValue(
            () => const ParentalChallenge(7, 8),
          ),
          appVersionProvider.overrideWith((ref) async => '1.2.3'),
          externalLinkLauncherProvider.overrideWithValue((url) async {
            launched.add(url);
            return true;
          }),
        ],
        child: const ColoringApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('About'), 100);
    await tester.ensureVisible(find.text('About'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
  }

  Future<void> tapLink(WidgetTester tester, String title) async {
    await tester.scrollUntilVisible(find.text(title), 100);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> answerGate(WidgetTester tester, String answer) async {
    expect(find.text('For grown-ups'), findsOneWidget);
    await tester.enterText(find.byType(TextField), answer);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the name, version and credits', (tester) async {
    await openAbout(tester);
    expect(find.text('Animosaic Colors'), findsOneWidget);
    expect(find.text('Version 1.2.3'), findsOneWidget);
    expect(find.text(contactEmail), findsOneWidget);
    expect(find.textContaining('AI image generation'), findsOneWidget);
  });

  testWidgets('every link asks the parental gate before opening', (
    tester,
  ) async {
    await openAbout(tester);
    final links = {
      'Privacy policy': privacyPolicyUrl,
      'Terms of use': termsOfUseUrl,
      'Contact us': Uri.parse('mailto:pirate.dmitry@gmail.com'),
    };
    for (final MapEntry(key: title, value: url) in links.entries) {
      await tapLink(tester, title);
      expect(launched, isEmpty);
      await answerGate(tester, '56');
      expect(launched, [url]);
      launched.clear();
    }
  });

  testWidgets('a wrong or cancelled gate opens nothing', (tester) async {
    await openAbout(tester);
    await tapLink(tester, 'Privacy policy');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    await tapLink(tester, 'Terms of use');
    await answerGate(tester, '54');
    expect(launched, isEmpty);
    expect(find.text('For grown-ups'), findsNothing);
    // Let the wrong-answer cooldown run out.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('back returns to settings', (tester) async {
    await openAbout(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });
}
