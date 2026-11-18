import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:coloring/features/palette/color_swatch.dart';
import 'package:coloring/features/palette/domain/base_palette.dart';
import 'package:coloring/features/palette/palette_panel.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const picture = [0xFFE57373, 0xFF7FB8DF, 0xFF5FA05A];
const sizes = [Size(640, 360), Size(1280, 800)];

Future<void> pump(
  WidgetTester tester, {
  required ColoringMode mode,
  List<int> recent = const [],
  int? selected,
  bool eraser = false,
  ValueChanged<int>? onSelected,
  Locale locale = const Locale('en'),
  Size size = const Size(640, 360),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 220,
            child: PalettePanel(
              mode: mode,
              picturePalette: picture,
              recent: recent,
              selectedColor: selected,
              eraserSelected: eraser,
              progress: const [
                PaletteProgress(1, 4),
                PaletteProgress(2, 2),
                PaletteProgress(0, 3),
              ],
              onColorSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('base palette has 24 distinct opaque colors', () {
    expect(basePalette.length, 24);
    expect(basePalette.toSet().length, 24);
    expect(basePalette.every((c) => c >> 24 == 0xFF), isTrue);
  });

  testWidgets('free mode shows three sections, Recent hidden when empty', (
    tester,
  ) async {
    await pump(tester, mode: ColoringMode.free);
    expect(find.text('Picture colors'), findsOneWidget);
    expect(find.text('All colors'), findsOneWidget);
    expect(find.text('Recent'), findsNothing);

    await pump(tester, mode: ColoringMode.free, recent: [0xFF2D4F8A]);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Picture colors'), findsOneWidget);
  });

  testWidgets('free mode offers all swatches and reports the tapped color', (
    tester,
  ) async {
    int? tapped;
    await pump(
      tester,
      mode: ColoringMode.free,
      recent: [0xFF2D4F8A],
      onSelected: (c) => tapped = c,
    );
    await tester.scrollUntilVisible(
      find.byType(PaletteSwatch).last,
      50,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.byType(PaletteSwatch).last);
    expect(tapped, basePalette.last);
    expect(find.byType(PaletteSwatch, skipOffstage: false), findsNWidgets(28));
  });

  testWidgets('numbers mode shows only picture colors with numbers', (
    tester,
  ) async {
    await pump(tester, mode: ColoringMode.numbers, recent: [0xFF2D4F8A]);
    expect(find.byType(PaletteSwatch), findsNWidgets(3));
    expect(find.text('Picture colors'), findsOneWidget);
    expect(find.text('All colors'), findsNothing);
    expect(find.text('Recent'), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // Palette index 1 is fully done: a check replaces its number.
    expect(find.text('2'), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('magic mode shows the hint and no swatches', (tester) async {
    await pump(tester, mode: ColoringMode.magic);
    expect(
      find.text('Draw with your finger and the picture will color itself!'),
      findsOneWidget,
    );
    expect(find.byType(PaletteSwatch), findsNothing);
  });

  testWidgets('selection ring follows selectedColor, not while erasing', (
    tester,
  ) async {
    bool selectedOf(WidgetTester t, int i) =>
        t.widget<PaletteSwatch>(find.byType(PaletteSwatch).at(i)).selected;
    await pump(tester, mode: ColoringMode.numbers, selected: picture[1]);
    expect(
      [for (var i = 0; i < 3; i++) selectedOf(tester, i)],
      [false, true, false],
    );
    await pump(
      tester,
      mode: ColoringMode.numbers,
      selected: picture[1],
      eraser: true,
    );
    expect(
      [for (var i = 0; i < 3; i++) selectedOf(tester, i)],
      [false, false, false],
    );
  });

  for (final size in sizes) {
    for (final mode in ColoringMode.values) {
      testWidgets(
        'uk ${mode.name} fits ${size.width.toInt()}x${size.height.toInt()} '
        'with tappables >= 48',
        (tester) async {
          await pump(
            tester,
            mode: mode,
            recent: [0xFF2D4F8A],
            locale: const Locale('uk'),
            size: size,
          );
          expect(tester.takeException(), isNull);
          for (final e
              in find.byType(PaletteSwatch, skipOffstage: false).evaluate()) {
            final s = tester.getSize(find.byWidget(e.widget));
            expect(s.width, greaterThanOrEqualTo(48));
            expect(s.height, greaterThanOrEqualTo(48));
          }
        },
      );
    }
  }
}
