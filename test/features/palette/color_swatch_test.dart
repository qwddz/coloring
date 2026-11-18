import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:coloring/features/palette/color_swatch.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('is at least 48x48 and fires onTap', (tester) async {
    var taps = 0;
    await pump(
      tester,
      PaletteSwatch(color: 0xFFE57373, selected: false, onTap: () => taps++),
    );
    final size = tester.getSize(find.byType(PaletteSwatch));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    await tester.tap(find.byType(PaletteSwatch));
    expect(taps, 1);
  });

  testWidgets('shows the number and a semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      PaletteSwatch(
        color: 0xFFE57373,
        selected: true,
        number: 3,
        progress: const PaletteProgress(1, 4),
        onTap: () {},
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.bySemanticsLabel('Color 3'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('shows a check instead of the number when done', (tester) async {
    await pump(
      tester,
      PaletteSwatch(
        color: 0xFF2D4F8A,
        selected: false,
        number: 2,
        progress: const PaletteProgress(4, 4),
        onTap: () {},
      ),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('2'), findsNothing);
  });
}
