import 'dart:async';
import 'dart:typed_data';

import 'package:coloring/app/app.dart';
import 'package:coloring/app/router.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/drawing/drawing_canvas.dart';
import 'package:coloring/features/drawing/drawing_controller.dart';
import 'package:coloring/features/drawing/drawing_route.dart';
import 'package:coloring/features/drawing/drawing_screen.dart';
import 'package:coloring/features/drawing/drawing_state.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/palette/color_swatch.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/features/subscription/domain/parental_challenge.dart';
import 'package:coloring/features/subscription/domain/purchase_service.dart';
import 'package:coloring/features/subscription/paywall_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/coloring_overrides.dart';
import '../../support/test_manifest.dart';
import 'controller_harness.dart';
import 'fakes.dart';

void main() {
  late FakePurchaseService store;
  late InMemoryDrawingRepository drawings;
  late ManualTimers timers;

  setUp(() {
    store = FakePurchaseService();
    drawings = InMemoryDrawingRepository();
    timers = ManualTimers();
  });

  /// The app at [size] (dp) with the drawing screen open at [route].
  Future<GoRouter> pumpDrawing(
    WidgetTester tester, {
    Size size = const Size(800, 360),
    String route = '/draw',
    Stream<bool> Function()? fullAccess,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          manifestProvider.overrideWith((ref) async => testManifest),
          purchaseServiceProvider.overrideWithValue(store),
          if (fullAccess != null)
            fullAccessProvider.overrideWith((ref) => fullAccess()),
          parentalChallengeProvider.overrideWithValue(
            () => const ParentalChallenge(7, 8),
          ),
          drawingSaveTimerProvider.overrideWithValue(timers.call),
          ...coloringScreenOverrides(drawings: drawings),
        ],
        child: const ColoringApp(),
      ),
    );
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(
      tester.element(find.byType(ColoringApp)),
    ).read(routerProvider);
    router.push(route);
    await settle(
      tester,
      () => find.byType(DrawingCanvas).evaluate().isNotEmpty,
    );
    return router;
  }

  DrawingRequest requestOf(WidgetTester tester) =>
      tester.widget<DrawingScreen>(find.byType(DrawingScreen)).request;

  /// The transition is over and the one screen left opened another sheet.
  bool onlyScreenIsNot(WidgetTester tester, DrawingRequest request) =>
      find.byType(DrawingScreen).evaluate().length == 1 &&
      requestOf(tester) != request;

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(DrawingScreen)));

  DrawingController controllerOf(WidgetTester tester) =>
      containerOf(tester)
          .read(drawingControllerProvider(requestOf(tester)).notifier);

  DrawingState stateOf(WidgetTester tester) =>
      containerOf(tester)
          .read(drawingControllerProvider(requestOf(tester)))
          .requireValue;

  /// The committed pixels after every queued change. Started in the test
  /// zone and pumped, since queued work may wait on its microtasks.
  Future<Uint8List> pixels(WidgetTester tester) async {
    final controller = controllerOf(tester);
    Uint8List? result;
    unawaited(
      controller.idle
          .then((_) => controller.engine!.readback())
          .then((bytes) => result = Uint8List.fromList(bytes)),
    );
    await settle(tester, () => result != null);
    return result!;
  }

  Future<void> drawOnCanvas(WidgetTester tester) async {
    final canvas = tester.getRect(find.byType(DrawingCanvas));
    final gesture = await tester.startGesture(canvas.center);
    for (var i = 1; i <= 5; i++) {
      await gesture.moveTo(canvas.center + Offset(i * 12.0, i * 6.0));
    }
    await gesture.up();
    await settle(tester, () => stateOf(tester).canUndo);
  }

  Future<void> answerGate(WidgetTester tester, String answer) async {
    expect(find.text('For grown-ups'), findsOneWidget);
    await tester.enterText(find.byType(TextField), answer);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(800, 360), Size(870, 390), Size(1280, 800)]) {
    testWidgets('${size.width.round()}x${size.height.round()}: canvas and '
        'panel fit, the selected tool is visible', (tester) async {
      await pumpDrawing(tester, size: size);
      expect(tester.takeException(), isNull);
      final canvas = tester.getRect(find.byType(DrawingCanvas));
      expect(canvas.width / canvas.height, closeTo(4 / 3, 0.01));
      final screen = Offset.zero & size;
      for (final tooltip in ['Back', 'Pencil', 'New sheet', 'Brush size']) {
        final rect = tester.getRect(find.byTooltip(tooltip));
        expect(screen.contains(rect.bottomRight), isTrue, reason: tooltip);
        expect(rect.shortestSide, greaterThanOrEqualTo(48), reason: tooltip);
      }
      expect(
        tester.getRect(find.byTooltip('Pencil')).left,
        greaterThan(canvas.right),
      );
      await tester.tap(find.byTooltip('Rainbow'));
      await tester.pumpAndSettle();
      expect(stateOf(tester).tool, DrawingTool.rainbow);
      final rainbow = tester.getRect(find.byTooltip('Rainbow'));
      expect(screen.contains(rainbow.bottomRight), isTrue);
    });
  }

  testWidgets('a finger stroke changes the pixels and enables undo', (
    tester,
  ) async {
    await pumpDrawing(tester);
    final before = await pixels(tester);
    expect(stateOf(tester).canUndo, isFalse);
    await drawOnCanvas(tester);
    expect(await pixels(tester), isNot(before));

    await tester.tap(find.byTooltip('Undo'));
    await settle(tester, () => !stateOf(tester).canUndo);
    expect(await pixels(tester), before);
    expect(stateOf(tester).canRedo, isTrue);
  });

  testWidgets('a second finger zooms without drawing', (tester) async {
    await pumpDrawing(tester);
    final before = await pixels(tester);
    final canvas = tester.getRect(find.byType(DrawingCanvas));
    final a = await tester.startGesture(canvas.center - const Offset(40, 0));
    final b = await tester.startGesture(
      canvas.center + const Offset(40, 0),
      pointer: 2,
    );
    for (var i = 1; i <= 4; i++) {
      await a.moveTo(canvas.center - Offset(40.0 + i * 15, 0));
      await b.moveTo(canvas.center + Offset(40.0 + i * 15, 0));
    }
    await a.up();
    await b.up();
    await tester.pump();
    final view = tester.state<DrawingCanvasState>(find.byType(DrawingCanvas));
    expect(view.viewport!.zoom, greaterThan(1.5));
    expect(stateOf(tester).canUndo, isFalse);
    expect(stateOf(tester).revision, 0);
    expect(await pixels(tester), before);
  });

  testWidgets('a locked tool asks the gate; buying selects it', (tester) async {
    await pumpDrawing(tester);
    await tester.tap(find.byTooltip('Watercolor: full version only'));
    await tester.pumpAndSettle();
    await answerGate(tester, '56');
    expect(find.byType(PaywallScreen), findsOneWidget);
    await tester.tap(find.text(r'Buy for $4.99'));
    await settle(tester, () => find.byType(PaywallScreen).evaluate().isEmpty);
    await settle(tester, () => stateOf(tester).tool == DrawingTool.watercolor);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
  });

  testWidgets('a wrong gate answer keeps the tool', (tester) async {
    await pumpDrawing(tester);
    await tester.tap(find.byTooltip('Mirror: off'));
    await tester.pumpAndSettle();
    await answerGate(tester, '1');
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.byType(DrawingScreen), findsOneWidget);
    expect(stateOf(tester).tool, DrawingTool.pencil);
    await tester.tap(find.byTooltip('Mirror: off'));
    await tester.pumpAndSettle();
    expect(find.text('For grown-ups'), findsNothing, reason: 'cooldown');
  });

  testWidgets('a buyer whose access loads slowly gets the tool, no gate', (
    tester,
  ) async {
    final access = StreamController<bool>();
    addTearDown(access.close);
    await pumpDrawing(tester, fullAccess: () => access.stream);
    // Locked-looking while the status loads.
    await tester.tap(find.byTooltip('Fill: full version only'));
    await tester.pump();
    expect(find.text('For grown-ups'), findsNothing);
    access.add(true);
    await tester.pumpAndSettle();
    expect(find.text('For grown-ups'), findsNothing);
    expect(stateOf(tester).tool, DrawingTool.fill);
  });

  testWidgets('a color picked with the eraser goes back to the tool before '
      'it', (tester) async {
    await pumpDrawing(tester);
    await tester.tap(find.byTooltip('Marker'));
    await tester.tap(find.byTooltip('Eraser'));
    await tester.pumpAndSettle();
    expect(stateOf(tester).tool, DrawingTool.eraser);
    final colors = find.byType(PaletteSwatch);
    await tester.tap(colors.at(3));
    await tester.pumpAndSettle();
    expect(stateOf(tester).tool, DrawingTool.marker);
  });

  testWidgets('clear asks first and is undoable', (tester) async {
    await pumpDrawing(tester);
    await drawOnCanvas(tester);
    final drawn = await pixels(tester);
    await tester.tap(find.byTooltip('Clear the sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, clear'));
    await tester.pumpAndSettle();
    final cleared = await pixels(tester);
    expect(cleared, isNot(drawn));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(await pixels(tester), drawn);
  });

  testWidgets('two new sheets in a row give two drawings, each saved', (
    tester,
  ) async {
    final router = await pumpDrawing(tester);
    final first = requestOf(tester);
    await drawOnCanvas(tester);
    final firstId = stateOf(tester).drawingId;

    await tester.tap(find.byTooltip('New sheet'));
    await settle(tester, () => onlyScreenIsNot(tester, first));
    await settle(tester, () => drawings.records.containsKey(firstId));
    final second = requestOf(tester);
    expect(second.newId, isNotNull);
    expect(stateOf(tester).isEmpty, isTrue);
    expect(router.state.uri.queryParameters['new'], second.newId);
    await drawOnCanvas(tester);
    final secondId = stateOf(tester).drawingId;
    expect(secondId, isNot(firstId));

    await tester.tap(find.byTooltip('New sheet'));
    await settle(tester, () => onlyScreenIsNot(tester, second));
    await settle(tester, () => drawings.records.containsKey(secondId));
    expect(drawings.records.keys.toSet(), {firstId, secondId});
    expect(stateOf(tester).isEmpty, isTrue);
    expect(find.byType(DrawingScreen), findsOneWidget);
  });

  testWidgets('an invalid ?work= opens one new sheet with its id in the URL', (
    tester,
  ) async {
    final router = await pumpDrawing(tester, route: '/draw?work=../x');
    final request = requestOf(tester);
    expect(request.newId, isNotNull);
    expect(router.state.uri.queryParameters['new'], request.newId);
    await tester.pumpAndSettle();
    expect(requestOf(tester), request);
  });

  testWidgets('access that arrives after the paywall closed selects the '
      'tool', (tester) async {
    final access = StreamController<bool>();
    addTearDown(access.close);
    await pumpDrawing(tester, fullAccess: () => access.stream);
    access.add(false);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Watercolor: full version only'));
    await tester.pumpAndSettle();
    await answerGate(tester, '56');
    expect(find.byType(PaywallScreen), findsOneWidget);
    // Bought, but the store has not told the app yet when the paywall goes.
    await tester.tap(find.byTooltip('Back').last);
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsNothing);
    expect(stateOf(tester).tool, DrawingTool.pencil);

    await tester.pump(const Duration(milliseconds: 500));
    access.add(true);
    await tester.pumpAndSettle();
    expect(stateOf(tester).tool, DrawingTool.watercolor);
  });

  for (final (how, leave) in [
    (
      'the back button',
      (WidgetTester tester) => tester.tap(find.byTooltip('Back')),
    ),
    ('system back', (WidgetTester tester) => tester.binding.handlePopRoute()),
  ]) {
    testWidgets('leaving with $how queues the save at once', (tester) async {
      await pumpDrawing(tester);
      await drawOnCanvas(tester);
      final id = stateOf(tester).drawingId;
      expect(drawings.hasPendingSave(id), isFalse);

      await leave(tester);
      await tester.pump();
      expect(
        drawings.hasPendingSave(id),
        isTrue,
        reason: 'queued before the screen is gone',
      );
      Uint8List? raster;
      unawaited(drawings.rasterOf(id).then((bytes) => raster = bytes));
      await settle(tester, () => raster != null);
      await tester.pumpAndSettle();
      expect(find.byType(DrawingScreen), findsNothing);
      expect(drawings.saves.map((r) => r.id), [id]);
    });
  }

  testWidgets('back leaves the drawing screen', (tester) async {
    await pumpDrawing(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawingScreen), findsNothing);
  });
}

/// Pumps, letting real image work (decode, readback, PNG) run between
/// frames, until [done].
Future<void> settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300; i++) {
    if (done()) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('the drawing screen did not settle');
}
