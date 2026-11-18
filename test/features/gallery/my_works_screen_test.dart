import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/app/theme.dart';
import 'package:coloring/app/widgets/book_button.dart';
import 'package:coloring/features/catalog/catalog_grid.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/coloring/coloring_controller.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/gallery/data/gallery_backend.dart';
import 'package:coloring/features/gallery/data/share_backend.dart';
import 'package:coloring/features/gallery/data/work_exporter.dart';
import 'package:coloring/features/gallery/data/work_preview_service.dart';
import 'package:coloring/features/gallery/data/works_provider.dart';
import 'package:coloring/features/gallery/gallery_routes.dart';
import 'package:coloring/features/gallery/my_works_screen.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/test_manifest.dart';
import '../coloring/fakes.dart';
import '../coloring/model/fixtures.dart';
import 'fake_preview_service.dart';
import 'fakes.dart';

const piglet = 'farm_piglet_picnic';
const goat = 'farm_goat_swing';
const dpr = 2.625;

/// A backfill that runs until [done] completes.
class SlowPreviewService extends FakePreviewService {
  final done = Completer<void>();

  @override
  Future<void> backfill(List<WorkSummary> works) async {
    await super.backfill(works);
    await done.future;
  }
}

void main() {
  late InMemoryWorkRepository works;
  late FakePreviewService previews;
  late FakeGalleryBackend gallery;
  late FakeShareBackend share;
  late Directory temp;
  late GoRouter router;

  setUp(() {
    works = InMemoryWorkRepository();
    previews = FakePreviewService();
    gallery = FakeGalleryBackend();
    share = FakeShareBackend();
    temp = Directory.systemTemp.createTempSync('my_works');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Work workOf(
    String pictureId,
    int minute, {
    bool completed = false,
    ColoringMode mode = ColoringMode.free,
  }) {
    final modified = DateTime.utc(2026, 11, 18, 10, minute);
    return Work(
      id: '$pictureId-${modified.millisecondsSinceEpoch}',
      pictureId: pictureId,
      mode: mode,
      colors: Uint32List(6)..[1] = red,
      modified: modified,
      completed: completed,
      completedAt: completed ? modified : null,
    );
  }

  Future<void> pumpScreen(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: myWorksRoute,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: myWorksRoute, builder: (_, _) => const MyWorksScreen()),
        GoRoute(
          path: '/coloring/:id',
          builder: (_, state) => Scaffold(body: Text('stub ${state.uri}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          manifestProvider.overrideWith((ref) async => testManifest),
          fullAccessProvider.overrideWith((ref) => Stream.value(false)),
          workRepositoryProvider.overrideWithValue(works),
          workPreviewServiceProvider.overrideWithValue(previews),
          pictureLoaderProvider.overrideWithValue(FakePictureLoader()),
          galleryBackendProvider.overrideWithValue(gallery),
          shareBackendProvider.overrideWithValue(share),
          shareDirectoryProvider.overrideWithValue(
            () async => Directory('${temp.path}/share'),
          ),
          coloringClockProvider.overrideWithValue(
            () => DateTime(2026, 11, 18, 9, 5, 7),
          ),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  /// Exports render real images, which only finish outside fake time.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  List<String?> captions(WidgetTester tester) => [
    for (final card in find.byType(PictureCard).evaluate())
      tester
          .widget<Text>(
            find.descendant(
              of: find.byWidget(card.widget),
              matching: find.byType(Text),
            ),
          )
          .data,
  ];

  Future<void> openActions(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  testWidgets('no works: a message and a way to the pictures', (tester) async {
    await pumpScreen(tester);
    expect(find.text('My works'), findsOneWidget);
    expect(find.text('Your colorings will appear here'), findsOneWidget);
    await tester.tap(find.widgetWithText(BookButton, 'Pick a picture'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('opening the screen clears leftover shared files', (
    tester,
  ) async {
    final leftover = File('${temp.path}/share/old-1.png')
      ..createSync(recursive: true);
    await pumpScreen(tester);
    await pumpUntil(tester, () => !leftover.existsSync());
    expect(Directory('${temp.path}/share').existsSync(), isFalse);
  });

  testWidgets('cards are newest first, a finished work has a star', (
    tester,
  ) async {
    await works.save(workOf(goat, 1));
    await works.save(workOf(piglet, 3, completed: true));
    await works.save(workOf(piglet, 2));
    await pumpScreen(tester);
    expect(captions(tester), ['Piglet', 'Piglet', 'Goat']);
    final cards = find.byType(PictureCard);
    Finder starIn(int i) => find.descendant(
      of: cards.at(i),
      matching: find.byIcon(Icons.star_rounded),
    );
    expect(starIn(0), findsOneWidget);
    expect(starIn(1), findsNothing);
    expect(starIn(2), findsNothing);
    expect(tester.widget<Icon>(starIn(0)).semanticLabel, 'Finished');
  });

  testWidgets('a tap shows the four actions; Continue opens that work', (
    tester,
  ) async {
    final older = workOf(piglet, 1);
    await works.save(older);
    await works.save(workOf(goat, 2));
    await pumpScreen(tester);
    await openActions(tester, 'Piglet');
    for (final label in ['Continue', 'New coloring', 'Save to gallery']) {
      expect(find.widgetWithText(BookButton, label), findsOneWidget);
    }
    expect(find.widgetWithText(BookButton, 'Share'), findsOneWidget);
    await tester.tap(find.widgetWithText(BookButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('stub /coloring/$piglet?work=${older.id}'),
      findsOneWidget,
    );
  });

  testWidgets('New coloring asks for a mode and opens a new work', (
    tester,
  ) async {
    await works.save(workOf(piglet, 1));
    await pumpScreen(tester);
    await openActions(tester, 'Piglet');
    await tester.tap(find.widgetWithText(BookButton, 'New coloring'));
    await tester.pumpAndSettle();
    expect(find.text('How do you want to color?'), findsOneWidget);
    await tester.tap(find.text('By numbers'));
    await tester.pumpAndSettle();
    expect(find.text('stub /coloring/$piglet?mode=numbers'), findsOneWidget);
  });

  testWidgets('a picture gone from the catalog cannot be continued', (
    tester,
  ) async {
    await works.save(workOf('gone_picture', 1));
    await pumpScreen(tester);
    expect(captions(tester), ['']);
    await tester.tap(find.byType(PictureCard));
    await tester.pumpAndSettle();
    expect(find.text('This picture is not available'), findsOneWidget);
    for (final label in ['Continue', 'New coloring']) {
      final button = tester.widget<BookButton>(
        find.widgetWithText(BookButton, label),
      );
      expect(button.onPressed, isNull, reason: label);
    }
  });

  for (final (result, message) in [
    (GallerySaveResult.saved, 'Saved to the gallery'),
    (GallerySaveResult.denied, 'Allow access to save pictures'),
    (GallerySaveResult.failed, 'Could not prepare the picture. Try again'),
  ]) {
    testWidgets('Save to gallery: ${result.name} → "$message"', (tester) async {
      gallery.result = result;
      await works.save(workOf(piglet, 1));
      await pumpScreen(tester);
      await openActions(tester, 'Piglet');
      await tester.tap(find.widgetWithText(BookButton, 'Save to gallery'));
      await tester.pump();
      await tester.pump();
      // No parental gate for saving (S2-D4); a progress overlay instead.
      expect(find.text('For grown-ups'), findsNothing);
      expect(find.text('Preparing the picture…'), findsOneWidget);
      await pumpUntil(tester, () => find.text(message).evaluate().isNotEmpty);
      expect(gallery.savedNames, hasLength(1));
      await tester.pump();
      expect(find.text('Preparing the picture…'), findsNothing);
    });
  }

  testWidgets('saving a locked picture says it is not available', (
    tester,
  ) async {
    await works.save(workOf(goat, 1));
    await pumpScreen(tester);
    await openActions(tester, 'Goat');
    await tester.tap(find.widgetWithText(BookButton, 'Save to gallery'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.text('This picture is not available').evaluate().isNotEmpty,
    );
    expect(gallery.savedNames, isEmpty);
  });

  testWidgets('a new preview swaps the card to the new file', (tester) async {
    final work = workOf(piglet, 1);
    await works.save(work);
    await works.savePreview(
      work.id,
      DateTime.utc(2026, 11, 18, 9),
      Uint8List(1),
    );
    await pumpScreen(tester);
    String path() {
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(PictureCard),
          matching: find.byType(Image),
        ),
      );
      return ((image.image as ResizeImage).imageProvider as FileImage)
          .file
          .path;
    }

    final before = path();
    expect(
      before,
      endsWith(
        '${work.id}.p${DateTime.utc(2026, 11, 18, 9).millisecondsSinceEpoch}.png',
      ),
    );
    await works.savePreview(work.id, work.modified, Uint8List(1));
    await tester.pump();
    await tester.pump();
    expect(
      path(),
      endsWith('${work.id}.p${work.modified.millisecondsSinceEpoch}.png'),
    );
    expect(path(), isNot(before));
  });

  testWidgets('grid previews are decoded no wider than the card', (
    tester,
  ) async {
    for (var i = 0; i < 4; i++) {
      final work = workOf(piglet, i);
      await works.save(work);
      await works.savePreview(work.id, work.modified, Uint8List(1));
    }
    await pumpScreen(tester);
    final cards = find.byType(PictureCard);
    expect(cards, findsNWidgets(4));
    for (var i = 0; i < 4; i++) {
      final image = tester.widget<Image>(
        find.descendant(of: cards.at(i), matching: find.byType(Image)),
      );
      expect(image.image, isA<ResizeImage>());
      final width = (image.image as ResizeImage).width!;
      final cardWidth = tester.getSize(cards.at(i)).width;
      expect(width, lessThanOrEqualTo(cardWidth * dpr));
    }
  });

  testWidgets('stale previews are backfilled; leaving cancels it', (
    tester,
  ) async {
    final fresh = workOf(piglet, 1);
    final stale = workOf(goat, 2);
    await works.save(fresh);
    await works.save(stale);
    await works.savePreview(fresh.id, fresh.modified, Uint8List(1));
    await pumpScreen(tester);
    expect(previews.backfills, hasLength(1));
    expect(
      previews.backfills.single.map((s) => s.work.id),
      containsAll([fresh.id, stale.id]),
    );
    expect(previews.cancelBackfillCalls, 0);
    router.go('/');
    await tester.pumpAndSettle();
    expect(previews.cancelBackfillCalls, 1);
  });

  testWidgets('a missing preview shows a spinner while backfill runs', (
    tester,
  ) async {
    final slow = previews = SlowPreviewService();
    await works.save(workOf(piglet, 1));
    // The spinner animates forever, so pump instead of settling.
    await pumpScreen(tester, settle: false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final spinner = find.descendant(
      of: find.byType(PictureCard),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinner, findsOneWidget);
    slow.done.complete();
    await tester.pump();
    await tester.pump();
    expect(spinner, findsNothing);
  });
}
