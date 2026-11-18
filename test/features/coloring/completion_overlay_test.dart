import 'package:coloring/app/theme.dart';
import 'package:coloring/app/widgets/book_button.dart';
import 'package:coloring/features/coloring/completion_overlay.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpOverlay(
    WidgetTester tester, {
    Size size = const Size(640, 360),
    Locale locale = const Locale('uk'),
    bool disableAnimations = true,
    VoidCallback? onKeep,
    VoidCallback? onBack,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: Scaffold(
          body: CompletionOverlay(
            onKeepColoring: onKeep ?? () {},
            onBack: onBack ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('both buttons fire their callbacks', (tester) async {
    var keep = 0;
    var back = 0;
    await pumpOverlay(
      tester,
      locale: const Locale('en'),
      onKeep: () => keep++,
      onBack: () => back++,
    );
    await tester.tap(find.text('Keep coloring'));
    expect((keep, back), (1, 0));
    await tester.tap(find.text('Back to pictures'));
    expect((keep, back), (1, 1));
    expect(find.text('Great job!'), findsOneWidget);
  });

  testWidgets('with disableAnimations nothing keeps animating', (tester) async {
    await pumpOverlay(tester);
    await tester.pumpAndSettle();
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('with animations on, the confetti ends by itself', (
    tester,
  ) async {
    await pumpOverlay(tester, disableAnimations: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });

  for (final size in const [Size(640, 360), Size(1280, 800)]) {
    testWidgets('fits $size in uk with buttons of at least 48 dp', (
      tester,
    ) async {
      await pumpOverlay(tester, size: size);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Розмальовувати далі', 'До картинок']) {
        final finder = find.text(label);
        expect(finder, findsOneWidget, reason: label);
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }
      for (final r
          in tester
              .widgetList(find.byType(BookButton))
              .map((w) => tester.getRect(find.byWidget(w)))) {
        expect(r.height, greaterThanOrEqualTo(48));
      }
    });
  }
}
