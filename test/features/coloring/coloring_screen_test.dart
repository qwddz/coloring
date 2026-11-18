import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:coloring/features/audio/audio_controller.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/coloring/coloring_canvas.dart';
import 'package:coloring/features/coloring/coloring_controller.dart';
import 'package:coloring/features/coloring/coloring_screen.dart';
import 'package:coloring/features/coloring/coloring_state.dart';
import 'package:coloring/features/coloring/completion_overlay.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/feedback.dart';
import 'package:coloring/features/coloring/game/coloring_game.dart';
import 'package:coloring/features/coloring/game/fill_renderer.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/picture_meta.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/content/data/picture_store.dart';
import 'package:coloring/features/palette/palette_panel.dart';
import 'package:coloring/features/progress/data/progress_store.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feedback_test.dart' show FakeAudioBackend, FakeHaptics;

const _pictureId = 'home_fox_cocoa';
const _paidId = 'home_paid';
const _pictureRoot = 'assets/coloring/free/$_pictureId/';

final _manifest = ContentManifest.fromJson({
  'version': 1,
  'categories': [
    {
      'id': 'home',
      'title': {'uk': 'Дім', 'en': 'Home', 'ru': 'Дом'},
      'pictures': [
        {
          'id': _pictureId,
          'title': {'uk': 'Лис', 'en': 'Fox', 'ru': 'Лис'},
          'level': 'simple',
          'free': true,
          'asset': 'coloring/free/$_pictureId/',
        },
        {
          'id': _paidId,
          'title': {'uk': 'Платна', 'en': 'Paid', 'ru': 'Платная'},
          'level': 'simple',
          'free': false,
          'url': 'home/$_paidId.zip',
          'sha256': '${'0' * 63}1',
        },
      ],
    },
  ],
});

/// Hands out clones of the bundled picture, decoded once per test file
/// (decoding needs real async time, the controller runs in fake time).
class _BundledLoader implements PictureLoader {
  _BundledLoader(this.source);

  final LoadedPicture source;

  @override
  Future<LoadedPicture> load(
    PictureEntry entry, {
    void Function(double progress)? onProgress,
  }) async => LoadedPicture(
    regionsImage: source.regionsImage.clone(),
    linesImage: source.linesImage.clone(),
    map: source.map,
    meta: source.meta,
  );
}

/// Real work files, with every write counted.
class _CountingRepository extends WorkRepository {
  _CountingRepository(super.directory);

  int saves = 0;

  @override
  Future<void> save(Work work) {
    saves++;
    return super.save(work);
  }
}

void main() {
  LoadedPicture? decoded;
  late Directory worksDir;
  late Directory progressDir;
  late SharedPreferences prefs;
  late FakeAudioBackend audio;
  late FakeHaptics haptics;
  late _CountingRepository repository;

  setUp(() async {
    worksDir = Directory.systemTemp.createTempSync('coloring_screen_test');
    progressDir = Directory.systemTemp.createTempSync('coloring_progress');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    audio = FakeAudioBackend();
    haptics = FakeHaptics();
  });

  tearDown(() {
    worksDir.deleteSync(recursive: true);
    progressDir.deleteSync(recursive: true);
  });
  tearDownAll(() => decoded?.dispose());

  PictureMeta meta() => decoded!.meta;

  /// Real IO started in fake time completes only while real time runs.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String reason = '',
  }) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(condition(), isTrue, reason: reason);
  }

  /// The single work file of the picture, or null.
  Map<String, Object?>? workFile() {
    final files = worksDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    if (files.isEmpty) return null;
    expect(files, hasLength(1));
    try {
      return jsonDecode(files.single.readAsStringSync())
          as Map<String, Object?>;
    } on FormatException {
      return null;
    }
  }

  int? savedColorOf(int regionId) =>
      (workFile()?['colors'] as List?)?[regionId] as int?;

  late GoRouter router;

  Future<void> pumpApp(
    WidgetTester tester, {
    String location = '/coloring/$_pictureId',
    Size size = const Size(1280, 800),
    Key? key,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    decoded ??= await tester.runAsync(
      () async =>
          PictureLoader.decode(BundledPictureFiles(rootBundle, _pictureRoot)),
    );
    repository = _CountingRepository(() async => worksDir);
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/coloring/:id',
          builder: (_, state) =>
              ColoringScreen(pictureId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/paywall',
          builder: (_, state) =>
              Text('paywall ${state.uri.queryParameters['from']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        key: key,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          manifestProvider.overrideWith((ref) async => _manifest),
          fullAccessProvider.overrideWith((ref) => Stream.value(false)),
          pictureLoaderProvider.overrideWithValue(_BundledLoader(decoded!)),
          workRepositoryProvider.overrideWithValue(repository),
          progressDirectoryProvider.overrideWithValue(() async => progressDir),
          audioBackendProvider.overrideWithValue(audio),
          hapticsBackendProvider.overrideWithValue(haptics),
          fillRendererProvider.overrideWith(
            (ref) async =>
                (meta, regions) => FlatFillRenderer(meta),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      ),
    );
    router.push(location);
    await pumpUntil(
      tester,
      () =>
          find.byType(ColoringCanvas).evaluate().isNotEmpty ||
          find.textContaining('paywall').evaluate().isNotEmpty,
      reason: 'the screen opens',
    );
    // Game load and first frames.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  ColoringGame game(WidgetTester tester) =>
      tester.widget<ColoringCanvas>(find.byType(ColoringCanvas)).game;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ColoringScreen)));

  ColoringController controller(WidgetTester tester) =>
      container(tester).read(coloringControllerProvider(_pictureId).notifier);

  ColoringState state(WidgetTester tester) =>
      container(tester)
          .read(coloringControllerProvider(_pictureId))
          .requireValue;

  /// Global position of image point ([x], [y]).
  Offset screenOf(WidgetTester tester, double x, double y) {
    final viewport = game(tester).viewport!;
    final p = viewport.imageToScreen(Point(x, y));
    return tester.getTopLeft(find.byType(ColoringCanvas)) + Offset(p.x, p.y);
  }

  Offset labelOf(WidgetTester tester, RegionInfo r) =>
      screenOf(tester, r.labelX, r.labelY);

  /// Big regions away from the back button, largest first.
  List<RegionInfo> bigRegions(WidgetTester tester) {
    final regions =
        meta().regions.where((r) => r.id != meta().backgroundId).where((r) {
          final p = labelOf(tester, r);
          return p.dx > 80 || p.dy > 80;
        }).toList()..sort((a, b) => b.labelRadius.compareTo(a.labelRadius));
    return regions;
  }

  /// The game ticks every frame, so the screen never settles; dialogs get
  /// half a second instead.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> tapRegion(WidgetTester tester, RegionInfo r) async {
    await tester.tapAt(labelOf(tester, r));
    await tester.pump();
  }

  testWidgets('opens with the canvas, toolbar and palette', (tester) async {
    await pumpApp(tester);
    expect(find.byType(ColoringCanvas), findsOneWidget);
    expect(find.byType(PalettePanel), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(state(tester).mode, ColoringMode.free);
    expect(game(tester).meta.regionCount, meta().regionCount);
  });

  testWidgets('fits a 640×360 phone without overflow', (tester) async {
    await pumpApp(tester, size: const Size(640, 360));
    expect(tester.takeException(), isNull);
    final canvas = tester.getSize(find.byType(ColoringCanvas));
    expect(canvas.width / canvas.height, closeTo(4 / 3, 0.01));
    expect(tester.getSize(find.byType(PalettePanel)).width, greaterThan(190));
  });

  testWidgets('a tap on a label point fills the region and saves it', (
    tester,
  ) async {
    await pumpApp(tester);
    final region = bigRegions(tester).first;
    final color = state(tester).selectedColor;
    await tapRegion(tester, region);
    expect(game(tester).fill.colorOf(region.id), color);
    await pumpUntil(
      tester,
      () => savedColorOf(region.id) == color,
      reason: 'the work file has the color',
    );
    expect(audio.effects, contains(Sfx.fill));
  });

  testWidgets('numbers mode: a wrong color is rejected', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('By numbers'));
    await tester.pump();
    expect(state(tester).mode, ColoringMode.numbers);
    expect(find.bySemanticsLabel('Color 1'), findsOneWidget);
    final selected = state(tester).selectedPaletteIndex;
    final wrong = bigRegions(tester)
        .firstWhere((r) => r.paletteIndex != selected);
    await tapRegion(tester, wrong);
    expect(game(tester).fill.colorOf(wrong.id), 0);
    expect(state(tester).rejectSeq, 1);
    expect(state(tester).filledFraction, 0);
    expect(audio.effects, contains(Sfx.wrong));
    expect(haptics.calls, contains('selection'));
  });

  testWidgets('magic brush: one drag fills both regions, one write', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Magic brush'));
    await tester.pump();
    expect(state(tester).mode, ColoringMode.magic);
    await pumpUntil(tester, () => workFile()?['mode'] == 'magic');
    final writes = repository.saves;
    final regions = bigRegions(tester);
    final a = regions[0];
    final b = regions[1];
    final gesture = await tester.startGesture(labelOf(tester, a));
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      final t = i / 10;
      await gesture.moveTo(
        Offset.lerp(labelOf(tester, a), labelOf(tester, b), t)!,
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(game(tester).fill.colorOf(a.id), meta().correctColorOf(a.id));
    expect(game(tester).fill.colorOf(b.id), meta().correctColorOf(b.id));
    expect(repository.saves, writes + 1);
    await pumpUntil(
      tester,
      () =>
          savedColorOf(a.id) == meta().correctColorOf(a.id) &&
          savedColorOf(b.id) == meta().correctColorOf(b.id),
    );
  });

  testWidgets('undo restores, clear with confirm empties', (tester) async {
    await pumpApp(tester);
    final regions = bigRegions(tester);
    await tapRegion(tester, regions[0]);
    await tapRegion(tester, regions[1]);
    expect(game(tester).fill.colorOf(regions[1].id), isNot(0));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(game(tester).fill.colorOf(regions[1].id), 0);
    expect(game(tester).fill.colorOf(regions[0].id), isNot(0));

    await tester.tap(find.byTooltip('Start over'));
    await pumpFrames(tester);
    await tester.tap(find.text('Yes, clear'));
    await pumpFrames(tester);
    expect(game(tester).fill.colorOf(regions[0].id), 0);
    expect(state(tester).filledFraction, 0);
    await pumpUntil(tester, () => savedColorOf(regions[0].id) == 0);
  });

  testWidgets('completing the picture shows the overlay once', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Magic brush'));
    await tester.pump();
    final c = controller(tester)..beginStroke();
    for (final r in meta().regions) {
      c.strokeTo(r.labelX, r.labelY, tolerance: 0);
    }
    c.endStroke();
    await tester.pump();
    expect(state(tester).completed, isTrue);
    expect(find.byType(CompletionOverlay), findsOneWidget);
    expect(audio.effects, contains(Sfx.win));
    await tester.tap(find.text('Keep coloring'));
    await tester.pump();
    expect(find.byType(CompletionOverlay), findsNothing);

    // Reopening a completed work shows no overlay.
    await pumpUntil(tester, () => workFile()?['completed'] == true);
    await pumpApp(tester, key: UniqueKey());
    expect(state(tester).completed, isTrue);
    expect(find.byType(CompletionOverlay), findsNothing);
  });

  testWidgets('a paid picture without access opens the paywall instead', (
    tester,
  ) async {
    await pumpApp(tester, location: '/coloring/$_paidId');
    await tester.pumpAndSettle();
    expect(find.text('paywall $_paidId'), findsOneWidget);
    expect(find.byType(ColoringScreen), findsNothing);
    // Replaced, not stacked: back leaves the paywall to the caller.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a new app run restores the colors and mode', (tester) async {
    await pumpApp(tester);
    final region = bigRegions(tester).first;
    final color = state(tester).selectedColor;
    await tapRegion(tester, region);
    await tester.tap(find.byTooltip('By numbers'));
    await tester.pump();
    await pumpUntil(
      tester,
      () =>
          savedColorOf(region.id) == color && workFile()?['mode'] == 'numbers',
    );

    await pumpApp(tester, key: UniqueKey());
    expect(state(tester).mode, ColoringMode.numbers);
    expect(game(tester).fill.colorOf(region.id), color);
    expect(find.byType(CompletionOverlay), findsNothing);
  });

  testWidgets('leaving during a fill wave is safe', (tester) async {
    await pumpApp(tester);
    await tapRegion(tester, bigRegions(tester).first);
    await tester.pump(const Duration(milliseconds: 16));
    router.pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('home'), findsOneWidget);
    expect(find.byType(ColoringScreen), findsNothing);
  });
}
