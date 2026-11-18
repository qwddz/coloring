import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/app/theme.dart';
import 'package:coloring/app/widgets/book_button.dart';
import 'package:coloring/features/catalog/catalog_grid.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/coloring/coloring_controller.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/gallery/data/gallery_backend.dart';
import 'package:coloring/features/gallery/data/share_backend.dart';
import 'package:coloring/features/gallery/data/work_exporter.dart';
import 'package:coloring/features/gallery/data/work_preview_service.dart';
import 'package:coloring/features/gallery/gallery_routes.dart';
import 'package:coloring/features/gallery/my_works_screen.dart';
import 'package:coloring/features/gallery/work_actions_dialog.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/features/subscription/domain/parental_challenge.dart';
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

void main() {
  late InMemoryWorkRepository works;
  late FakeGalleryBackend gallery;
  late FakeShareBackend share;
  late Directory temp;
  late GoRouter router;

  setUp(() {
    works = InMemoryWorkRepository();
    gallery = FakeGalleryBackend();
    share = FakeShareBackend();
    temp = Directory.systemTemp.createTempSync('work_actions');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Work workOf(String pictureId) {
    final modified = DateTime.utc(2026, 11, 18, 10);
    return Work(
      id: '$pictureId-${modified.millisecondsSinceEpoch}',
      pictureId: pictureId,
      mode: ColoringMode.free,
      colors: Uint32List(6)..[1] = red,
      modified: modified,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<ContentManifest>? manifest,
  }) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.625;
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
          manifestProvider.overrideWith(
            (ref) => manifest ?? Future.value(testManifest),
          ),
          fullAccessProvider.overrideWith((ref) => Stream.value(false)),
          workRepositoryProvider.overrideWithValue(works),
          workPreviewServiceProvider.overrideWithValue(FakePreviewService()),
          pictureLoaderProvider.overrideWithValue(FakePictureLoader()),
          galleryBackendProvider.overrideWithValue(gallery),
          shareBackendProvider.overrideWithValue(share),
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
          locale: const Locale('en'),
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
    expect(find.byType(WorkActionsDialog), findsOneWidget);
  }

  Future<void> answerGate(WidgetTester tester, String answer) async {
    expect(find.text('For grown-ups'), findsOneWidget);
    await tester.enterText(find.byType(TextField), answer);
    await tester.tap(find.text('OK'));
    await tester.pump();
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

  testWidgets('the dialog shows the title, a large preview and closes', (
    tester,
  ) async {
    final work = workOf(piglet);
    await works.save(work);
    await works.savePreview(work.id, work.modified, Uint8List(1));
    await pumpScreen(tester);
    await openActions(tester);
    final dialog = find.byType(WorkActionsDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Piglet')),
      findsOneWidget,
    );
    final image = tester.widget<Image>(
      find.descendant(of: dialog, matching: find.byType(Image)),
    );
    final resized = image.image as ResizeImage;
    expect((resized.imageProvider as FileImage).file.path, contains(work.id));
    expect(
      resized.width,
      lessThanOrEqualTo(WorkActionsDialog.previewWidth * 2.625),
    );
    for (final label in [
      'Continue',
      'New coloring',
      'Save to gallery',
      'Share',
    ]) {
      final button = find.widgetWithText(BookButton, label);
      expect(tester.widget<BookButton>(button).onPressed, isNotNull);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkActionsDialog), findsNothing);
    expect(router.state.matchedLocation, myWorksRoute);
  });

  testWidgets('a picture gone from the catalog disables every action', (
    tester,
  ) async {
    await works.save(workOf('gone_picture'));
    await pumpScreen(tester);
    await openActions(tester);
    expect(find.text('This picture is not available'), findsOneWidget);
    for (final label in [
      'Continue',
      'New coloring',
      'Save to gallery',
      'Share',
    ]) {
      final button = find.widgetWithText(BookButton, label);
      expect(tester.widget<BookButton>(button).onPressed, isNull);
    }
  });

  testWidgets('while the catalog loads, actions wait without the note', (
    tester,
  ) async {
    final manifest = Completer<ContentManifest>();
    await works.save(workOf(piglet));
    await pumpScreen(tester, manifest: manifest.future);
    await tester.tap(find.byType(PictureCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(WorkActionsDialog), findsOneWidget);
    expect(find.text('This picture is not available'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(WorkActionsDialog),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    for (final label in [
      'Continue',
      'New coloring',
      'Save to gallery',
      'Share',
    ]) {
      final button = find.widgetWithText(BookButton, label);
      expect(tester.widget<BookButton>(button).onPressed, isNull);
    }

    manifest.complete(testManifest);
    await tester.pumpAndSettle();
    expect(find.text('This picture is not available'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final button = find.widgetWithText(BookButton, 'Continue');
    expect(tester.widget<BookButton>(button).onPressed, isNotNull);
  });

  testWidgets('cancelling the mode picker stays on «My works»', (tester) async {
    await works.save(workOf(piglet));
    await pumpScreen(tester);
    await openActions(tester);
    await tester.tap(find.widgetWithText(BookButton, 'New coloring'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BookButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, myWorksRoute);
    expect(find.textContaining('stub'), findsNothing);
  });

  testWidgets('Share asks the parental gate first', (tester) async {
    final work = workOf(piglet);
    await works.save(work);
    await pumpScreen(tester);

    await openActions(tester);
    await tester.tap(find.widgetWithText(BookButton, 'Share'));
    await tester.pumpAndSettle();
    await answerGate(tester, '11');
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(share.shared, isEmpty);
    expect(gallery.savedNames, isEmpty);

    // A wrong answer locks the gate for a while.
    await tester.pump(const Duration(seconds: 11));
    await openActions(tester);
    await tester.tap(find.widgetWithText(BookButton, 'Share'));
    await tester.pumpAndSettle();
    await answerGate(tester, '12');
    await pumpUntil(
      tester,
      () =>
          share.sharedBytes.isNotEmpty &&
          find.text('Preparing the picture…').evaluate().isEmpty,
    );
    await tester.pump();
    expect(share.shared, hasLength(1));
    final file = share.shared.single;
    expect(file.path, '${temp.path}/share/${work.id}.png');
    expect(share.sharedBytes.single.sublist(1, 4), 'PNG'.codeUnits);
    expect(await tester.runAsync(file.exists), isFalse);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Preparing the picture…'), findsNothing);
  });
}
