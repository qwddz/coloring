import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/app/theme.dart';
import 'package:coloring/app/widgets/book_button.dart';
import 'package:coloring/features/catalog/catalog_grid.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/coloring/coloring_controller.dart';
import 'package:coloring/features/drawing/model/drawing_record.dart';
import 'package:coloring/features/gallery/data/gallery_backend.dart';
import 'package:coloring/features/gallery/data/share_backend.dart';
import 'package:coloring/features/gallery/data/work_exporter.dart';
import 'package:coloring/features/gallery/data/work_preview_service.dart';
import 'package:coloring/features/gallery/drawing_actions_dialog.dart';
import 'package:coloring/features/gallery/gallery_routes.dart';
import 'package:coloring/features/gallery/my_works_screen.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/features/subscription/domain/parental_challenge.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/coloring_overrides.dart';
import '../../support/test_manifest.dart';
import '../coloring/fakes.dart';
import '../drawing/fakes.dart';
import 'fake_preview_service.dart';
import 'fakes.dart';

const dpr = 2.625;

void main() {
  late InMemoryDrawingRepository drawings;
  late FakeGalleryBackend gallery;
  late FakeShareBackend share;
  late Directory temp;
  late GoRouter router;

  final modified = DateTime.utc(2026, 11, 18, 12);
  final drawing = DrawingRecord(
    id: 'd-1',
    created: modified,
    modified: modified,
    width: 4,
    height: 3,
    raster: DrawingRecord.rasterName('d-1', modified),
  );
  final raster = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

  setUp(() {
    drawings = InMemoryDrawingRepository();
    gallery = FakeGalleryBackend();
    share = FakeShareBackend();
    temp = Directory.systemTemp.createTempSync('drawing_actions');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> pumpScreen(WidgetTester tester, {Locale? locale}) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: myWorksRoute,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: myWorksRoute, builder: (_, _) => const MyWorksScreen()),
        GoRoute(
          path: '/draw',
          builder: (_, state) => Scaffold(body: Text('stub ${state.uri}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...drawingScreenOverrides(drawings: drawings),
          workRepositoryProvider.overrideWithValue(InMemoryWorkRepository()),
          workPreviewServiceProvider.overrideWithValue(FakePreviewService()),
          galleryBackendProvider.overrideWithValue(gallery),
          shareBackendProvider.overrideWithValue(share),
          manifestProvider.overrideWith((ref) async => testManifest),
          fullAccessProvider.overrideWith((ref) => Stream.value(false)),
          shareDirectoryProvider.overrideWithValue(
            () async => Directory('${temp.path}/share'),
          ),
          coloringClockProvider.overrideWithValue(
            () => DateTime(2026, 11, 18, 9, 5, 7),
          ),
          parentalChallengeProvider.overrideWithValue(
            () => const ParentalChallenge(3, 4),
          ),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          locale: locale ?? const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openActions(WidgetTester tester) async {
    await tester.tap(find.byType(PictureCard));
    await tester.pumpAndSettle();
    expect(find.byType(DrawingActionsDialog), findsOneWidget);
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  testWidgets('the dialog shows the dated title, a preview and closes', (
    tester,
  ) async {
    await drawings.save(drawing, Future.value(raster));
    await drawings.savePreview(drawing.id, drawing.modified, Uint8List(1));
    await pumpScreen(tester);
    await openActions(tester);
    final dialog = find.byType(DrawingActionsDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Drawing, Nov 18, 2026')),
      findsOneWidget,
    );
    final image = tester.widget<Image>(
      find.descendant(of: dialog, matching: find.byType(Image)),
    );
    final resized = image.image as ResizeImage;
    expect(
      (resized.imageProvider as FileImage).file.path,
      contains(drawing.id),
    );
    expect(
      resized.width,
      lessThanOrEqualTo(DrawingActionsDialog.previewWidth * dpr),
    );
    for (final label in [
      'Continue',
      'New drawing',
      'Save to gallery',
      'Share',
    ]) {
      final button = find.widgetWithText(BookButton, label);
      expect(tester.widget<BookButton>(button).onPressed, isNotNull);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawingActionsDialog), findsNothing);
    expect(router.state.matchedLocation, myWorksRoute);
  });

  testWidgets('the title follows the app language', (tester) async {
    await drawings.save(drawing, Future.value(raster));
    await pumpScreen(tester, locale: const Locale('ru'));
    expect(find.textContaining('Рисунок, 18'), findsOneWidget);
  });

  testWidgets('Save to gallery saves the raster without the gate', (
    tester,
  ) async {
    await drawings.save(drawing, Future.value(raster));
    await pumpScreen(tester);
    await openActions(tester);
    await tester.tap(find.widgetWithText(BookButton, 'Save to gallery'));
    await tester.pump();
    expect(find.text('For grown-ups'), findsNothing);
    await pumpUntil(
      tester,
      () => find.text('Saved to the gallery').evaluate().isNotEmpty,
    );
    expect(gallery.savedNames, ['animosaic_colors_drawing_20261118_090507']);
    expect(gallery.savedBytes.single, raster);
  });

  testWidgets('a missing raster says it is not available', (tester) async {
    await drawings.save(drawing, Future.value(raster));
    drawings.rasters.remove(drawing.id);
    await pumpScreen(tester);
    await openActions(tester);
    await tester.tap(find.widgetWithText(BookButton, 'Save to gallery'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.text('This picture is not available').evaluate().isNotEmpty,
    );
    expect(gallery.savedBytes, isEmpty);
  });

  testWidgets('Share asks the gate, then shares share/<id>.png', (
    tester,
  ) async {
    await drawings.save(drawing, Future.value(raster));
    await pumpScreen(tester);
    await openActions(tester);
    await tester.tap(find.widgetWithText(BookButton, 'Share'));
    await tester.pumpAndSettle();
    expect(find.text('For grown-ups'), findsOneWidget);
    expect(share.shared, isEmpty);
    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('OK'));
    await tester.pump();
    await pumpUntil(
      tester,
      () =>
          share.sharedBytes.isNotEmpty &&
          find.text('Preparing the picture…').evaluate().isEmpty,
    );
    final file = share.shared.single;
    expect(file.path, '${temp.path}/share/${drawing.id}.png');
    expect(share.sharedBytes.single, raster);
    expect(await tester.runAsync(file.exists), isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });
}
