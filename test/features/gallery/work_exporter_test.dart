import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/coloring/coloring_controller.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/gallery/data/gallery_backend.dart';
import 'package:coloring/features/gallery/data/share_backend.dart';
import 'package:coloring/features/gallery/data/work_exporter.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_manifest.dart';
import '../coloring/fakes.dart';
import '../coloring/model/fixtures.dart';
import 'fakes.dart';

const free = 'farm_piglet_picnic';
const locked = 'farm_goat_swing';

Work workOf(String pictureId) => Work(
  id: '$pictureId-1',
  pictureId: pictureId,
  mode: ColoringMode.free,
  colors: Uint32List(6)..[1] = red,
  modified: DateTime.utc(2026, 11, 18),
);

class ThrowingLoader extends FakePictureLoader {
  @override
  Future<LoadedPicture> load(entry, {onProgress}) async =>
      throw StateError('offline');
}

class ThrowingShare implements ShareBackend {
  @override
  Future<void> sharePng(File file) async => throw StateError('no sheet');
}

void main() {
  late Directory temp;
  late FakeGalleryBackend gallery;
  late FakeShareBackend share;
  late FakePictureLoader loader;
  // Listeners currently on fullAccessProvider.
  var accessListeners = 0;

  setUp(() {
    accessListeners = 0;
    temp = Directory.systemTemp.createTempSync('exporter');
    gallery = FakeGalleryBackend();
    share = FakeShareBackend();
    loader = FakePictureLoader();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  WorkExporter exporter({
    bool fullAccess = false,
    PictureLoader? pictureLoader,
    ShareBackend? shareBackend,
    Object? manifestError,
  }) {
    final container = ProviderContainer(
      overrides: [
        manifestProvider.overrideWith(
          (ref) async =>
              manifestError == null ? testManifest : throw manifestError,
        ),
        fullAccessProvider.overrideWith((ref) {
          ref.onAddListener(() => accessListeners++);
          ref.onRemoveListener(() => accessListeners--);
          return Stream.value(fullAccess);
        }),
        pictureLoaderProvider.overrideWithValue(pictureLoader ?? loader),
        galleryBackendProvider.overrideWithValue(gallery),
        shareBackendProvider.overrideWithValue(shareBackend ?? share),
        shareDirectoryProvider.overrideWithValue(
          () async => Directory('${temp.path}/share'),
        ),
        coloringClockProvider.overrideWithValue(
          () => DateTime(2026, 11, 18, 9, 5, 7),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container.read(workExporterProvider);
  }

  Future<(int, int)> pngSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final size = (image.width, image.height);
    image.dispose();
    return size;
  }

  void expectAllDisposed() {
    expect(loader.pictures, isNotEmpty);
    for (final p in loader.pictures) {
      expect(p.regionsImage.debugDisposed, isTrue);
      expect(p.linesImage.debugDisposed, isTrue);
    }
  }

  testWidgets('saves a PNG of the picture size under the album name', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final outcome = await exporter().saveToGallery(workOf(free));
      expect(outcome, ExportOutcome.saved);
      expect(gallery.album, 'Animosaic Colors');
      expect(gallery.savedNames, ['animosaic_colors_${free}_20261118_090507']);
      expect(await pngSize(gallery.savedBytes.single), (
        fixtureWidth,
        fixtureHeight,
      ));
      expectAllDisposed();
    });
  });

  testWidgets('denied and failed results propagate', (tester) async {
    await tester.runAsync(() async {
      gallery.result = GallerySaveResult.denied;
      expect(
        await exporter().saveToGallery(workOf(free)),
        ExportOutcome.denied,
      );
      gallery.result = GallerySaveResult.failed;
      expect(
        await exporter().saveToGallery(workOf(free)),
        ExportOutcome.failed,
      );
      expectAllDisposed();
    });
  });

  testWidgets('a picture missing from the manifest is unavailable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final outcome = await exporter().saveToGallery(workOf('nope'));
      expect(outcome, ExportOutcome.unavailable);
      expect(loader.loadedIds, isEmpty);
      expect(gallery.savedBytes, isEmpty);
    });
  });

  testWidgets('a locked picture is unavailable and never loaded', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final e = exporter();
      expect(await e.saveToGallery(workOf(locked)), ExportOutcome.unavailable);
      expect(await e.share(workOf(locked)), ExportOutcome.unavailable);
      expect(loader.loadedIds, isEmpty);
      expect(gallery.savedBytes, isEmpty);
      expect(share.shared, isEmpty);
    });
  });

  testWidgets('full access exports a paid picture', (tester) async {
    await tester.runAsync(() async {
      final outcome = await exporter(fullAccess: true)
          .saveToGallery(workOf(locked));
      expect(outcome, ExportOutcome.saved);
      expectAllDisposed();
    });
  });

  testWidgets('a load failure is unavailable', (tester) async {
    await tester.runAsync(() async {
      final outcome = await exporter(pictureLoader: ThrowingLoader())
          .saveToGallery(workOf(free));
      expect(outcome, ExportOutcome.unavailable);
      expect(gallery.savedBytes, isEmpty);
    });
  });

  testWidgets('share passes the work file on, then deletes it', (tester) async {
    await tester.runAsync(() async {
      final work = workOf(free);
      final e = exporter();
      expect(await e.share(work), ExportOutcome.shared);
      expect(await e.share(work), ExportOutcome.shared);
      final file = share.shared.last;
      expect(file.path, '${temp.path}/share/${work.id}.png');
      expect(await pngSize(share.sharedBytes.last), (
        fixtureWidth,
        fixtureHeight,
      ));
      expect(Directory('${temp.path}/share').listSync(), isEmpty);
      expectAllDisposed();
    });
  });

  testWidgets('a share backend error is failed and leaves no file', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final outcome = await exporter(shareBackend: ThrowingShare())
          .share(workOf(free));
      expect(outcome, ExportOutcome.failed);
      expect(Directory('${temp.path}/share').listSync(), isEmpty);
      expectAllDisposed();
    });
  });

  testWidgets('clearShareDirectory removes leftover shared files', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final leftover = File('${temp.path}/share/old-1.png')
        ..createSync(recursive: true);
      final e = exporter();
      await e.clearShareDirectory();
      expect(leftover.existsSync(), isFalse);
      // Sharing still works after the folder is gone.
      expect(await e.share(workOf(free)), ExportOutcome.shared);
      expect(share.sharedBytes, hasLength(1));
    });
  });

  testWidgets('exports do not leave listeners on the access provider', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final e = exporter();
      for (var i = 0; i < 3; i++) {
        expect(await e.saveToGallery(workOf(free)), ExportOutcome.saved);
        expect(
          await e.saveToGallery(workOf(locked)),
          ExportOutcome.unavailable,
        );
        expect(
          await e.saveToGallery(workOf('nope')),
          ExportOutcome.unavailable,
        );
      }
      expect(accessListeners, 0);
    });
  });

  testWidgets('a manifest failure throws and leaves no listener', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final e = exporter(manifestError: StateError('offline'));
      for (var i = 0; i < 3; i++) {
        await expectLater(e.saveToGallery(workOf(free)), throwsStateError);
      }
      expect(accessListeners, 0);
      expect(loader.loadedIds, isEmpty);
    });
  });
}
