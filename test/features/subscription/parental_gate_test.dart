import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/app/theme.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/features/subscription/domain/parental_challenge.dart';
import 'package:coloring/features/subscription/parental_gate.dart';
import 'package:coloring/l10n/app_localizations.dart';

void main() {
  // The 20:9 emulator phone with the number keyboard leaves about 150 dp,
  // including the status bar.
  for (final (size, keyboard) in [
    (const Size(640, 360), 200.0),
    (const Size(915, 412), 260.0),
  ]) {
    testWidgets('gate keeps the field and OK visible at $size, keyboard '
        '$keyboard', (tester) async {
      await _openGateAndAnswer(tester, size, keyboard);
    });
  }
}

Future<void> _openGateAndAnswer(
  WidgetTester tester,
  Size size,
  double keyboard,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  bool? passed;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        parentalChallengeProvider.overrideWithValue(
          () => const ParentalChallenge(7, 8),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async =>
                  passed = await showParentalGate(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  // No RenderFlex overflow was reported while laying out the dialog.
  expect(tester.takeException(), isNull);

  final visibleBottom = size.height - keyboard;
  final field = find.byType(TextField);
  expect(field, findsOneWidget);
  final fieldRect = tester.getRect(field);
  expect(fieldRect.top, greaterThanOrEqualTo(24));
  expect(fieldRect.bottom, lessThanOrEqualTo(visibleBottom));
  // The question right above the field is in view too.
  final question = tester.getRect(find.textContaining('7 × 8'));
  expect(question.top, greaterThanOrEqualTo(24));

  await tester.enterText(field, '56');
  // Typing scrolls the field (and the question) back into view.
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('OK'));
  await tester.pumpAndSettle();
  final ok = tester.getRect(find.text('OK'));
  expect(ok.bottom, lessThanOrEqualTo(visibleBottom));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  expect(passed, isTrue);
}
