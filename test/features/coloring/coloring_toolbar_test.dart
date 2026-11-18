import 'package:coloring/app/widgets/book_button.dart';
import 'package:coloring/features/coloring/clear_confirm_dialog.dart';
import 'package:coloring/features/coloring/coloring_toolbar.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Calls {
  int undo = 0, eraser = 0, clear = 0, done = 0;
  final modes = <ColoringMode>[];
}

Future<void> pump(
  WidgetTester tester,
  Calls calls, {
  ColoringMode mode = ColoringMode.free,
  bool canUndo = true,
  bool canFinish = true,
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
            child: ColoringToolbar(
              mode: mode,
              canUndo: canUndo,
              canFinish: canFinish,
              eraserSelected: false,
              onUndo: () => calls.undo++,
              onEraser: () => calls.eraser++,
              onClear: () => calls.clear++,
              onDone: () => calls.done++,
              onModeChanged: calls.modes.add,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('undo is disabled when canUndo is false', (tester) async {
    final calls = Calls();
    await pump(tester, calls, canUndo: false);
    await tester.tap(find.byIcon(Icons.undo), warnIfMissed: false);
    expect(calls.undo, 0);
    await pump(tester, calls);
    await tester.tap(find.byIcon(Icons.undo));
    expect(calls.undo, 1);
  });

  testWidgets('eraser toggles outside magic mode only', (tester) async {
    final calls = Calls();
    await pump(tester, calls);
    await tester.tap(find.byIcon(Icons.cleaning_services));
    expect(calls.eraser, 1);
    await pump(tester, calls, mode: ColoringMode.magic);
    await tester.tap(find.byIcon(Icons.cleaning_services), warnIfMissed: false);
    expect(calls.eraser, 1);
  });

  testWidgets('done only in free mode and disabled below canFinish', (
    tester,
  ) async {
    final calls = Calls();
    await pump(tester, calls, canFinish: false);
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'), warnIfMissed: false);
    expect(calls.done, 0);

    await pump(tester, calls);
    await tester.tap(find.text('Done'));
    expect(calls.done, 1);

    await pump(tester, calls, mode: ColoringMode.numbers);
    expect(find.text('Done'), findsNothing);
    await pump(tester, calls, mode: ColoringMode.magic);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('mode switch reports the chosen mode', (tester) async {
    final calls = Calls();
    await pump(tester, calls);
    await tester.tap(find.byIcon(Icons.auto_fix_high));
    await tester.tap(find.text('1·2·3'));
    expect(calls.modes, [ColoringMode.magic, ColoringMode.numbers]);
  });

  testWidgets('confirming clear fires the callback', (tester) async {
    final calls = Calls();
    await pump(tester, calls);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Start over?'), findsOneWidget);
    expect(calls.clear, 0);
    await tester.tap(find.text('Yes, clear'));
    await tester.pumpAndSettle();
    expect(calls.clear, 1);
    expect(find.text('Start over?'), findsNothing);
  });

  testWidgets('cancelling clear does not fire the callback', (tester) async {
    final calls = Calls();
    await pump(tester, calls);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, keep it'));
    await tester.pumpAndSettle();
    expect(calls.clear, 0);
    expect(find.text('Start over?'), findsNothing);
  });

  testWidgets('dialog helper returns false when dismissed', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showClearConfirmDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  for (final size in const [Size(640, 360), Size(1280, 800)]) {
    for (final mode in ColoringMode.values) {
      testWidgets(
        'uk ${mode.name} fits ${size.width.toInt()}x${size.height.toInt()} '
        'with tappables >= 48',
        (tester) async {
          await pump(
            tester,
            Calls(),
            mode: mode,
            locale: const Locale('uk'),
            size: size,
          );
          expect(tester.takeException(), isNull);
          final tappables = find.descendant(
            of: find.byType(ColoringToolbar),
            matching: find.byType(GestureDetector),
          );
          expect(tappables, findsWidgets);
          for (final e in tappables.evaluate()) {
            final s = tester.getSize(find.byWidget(e.widget));
            expect(s.width, greaterThanOrEqualTo(48));
            expect(s.height, greaterThanOrEqualTo(48));
          }
          if (mode == ColoringMode.free) {
            expect(find.byType(BookButton), findsOneWidget);
          }
        },
      );
    }
  }
}
