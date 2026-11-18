import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late WorkRepository repo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('works_test');
    repo = WorkRepository(() async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Work make(String picture, int millis, {int regions = 3}) => Work.create(
    pictureId: picture,
    regionCount: regions,
    now: () => DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
  );

  test('save then latestFor round trips', () async {
    final work = make('fox', 1000);
    await repo.save(work);
    final loaded = await repo.latestFor('fox');
    expect(loaded, isNotNull);
    expect(loaded!.id, work.id);
    expect(loaded.colors, work.colors);
    expect(loaded.modified, work.modified);
  });

  test('latestFor picks max modified and ignores other pictures', () async {
    await repo.save(make('fox', 1000));
    await repo.save(make('fox', 3000));
    await repo.save(make('fox', 2000));
    await repo.save(make('fox_cocoa', 9000));
    await repo.save(make('cat', 8000));
    expect((await repo.latestFor('fox'))!.id, 'fox-3000');
    expect((await repo.latestFor('fox_cocoa'))!.id, 'fox_cocoa-9000');
    expect(await repo.latestFor('dog'), isNull);
  });

  test('a file with a prefix-clash name is not matched', () async {
    await repo.save(make('fox_cocoa', 9000));
    expect(await repo.latestFor('fox'), isNull);
  });

  test(
    'corrupt file is skipped, not overwritten; new work gets new id',
    () async {
      final bad = File('${dir.path}/fox-5000.json')..writeAsStringSync('{oops');
      await repo.save(make('fox', 1000));
      expect((await repo.latestFor('fox'))!.id, 'fox-1000');
      expect(bad.readAsStringSync(), '{oops');
      final fresh = make('fox', 6000);
      expect(fresh.id, isNot('fox-5000'));
      await repo.save(fresh);
      expect(bad.readAsStringSync(), '{oops');
      expect((await repo.latestFor('fox'))!.id, 'fox-6000');
    },
  );

  test('rapid saves stay ordered: last state is on disk', () async {
    final base = make('fox', 1000, regions: 12);
    final saves = <Future<void>>[];
    for (var i = 1; i <= 10; i++) {
      base.colors[1] = 0xFF000000 + i;
      saves.add(
        repo.save(
          Work(
            id: base.id,
            pictureId: base.pictureId,
            mode: base.mode,
            colors: Work.fromJson(base.toJson())!.colors,
            modified: base.modified,
          ),
        ),
      );
    }
    await Future.wait(saves);
    final loaded = await repo.latestFor('fox');
    expect(loaded!.colors[1], 0xFF00000A);
  });

  group('byId', () {
    test('hit and miss', () async {
      await repo.save(make('fox', 1000));
      expect((await repo.byId('fox-1000'))!.pictureId, 'fox');
      expect(await repo.byId('fox-2000'), isNull);
      expect(await repo.byId('../fox-1000'), isNull);
    });

    test('ids that are not plain file names are refused', () async {
      File('${dir.path}/.json').writeAsStringSync('{}');
      for (final bad in ['', '.', '..', 'a/b', r'a\b', 'fox 1', 'fox*']) {
        expect(await repo.byId(bad), isNull, reason: bad);
        expect(await repo.previewOf(bad), isNull, reason: bad);
        await expectLater(
          repo.savePreview(bad, DateTime.utc(2026), Uint8List(1)),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('corrupt file → null, left untouched', () async {
      final bad = File('${dir.path}/fox-5000.json')..writeAsStringSync('{oops');
      expect(await repo.byId('fox-5000'), isNull);
      expect(bad.readAsStringSync(), '{oops');
    });

    test('a file holding another id → null', () async {
      final work = make('fox', 1000);
      File('${dir.path}/fox-9000.json')
          .writeAsStringSync(jsonEncode(work.toJson()));
      expect(await repo.byId('fox-9000'), isNull);
    });
  });

  test('worksFor returns only that picture, no prefix clash', () async {
    await repo.save(make('a_b', 1000));
    await repo.save(make('a_b', 2000));
    await repo.save(make('a_b_c', 3000));
    await repo.save(make('a', 4000));
    final ids = (await repo.worksFor('a_b')).map((w) => w.id).toSet();
    expect(ids, {'a_b-1000', 'a_b-2000'});
    expect((await repo.worksFor('a_b_c')).single.id, 'a_b_c-3000');
    expect((await repo.worksFor('a')).single.id, 'a-4000');
    expect(await repo.worksFor('dog'), isEmpty);
  });

  group('previews', () {
    final png1 = Uint8List.fromList([1, 2, 3]);
    final png2 = Uint8List.fromList([4, 5, 6, 7]);
    final t1 = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
    final t2 = DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true);

    List<String> files() =>
        dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

    test('savePreview then previewOf round trips', () async {
      expect(await repo.previewOf('fox-1000'), isNull);
      await repo.savePreview('fox-1000', t1, png1);
      final preview = await repo.previewOf('fox-1000');
      expect(preview!.sourceModified, t1);
      expect(preview.file.path, endsWith('/fox-1000.p1000.png'));
      expect(preview.file.readAsBytesSync(), png1);
      expect(await repo.previewOf('fox-100'), isNull);
    });

    test('a second savePreview removes the older file', () async {
      await repo.savePreview('fox-1000', t1, png1);
      await repo.savePreview('fox-10000', t1, png1);
      await repo.savePreview('fox-1000', t2, png2);
      expect(files(), ['fox-1000.p2000.png', 'fox-10000.p1000.png']);
      final preview = await repo.previewOf('fox-1000');
      expect(preview!.sourceModified, t2);
      expect(preview.file.readAsBytesSync(), png2);
    });

    test('concurrent savePreviews end with the last bytes', () async {
      await Future.wait([
        for (var i = 1; i <= 8; i++)
          repo.savePreview(
            'fox-1000',
            DateTime.fromMillisecondsSinceEpoch(9000 - i, isUtc: true),
            Uint8List.fromList([i]),
          ),
      ]);
      expect(files(), ['fox-1000.p8992.png']);
      final preview = await repo.previewOf('fox-1000');
      expect(preview!.file.readAsBytesSync(), [8]);
    });

    test('previews() maps every work to its newest preview', () async {
      await repo.savePreview('fox-1000', t1, png1);
      await repo.savePreview('fox-10000', t2, png2);
      File('${dir.path}/fox-1000.p500.png').writeAsBytesSync(png1);
      File('${dir.path}/cat-1.p9.png.tmp').writeAsBytesSync(png1);
      File('${dir.path}/notes.png').writeAsBytesSync(png1);
      final previews = await repo.previews();
      expect(previews.keys.toSet(), {'fox-1000', 'fox-10000'});
      expect(previews['fox-1000']!.sourceModified, t1);
      expect(previews['fox-10000']!.sourceModified, t2);
      expect(previews['fox-10000']!.file.readAsBytesSync(), png2);
    });

    test('savePreview also removes stale temp files of that work', () async {
      File('${dir.path}/fox-1000.p5.png.tmp').writeAsBytesSync(png1);
      File('${dir.path}/fox-1000.p7.png.tmp').writeAsBytesSync(png1);
      File('${dir.path}/fox-10000.p5.png.tmp').writeAsBytesSync(png1);
      await repo.savePreview('fox-1000', t1, png1);
      expect(files(), ['fox-1000.p1000.png', 'fox-10000.p5.png.tmp']);
    });

    test('list() ignores previews and temp files', () async {
      await repo.save(make('fox', 1000));
      await repo.savePreview('fox-1000', t1, png1);
      File('${dir.path}/fox-1000.p5.png.tmp').writeAsBytesSync(png1);
      File('${dir.path}/fox-2000.json.tmp').writeAsStringSync('{}');
      final works = await repo.list();
      expect(works.map((w) => w.id), ['fox-1000']);
    });
  });

  test('changes emits WorkSaved and PreviewSaved after the write', () async {
    final events = <WorkChange>[];
    final sub = repo.changes.listen((change) {
      events.add(change);
      if (change is WorkSaved) {
        expect(File('${dir.path}/${change.work.id}.json').existsSync(), isTrue);
      }
      if (change is PreviewSaved) {
        expect(change.preview.file.existsSync(), isTrue);
      }
    });
    addTearDown(sub.cancel);
    final work = make('fox', 1000);
    await repo.save(work);
    await repo.savePreview(work.id, work.modified, Uint8List.fromList([1]));
    await pumpEventQueue();
    expect(events, hasLength(2));
    expect((events[0] as WorkSaved).work.id, work.id);
    final saved = events[1] as PreviewSaved;
    expect(saved.workId, work.id);
    expect(saved.preview.sourceModified, work.modified);
  });
}
