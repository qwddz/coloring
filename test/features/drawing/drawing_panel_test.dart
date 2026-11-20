import 'package:coloring/features/drawing/drawing_panel.dart';
import 'package:coloring/features/drawing/drawing_state.dart';
import 'package:coloring/features/drawing/model/brush_size.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/drawing/model/symmetry.dart';
import 'package:coloring/features/palette/color_swatch.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _state = DrawingState(
  drawingId: 'drawing-1',
  tool: DrawingTool.pencil,
  color: 0xFF4A86C5,
  size: BrushSize.medium,
  symmetry: SymmetryMode.off,
  canUndo: true,
  canRedo: false,
  busy: false,
  isEmpty: false,
  revision: 1,
);

/// The panel alone, [width] × [height], selecting tools, colors and sizes in
/// place. Returns the callback log.
Future<List<String>> pumpPanel(
  WidgetTester tester, {
  required double width,
  required double height,
  bool fullAccess = false,
}) async {
  tester.view.physicalSize = Size(width + 40, height + 40);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final log = <String>[];
  var state = _state;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fullAccessProvider.overrideWith((ref) => Stream.value(fullAccess)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: StatefulBuilder(
                builder: (context, setState) => DrawingPanel(
                  state: state,
                  recent: const [0xFFE57373, 0xFF5FA05A],
                  onTool: (tool) {
                    log.add('tool ${tool.name}');
                    setState(() => state = state.copyWith(tool: tool));
                  },
                  onColor: (color) {
                    log.add('color ${color.toRadixString(16)}');
                    setState(() => state = state.copyWith(color: color));
                  },
                  onSize: (size) {
                    log.add('size ${size.name}');
                    setState(() => state = state.copyWith(size: size));
                  },
                  onUndo: () => log.add('undo'),
                  onRedo: () => log.add('redo'),
                  onMirror: () => log.add('mirror'),
                  onClear: () => log.add('clear'),
                  onNewSheet: () => log.add('new sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return log;
}

/// Whether the whole of [target] is inside the viewport of its scroll view.
bool fullyVisible(WidgetTester tester, Finder target) {
  final rect = tester.getRect(target);
  final viewport = tester.getRect(
    find.ancestor(of: target, matching: find.byType(Scrollable)).first,
  );
  return viewport.inflate(0.5).contains(rect.topLeft) &&
      viewport.inflate(0.5).contains(rect.bottomRight);
}

void main() {
  // The panel sizes of the drawing screen (spec §13) on 800 × 360 and
  // 870 × 390 phones and a 1280 × 800 tablet, plus a short phone where the
  // tools column scrolls.
  const panels = {
    '800x360': Size(317, 344),
    '870x390': Size(347, 374),
    '1280x800': Size(300, 784),
    'short': Size(300, 250),
  };

  for (final MapEntry(key: name, value: size) in panels.entries) {
    testWidgets('$name: fits, buttons are 48 dp, selected tool visible', (
      tester,
    ) async {
      await pumpPanel(tester, width: size.width, height: size.height);
      expect(tester.takeException(), isNull);
      for (final tooltip in [
        'Pencil',
        'Eraser',
        'Undo',
        'Redo',
        'Mirror: off',
        'Brush size',
        'Clear the sheet',
        'New sheet',
      ]) {
        final box = tester.getSize(find.byTooltip(tooltip));
        expect(box.width, greaterThanOrEqualTo(48), reason: tooltip);
        expect(box.height, greaterThanOrEqualTo(48), reason: tooltip);
      }
      expect(fullyVisible(tester, find.byTooltip('Pencil')), isTrue);

      // The last tool, scrolled to when the column is short.
      final fill = find.byTooltip('Fill: full version only');
      await tester.ensureVisible(fill);
      await tester.pumpAndSettle();
      await tester.tap(fill);
      await tester.pumpAndSettle();
      expect(fullyVisible(tester, fill), isTrue);

      // Back to the first one: the column scrolls back.
      await tester.drag(
        find.ancestor(of: fill, matching: find.byType(Scrollable)).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      final pencil = find.byTooltip('Pencil');
      await tester.ensureVisible(pencil);
      await tester.pumpAndSettle();
      await tester.tap(pencil);
      await tester.pumpAndSettle();
      expect(fullyVisible(tester, pencil), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selecting a tool off screen scrolls it into view', (
    tester,
  ) async {
    final log = await pumpPanel(
      tester,
      width: 300,
      height: 200,
      fullAccess: true,
    );
    final fill = find.byTooltip('Fill');
    expect(fullyVisible(tester, fill), isFalse);
    // The selection comes from elsewhere (the screen), not from a tap.
    final panel = tester.widget<DrawingPanel>(find.byType(DrawingPanel));
    panel.onTool(DrawingTool.fill);
    await tester.pumpAndSettle();
    expect(log, ['tool fill']);
    expect(fullyVisible(tester, fill), isTrue);
  });

  testWidgets('paid tools and the mirror show a lock without the full '
      'version', (tester) async {
    await pumpPanel(tester, width: 317, height: 344);
    for (final name in ['Pencil', 'Felt-tip', 'Marker', 'Eraser', 'Rainbow']) {
      expect(find.byTooltip(name), findsOneWidget, reason: name);
    }
    for (final name in [
      'Pastel',
      'Watercolor',
      'Airbrush',
      'Neon',
      'Stars',
      'Hearts',
      'Fill',
    ]) {
      expect(
        find.byTooltip('$name: full version only'),
        findsOneWidget,
        reason: name,
      );
    }
    // Seven tools and the mirror.
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(8));
  });

  testWidgets('no locks with the full version', (tester) async {
    await pumpPanel(tester, width: 317, height: 344, fullAccess: true);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.byTooltip('Fill'), findsOneWidget);
  });

  testWidgets('buttons forward their taps; clear asks first', (tester) async {
    final log = await pumpPanel(tester, width: 317, height: 344);
    await tester.tap(find.byTooltip('Undo'));
    await tester.tap(find.byTooltip('Redo'));
    await tester.tap(find.byTooltip('Mirror: off'));
    await tester.tap(find.byTooltip('New sheet'));
    expect(log, ['undo', 'mirror', 'new sheet'], reason: 'redo is disabled');

    await tester.tap(find.byTooltip('Clear the sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Clear the sheet?'), findsOneWidget);
    await tester.tap(find.text('No, keep it'));
    await tester.pumpAndSettle();
    expect(log, isNot(contains('clear')));
    await tester.tap(find.byTooltip('Clear the sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, clear'));
    await tester.pumpAndSettle();
    expect(log.last, 'clear');
  });

  testWidgets('the size menu shows four 48 dp sizes', (tester) async {
    final log = await pumpPanel(tester, width: 317, height: 344);
    await tester.tap(find.byTooltip('Brush size'));
    await tester.pumpAndSettle();
    for (final name in ['Small', 'Medium', 'Large', 'Huge']) {
      expect(
        tester.getSize(find.byTooltip(name)).shortestSide,
        greaterThanOrEqualTo(48),
      );
    }
    await tester.tap(find.byTooltip('Huge'));
    await tester.pumpAndSettle();
    expect(log, ['size huge']);
    expect(find.byTooltip('Huge'), findsNothing, reason: 'menu closed');
  });

  testWidgets('colors: recent first, the selected one ringed', (tester) async {
    final log = await pumpPanel(tester, width: 317, height: 344);
    final swatches = find.byType(PaletteSwatch);
    expect(swatches, findsNWidgets(2 + 24));
    expect(tester.widget<PaletteSwatch>(swatches.first).color, 0xFFE57373);
    expect(
      tester.widgetList<PaletteSwatch>(swatches).where((s) => s.selected),
      hasLength(1),
    );
    await tester.tap(swatches.first);
    expect(log, ['color ffe57373']);
  });
}
