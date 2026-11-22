import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/gallery/data/work_preview_service.dart';
import 'package:coloring/features/gallery/data/works_provider.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../coloring/fakes.dart';
import '../coloring/model/fixtures.dart';

DateTime at(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

Work make(String picture, int millis) => Work(
  id: '$picture-$millis',
  pictureId: picture,
  mode: ColoringMode.free,
  colors: Uint32List(6)..[1] = red,
  modified: at(millis),
);

/// Records preview writes; a write can be held until [release] is called,
/// or made to fail.
class RecordingRepository extends InMemoryWorkRepository {
  RecordingRepository({this.hold = false, this.fail = false});

  final bool hold;
  bool fail;
  final calls = <(String, DateTime)>[];
  final _gate = Completer<void>();
  int _active = 0;
  int maxActive = 0;

  void release() => _gate.complete();

  /// Saves a preview without recording, holding or failing.
  Future<void> savePreviewNow(
    String workId,
    DateTime sourceModified,
    Uint8List png,
  ) => super.savePreview(workId, sourceModified, png);

  @override
  Future<void> savePreview(
    String workId,
    DateTime sourceModified,
    Uint8List png,
  ) async {
    calls.add((workId, sourceModified));
    _active++;
    if (_active > maxActive) maxActive = _active;
    try {
      if (hold) await _gate.future;
      if (fail) throw StateError('disk full');
      await super.savePreview(workId, sourceModified, png);
    } finally {
      _active--;
    }
  }
}

WorkPreviewService serviceFor(
  WorkRepository repository, {
  PictureLoader? loader,
  Future<bool> Function(PictureEntry entry)? isLocal,
}) => WorkPreviewService(
  repository: repository,
  loader: loader ?? FakePictureLoader(),
  manifest: () async => fixtureManifest,
  isLocal: isLocal,
);

ui.Image linesImage() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(fixtureWidth, fixtureHeight);
  } finally {
    picture.dispose();
  }
}

/// Polls until [done] holds; fails after about two seconds.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

Future<List<WorkSummary>> summaries(
  WorkRepository repo,
  List<Work> works,
) async => [
  for (final w in works) WorkSummary(w, preview: await repo.previewOf(w.id)),
];

void main() {
  group('renderAfterLeave', () {
    testWidgets('saves a versioned PNG preview and disposes the clone', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final repo = RecordingRepository();
        final service = serviceFor(repo);
        final changes = <WorkChange>[];
        final sub = repo.changes.listen(changes.add);
        addTearDown(sub.cancel);
        final lines = linesImage();
        addTearDown(lines.dispose);
        final clone = lines.clone();

        service.renderAfterLeave(
          workId: 'fix_free-1',
          sourceModified: at(1234),
          map: fixtureMap(),
          colors: Uint32List(6)..[1] = red,
          linesClone: clone,
        );
        await service.idle;

        expect(repo.calls, [('fix_free-1', at(1234))]);
        final png = repo.previewBytes['fix_free-1']!;
        expect(png.sublist(1, 4), 'PNG'.codeUnits);
        final codec = await ui.instantiateImageCodec(png);
        final image = (await codec.getNextFrame()).image;
        expect((image.width, image.height), (previewWidth, previewHeight));
        image.dispose();
        codec.dispose();
        final saved = changes.single as PreviewSaved;
        expect(saved.workId, 'fix_free-1');
        expect(saved.preview.sourceModified, at(1234));
        expect(saved.preview.file.path, endsWith('fix_free-1.p1234.png'));
        expect(clone.debugDisposed, isTrue);
        expect(lines.debugDisposed, isFalse);
      });
    });

    testWidgets('runs renders one at a time, in order', (tester) async {
      await tester.runAsync(() async {
        final repo = RecordingRepository(hold: true);
        final service = serviceFor(repo);
        final lines = linesImage();
        addTearDown(lines.dispose);
        final clones = [lines.clone(), lines.clone()];
        for (final (i, clone) in clones.indexed) {
          service.renderAfterLeave(
            workId: 'w$i',
            sourceModified: at(i),
            map: fixtureMap(),
            colors: Uint32List(6),
            linesClone: clone,
          );
        }

        await until(() => repo.calls.isNotEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(repo.calls, [('w0', at(0))]);
        expect(clones[1].debugDisposed, isFalse);

        repo.release();
        await service.idle;
        expect(repo.calls, [('w0', at(0)), ('w1', at(1))]);
        expect(repo.maxActive, 1);
        expect(clones.every((c) => c.debugDisposed), isTrue);
      });
    });

    testWidgets('a failing render does not throw and disposes the clone', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final repo = RecordingRepository(fail: true);
        final service = serviceFor(repo);
        final lines = linesImage();
        addTearDown(lines.dispose);
        final clone = lines.clone();

        service.renderAfterLeave(
          workId: 'w',
          sourceModified: at(1),
          map: fixtureMap(),
          colors: Uint32List(6),
          linesClone: clone,
        );
        await service.idle;

        expect(repo.calls, hasLength(1));
        expect(repo.previewBytes, isEmpty);
        expect(clone.debugDisposed, isTrue);

        // The queue goes on after a failure.
        repo.fail = false;
        service.renderAfterLeave(
          workId: 'w',
          sourceModified: at(2),
          map: fixtureMap(),
          colors: Uint32List(6),
          linesClone: lines.clone(),
        );
        await service.idle;
        expect(repo.previewBytes.keys, ['w']);
      });
    });
  });

  group('backfill', () {
    testWidgets('renders only missing or stale previews of bundled pictures', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final repo = RecordingRepository();
        final loader = FakePictureLoader();
        final service = serviceFor(repo, loader: loader);
        final missing = make(freePictureId, 1000);
        final fresh = make(freePictureId, 2000);
        final stale = make(freePictureId, 3000);
        final cdn = make(paidPictureId, 4000);
        final gone = make('gone', 5000);
        for (final w in [missing, fresh, stale, cdn, gone]) {
          await repo.save(w);
        }
        await repo.savePreview(fresh.id, fresh.modified, Uint8List(1));
        await repo.savePreview(stale.id, at(2500), Uint8List(1));
        repo.calls.clear();

        await service.backfill(
          await summaries(repo, [missing, fresh, stale, cdn, gone]),
        );

        expect(repo.calls, [
          (missing.id, missing.modified),
          (stale.id, stale.modified),
        ]);
        expect(loader.loadedIds, [freePictureId, freePictureId]);
        expect(
          loader.pictures.every(
            (p) => p.linesImage.debugDisposed && p.regionsImage.debugDisposed,
          ),
          isTrue,
        );
      });
    });

    testWidgets('renders a CDN picture already on the device', (tester) async {
      await tester.runAsync(() async {
        final repo = RecordingRepository();
        final loader = FakePictureLoader();
        final local = <String>{freePictureId, paidPictureId};
        final service = serviceFor(
          repo,
          loader: loader,
          isLocal: (entry) async => local.contains(entry.id),
        );
        final downloaded = make(paidPictureId, 1000);
        await repo.save(downloaded);

        await service.backfill(await summaries(repo, [downloaded]));
        expect(repo.calls, [(downloaded.id, downloaded.modified)]);

        // Not downloaded: skipped, nothing is loaded.
        local.remove(paidPictureId);
        final later = make(paidPictureId, 2000);
        await repo.save(later);
        repo.calls.clear();
        loader.loadedIds.clear();
        await service.backfill(await summaries(repo, [later]));
        expect(repo.calls, isEmpty);
        expect(loader.loadedIds, isEmpty);
      });
    });

    testWidgets('skips a work whose preview became fresh meanwhile', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final repo = RecordingRepository();
        final loader = FakePictureLoader();
        final service = serviceFor(repo, loader: loader);
        final work = make(freePictureId, 1000);
        await repo.save(work);
        final list = await summaries(repo, [work]);
        await repo.savePreview(work.id, work.modified, Uint8List(1));
        repo.calls.clear();

        await service.backfill(list);

        expect(repo.calls, isEmpty);
        expect(loader.loadedIds, isEmpty);
      });
    });

    testWidgets('lists the previews once per run, never per work', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final repo = RecordingRepository();
        final service = serviceFor(repo);
        final works = [
          for (var i = 1; i <= 5; i++) make(freePictureId, i * 1000),
        ];
        for (final w in works) {
          await repo.save(w);
        }
        final list = await summaries(repo, works);
        repo.previewOfCalls = 0;

        await service.backfill(list);

        expect(repo.calls, hasLength(5));
        expect(repo.previewsCalls, 1);
        expect(repo.previewOfCalls, 0);
      });
    });

    testWidgets('skips a work whose preview was saved during the run', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final repo = RecordingRepository(hold: true);
        final loader = FakePictureLoader();
        final service = serviceFor(repo, loader: loader);
        final first = make(freePictureId, 1000);
        final second = make(freePictureId, 2000);
        for (final w in [first, second]) {
          await repo.save(w);
        }

        final run = service.backfill(await summaries(repo, [first, second]));
        await until(() => repo.calls.isNotEmpty);
        await repo.savePreviewNow(second.id, second.modified, Uint8List(1));
        repo.release();
        await run;

        expect(repo.calls, [(first.id, first.modified)]);
        expect(loader.loadedIds, [freePictureId]);
      });
    });

    testWidgets('cancelBackfill stops before the next work', (tester) async {
      await tester.runAsync(() async {
        final repo = RecordingRepository(hold: true);
        final loader = FakePictureLoader();
        final service = serviceFor(repo, loader: loader);
        final works = [
          for (var i = 1; i <= 3; i++) make(freePictureId, i * 1000),
        ];
        for (final w in works) {
          await repo.save(w);
        }

        final run = service.backfill(await summaries(repo, works));
        await until(() => repo.calls.isNotEmpty);
        service.cancelBackfill();
        repo.release();
        await run;

        expect(repo.calls, [(works.first.id, works.first.modified)]);
        expect(loader.loadedIds, [freePictureId]);
        expect(loader.pictures.single.linesImage.debugDisposed, isTrue);
      });
    });

    testWidgets('disposing the provider stops backfill', (tester) async {
      await tester.runAsync(() async {
        final repo = RecordingRepository(hold: true);
        final loader = FakePictureLoader();
        final container = ProviderContainer(
          overrides: [
            workRepositoryProvider.overrideWithValue(repo),
            pictureLoaderProvider.overrideWithValue(loader),
            manifestProvider.overrideWith((ref) async => fixtureManifest),
          ],
        );
        final service = container.read(workPreviewServiceProvider);
        final works = [make(freePictureId, 1000), make(freePictureId, 2000)];
        for (final w in works) {
          await repo.save(w);
        }

        final run = service.backfill(await summaries(repo, works));
        await until(() => repo.calls.isNotEmpty);
        container.dispose();
        repo.release();
        await run;

        expect(repo.calls, hasLength(1));
        expect(loader.loadedIds, hasLength(1));
      });
    });
  });
}
