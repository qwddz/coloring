import 'package:coloring/app/theme.dart';
import 'package:coloring/features/catalog/mode_picker_dialog.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Future<ColoringMode?> Function()> pumpPicker(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return () => showModePicker(context);
  }

  testWidgets('shows the three modes and returns the tapped one', (
    tester,
  ) async {
    final open = await pumpPicker(tester);
    final result = open();
    await tester.pumpAndSettle();
    expect(find.text('How do you want to color?'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('By numbers'), findsOneWidget);
    expect(find.text('Magic brush'), findsOneWidget);
    expect(find.text('Choose any colors you like'), findsOneWidget);
    await tester.tap(find.text('Magic brush'));
    await tester.pumpAndSettle();
    expect(await result, ColoringMode.magic);
  });

  testWidgets('cancel returns null', (tester) async {
    final open = await pumpPicker(tester);
    final result = open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('option cards are at least 48 dp tall, Cancel too', (
    tester,
  ) async {
    final open = await pumpPicker(tester);
    open();
    await tester.pumpAndSettle();
    for (final name in ['Free', 'By numbers', 'Magic brush']) {
      final card = find.ancestor(
        of: find.text(name),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(card).width, greaterThanOrEqualTo(48));
    }
    final cancel = find.ancestor(
      of: find.text('Cancel'),
      matching: find.byType(ConstrainedBox),
    );
    expect(tester.getSize(cancel.first).height, greaterThanOrEqualTo(48));
  });
}
