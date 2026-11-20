import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coloring/features/drawing/data/drawing_preview_service.dart';
import 'package:coloring/features/drawing/data/drawing_repository.dart';
import 'package:coloring/features/drawing/data/drawings_provider.dart';
import 'package:coloring/features/drawing/model/drawing_record.dart';
import 'package:coloring/features/gallery/data/work_preview_service.dart'
    show previewHeight, previewWidth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

DrawingRecord make(String id, int millis) => DrawingRecord(
  id: id,
  created: at(0),
  modified: at(millis),
  width: 400,
  height: 300,
  raster: DrawingRecord.rasterName(id, at(millis)),
);

/// A 400 × 300 red image (the raster of a drawing, at a small size).
ui.Image redImage() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 400, 300),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(400, 300);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> pngOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<(int, int, int)> sizeAndRed(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final rgba = await image.toByteData();
  final result = (image.width, image.height, rgba!.getUint8(0));
  image.dispose();
  codec.dispose();
  return result;
}

/// Records preview writes; a write can be held until [release] is called,
/// or made to fail.
class RecordingRepository extends DrawingRepository {
  RecordingRepository(super.directory, {this.hold = false, this.fail = false});

  final bool hold;
  bool fail;
  final calls = <(String, DateTime)>[];
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<void> savePreview(
    String drawingId,
    DateTime sourceModified,
    Uint8List png,
  ) async {
    calls.add((drawingId, sourceModified));
    if (hold) await _gate.future;
    if (fail) throw StateError('disk full');
    await super.savePreview(drawingId, sourceModified, png);
  }
}

/// Polls until [done] holds; fails after about two seconds.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('drawing_previews'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<DrawingSummary>> summaries(
    DrawingRepository repo,
    List<DrawingRecord> records,
  ) async => [
    for (final r in records)
      DrawingSummary(r, preview: await repo.previewOf(r.id)),
  ];

  testWidgets('renderAfterLeave saves a 640×480 preview, disposes the clone', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repo = RecordingRepository(() async => dir);
      final service = DrawingPreviewService(repo);
      final image = redImage();
      addTearDown(image.dispose);
      final clone = image.clone();

      service.renderAfterLeave(
        drawingId: 'drawing-1',
        sourceModified: at(1234),
        imageClone: clone,
      );
      await service.idle;

      expect(repo.calls, [('drawing-1', at(1234))]);
      final preview = (await repo.previewOf('drawing-1'))!;
      expect(preview.file.path, endsWith('drawing-1.p1234.png'));
      expect(await sizeAndRed(preview.file.readAsBytesSync()), (
        previewWidth,
        previewHeight,
        255,
      ));
      expect(clone.debugDisposed, isTrue);
      expect(image.debugDisposed, isFalse);
    });
  });

  testWidgets('a failing render does not throw and disposes the clone', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repo = RecordingRepository(() async => dir, fail: true);
      final service = DrawingPreviewService(repo);
      final image = redImage();
      addTearDown(image.dispose);
      final clone = image.clone();

      service.renderAfterLeave(
        drawingId: 'd',
        sourceModified: at(1),
        imageClone: clone,
      );
      await service.idle;
      expect(clone.debugDisposed, isTrue);
      expect(await repo.previews(), isEmpty);

      // The queue goes on after a failure.
      repo.fail = false;
      service.renderAfterLeave(
        drawingId: 'd',
        sourceModified: at(2),
        imageClone: image.clone(),
      );
      await service.idle;
      expect((await repo.previewOf('d'))!.sourceModified, at(2));
    });
  });

  testWidgets('backfill draws missing and stale previews from the raster', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repo = RecordingRepository(() async => dir);
      final service = DrawingPreviewService(repo);
      final image = redImage();
      addTearDown(image.dispose);
      final raster = await pngOf(image);
      final missing = make('missing', 1000);
      final fresh = make('fresh', 2000);
      final stale = make('stale', 3000);
      final noRaster = make('no-raster', 4000);
      for (final r in [missing, fresh, stale, noRaster]) {
        await repo.save(r, Future.value(raster));
      }
      File('${dir.path}/${noRaster.raster}').deleteSync();
      await repo.savePreview(fresh.id, fresh.modified, Uint8List(1));
      await repo.savePreview(stale.id, at(2500), Uint8List(1));
      repo.calls.clear();

      await service.backfill(
        await summaries(repo, [missing, fresh, stale, noRaster]),
      );

      expect(repo.calls, [
        (missing.id, missing.modified),
        (stale.id, stale.modified),
      ]);
      final preview = (await repo.previewOf(stale.id))!;
      expect(preview.sourceModified, stale.modified);
      expect(await sizeAndRed(preview.file.readAsBytesSync()), (
        previewWidth,
        previewHeight,
        255,
      ));
    });
  });

  testWidgets('backfill skips a drawing whose preview became fresh', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repo = RecordingRepository(() async => dir);
      final service = DrawingPreviewService(repo);
      final record = make('d', 1000);
      await repo.save(record, Future.value(Uint8List.fromList([1])));
      final list = await summaries(repo, [record]);
      await repo.savePreview(record.id, record.modified, Uint8List(1));
      repo.calls.clear();

      await service.backfill(list);

      expect(repo.calls, isEmpty);
    });
  });

  testWidgets('cancelBackfill stops before the next drawing', (tester) async {
    await tester.runAsync(() async {
      final repo = RecordingRepository(() async => dir, hold: true);
      final service = DrawingPreviewService(repo);
      final image = redImage();
      addTearDown(image.dispose);
      final raster = await pngOf(image);
      final records = [for (var i = 1; i <= 3; i++) make('d$i', i * 1000)];
      for (final r in records) {
        await repo.save(r, Future.value(raster));
      }

      final run = service.backfill(await summaries(repo, records));
      await until(() => repo.calls.isNotEmpty);
      service.cancelBackfill();
      repo.release();
      await run;

      expect(repo.calls, [(records.first.id, records.first.modified)]);
    });
  });

  testWidgets('disposing the provider stops backfill', (tester) async {
    await tester.runAsync(() async {
      final repo = RecordingRepository(() async => dir, hold: true);
      final container = ProviderContainer(
        overrides: [drawingRepositoryProvider.overrideWithValue(repo)],
      );
      final service = container.read(drawingPreviewServiceProvider);
      final image = redImage();
      addTearDown(image.dispose);
      final raster = await pngOf(image);
      final records = [make('a', 1000), make('b', 2000)];
      for (final r in records) {
        await repo.save(r, Future.value(raster));
      }

      final run = service.backfill(await summaries(repo, records));
      await until(() => repo.calls.isNotEmpty);
      container.dispose();
      repo.release();
      await run;

      expect(repo.calls, hasLength(1));
    });
  });
}
