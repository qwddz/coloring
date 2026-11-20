import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/features/drawing/data/drawing_repository.dart';
import 'package:coloring/features/drawing/model/drawing_record.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

DrawingRecord make(String id, int millis, {int created = 0}) => DrawingRecord(
  id: id,
  created: at(created),
  modified: at(millis),
  width: 2048,
  height: 1536,
  raster: DrawingRecord.rasterName(id, at(millis)),
);

Future<Uint8List> png(int marker) async => Uint8List.fromList([marker, 1, 2]);

void main() {
  late Directory dir;
  late DrawingRepository repo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('drawings_test');
    repo = DrawingRepository(() async => dir);
  });
  tearDown(() {
    repo.dispose();
    dir.deleteSync(recursive: true);
  });

  File file(String name) => File('${dir.path}/$name');

  Set<String> names() => {
    for (final e in dir.listSync()) e.uri.pathSegments.last,
  };

  test('save writes the raster and the JSON, then reads them back', () async {
    final record = make('drawing-1', 1000);
    expect(await repo.save(record, png(7)), isTrue);

    expect(names(), {'drawing-1.json', 'drawing-1.r1000.png'});
    final loaded = await repo.byId('drawing-1');
    expect(loaded!.toJson(), record.toJson());
    expect(await repo.rasterOf('drawing-1'), [7, 1, 2]);
    expect((await repo.latest())!.id, 'drawing-1');
  });

  test(
    'byId, latest and rasterOf right after save see the new raster',
    () async {
      await repo.save(make('d', 1000), png(1));
      final encoding = Completer<Uint8List>();

      // The save is queued synchronously; nothing is awaited before reading.
      final saved = repo.save(make('d', 2000), encoding.future);
      expect(repo.hasPendingSave('d'), isTrue);
      final byId = repo.byId('d');
      final latest = repo.latest();
      final raster = repo.rasterOf('d');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      encoding.complete(Uint8List.fromList([2, 1, 2]));

      expect((await byId)!.modified, at(2000));
      expect((await latest)!.modified, at(2000));
      expect(await raster, [2, 1, 2]);
      expect(await saved, isTrue);
      expect(repo.hasPendingSave('d'), isFalse);
    },
  );

  test('save in flight, reopen: the strokes are kept', () async {
    // First visit: a drawing saved once.
    await repo.save(make('d', 1000), png(1));
    // Leaving: the flush queues a save whose PNG is still encoding.
    final encoding = Completer<Uint8List>();
    unawaited(repo.save(make('d', 2000), encoding.future));
    // Reopening at once, through a fresh read of the latest drawing.
    final reopened = repo.latest().then(
      (record) async => (record, await repo.rasterOf(record!.id)),
    );
    encoding.complete(Uint8List.fromList([9, 9, 9]));

    final (record, raster) = await reopened;
    expect(record!.raster, 'd.r2000.png');
    expect(raster, [9, 9, 9]);
  });

  test('saves of one drawing run in order and the last one wins', () async {
    final slow = Completer<Uint8List>();
    final first = repo.save(make('d', 1000), slow.future);
    final second = repo.save(make('d', 2000), png(2));
    final third = repo.save(make('d', 3000), png(3));
    slow.complete(Uint8List.fromList([1]));

    expect(await Future.wait([first, second, third]), [true, true, true]);
    expect((await repo.byId('d'))!.modified, at(3000));
    expect(await repo.rasterOf('d'), [3, 1, 2]);
    expect(names(), {'d.json', 'd.r3000.png'});
  });

  test('a failing png leaves the previous JSON and raster intact', () async {
    await repo.save(make('d', 1000), png(1));
    final held = Completer<Uint8List>();
    final blocker = repo.save(make('d', 1500), held.future);
    // Fails before the queue reaches it; must not be an unhandled error.
    final failed = repo.save(
      make('d', 2000),
      Future<Uint8List>.error(StateError('encode failed')),
    );
    held.completeError(StateError('encode failed too'));

    expect(await blocker, isFalse);
    expect(await failed, isFalse);
    expect((await repo.byId('d'))!.modified, at(1000));
    expect(await repo.rasterOf('d'), [1, 1, 2]);
    expect(names(), {'d.json', 'd.r1000.png'});
  });

  test('a failing raster write keeps the previous JSON and raster', () async {
    await repo.save(make('d', 1000), png(1));
    // A directory where the temp raster goes makes the write fail.
    Directory('${dir.path}/d.r2000.png.tmp').createSync();

    expect(await repo.save(make('d', 2000), png(2)), isFalse);
    expect((await repo.byId('d'))!.modified, at(1000));
    expect(await repo.rasterOf('d'), [1, 1, 2]);
  });

  test(
    'save removes stale rasters and temp files of that drawing only',
    () async {
      for (final name in [
        'd.r1.png',
        'd.r5.png',
        'd.json.tmp',
        'd.r7.png.tmp',
        'd.p3.png.tmp',
        'd.p3.png',
        'd-1.r1.png',
        'd-1.json',
        'other.json.tmp',
      ]) {
        file(name).writeAsBytesSync([0]);
      }

      await repo.save(make('d', 2000), png(2));

      expect(names(), {
        'd.json',
        'd.r2000.png',
        // A preview write has its own queue; save never touches previews.
        'd.p3.png.tmp',
        'd.p3.png',
        'd-1.r1.png',
        'd-1.json',
        'other.json.tmp',
      });
    },
  );

  test('list removes orphan rasters and leftover temp files', () async {
    await repo.save(make('kept', 1000), png(1));
    for (final name in [
      'gone.r1.png',
      'gone.r1.png.tmp',
      'gone.json.tmp',
      'kept.p1.png.tmp',
      'notes.txt',
    ]) {
      file(name).writeAsBytesSync([0]);
    }

    final list = await repo.list();

    expect(list.map((r) => r.id), ['kept']);
    expect(names(), {'kept.json', 'kept.r1000.png', 'notes.txt'});
  });

  test('a pending new drawing keeps its raster through list', () async {
    final heldOld = Completer<Uint8List>();
    final heldNew = Completer<Uint8List>();
    final old = repo.save(make('old', 1000), heldOld.future);
    final listing = repo.list();
    // A new drawing is saved while list waits; its raster is on disk before
    // its JSON.
    final fresh = repo.save(make('new', 5000), heldNew.future);
    file('new.r5000.png').writeAsBytesSync([5]);
    file('new.r5000.png.tmp').writeAsBytesSync([5]);
    file('orphan.r1.png').writeAsBytesSync([0]);
    heldOld.complete(Uint8List.fromList([1]));

    final list = await listing;
    expect(list.map((r) => r.id), ['old']);
    expect(names(), containsAll(['new.r5000.png', 'new.r5000.png.tmp']));
    expect(names(), isNot(contains('orphan.r1.png')));

    heldNew.complete(Uint8List.fromList([6]));
    expect(await Future.wait([old, fresh]), [true, true]);
    expect(await repo.rasterOf('new'), [6]);
    expect(names(), {'old.json', 'old.r1000.png', 'new.json', 'new.r5000.png'});
  });

  test('a save that starts after the listing keeps its raster', () async {
    // The folder listing is not atomic: a save that runs while it does can
    // show up with its raster but without its JSON.
    late DrawingRepository racing;
    final listing = _HookedDirectory(
      dir,
      onFirstList: () async {
        expect(await racing.save(make('fresh', 3000), png(9)), isTrue);
        return {'fresh.json'};
      },
    );
    racing = DrawingRepository(() async => listing);
    addTearDown(racing.dispose);

    expect(await racing.list(), isEmpty, reason: 'listed without its JSON');
    expect(names(), {'fresh.json', 'fresh.r3000.png'});
    expect(await racing.rasterOf('fresh'), [9, 1, 2]);
  });

  test('an unreadable JSON is skipped and never touched', () async {
    file('bad.json').writeAsStringSync('{not json');
    file('bad.r1.png').writeAsBytesSync([1]);
    file('wrong.json').writeAsStringSync('{"v": 1, "id": "wrong"}');
    await repo.save(make('good', 1000), png(1));

    expect((await repo.list()).map((r) => r.id), ['good']);
    expect(await repo.byId('bad'), isNull);
    expect(await repo.rasterOf('bad'), isNull);
    expect((await repo.latest())!.id, 'good');

    expect(await repo.save(make('bad', 2000), png(2)), isFalse);
    expect(file('bad.json').readAsStringSync(), '{not json');
    expect(file('bad.r1.png').existsSync(), isTrue);
    expect(file('bad.r2000.png').existsSync(), isFalse);
    expect(file('wrong.json').readAsStringSync(), '{"v": 1, "id": "wrong"}');
  });

  test('a JSON holding another id is not that drawing', () async {
    await repo.save(make('a', 1000), png(1));
    file('b.json').writeAsStringSync(file('a.json').readAsStringSync());

    expect(await repo.byId('b'), isNull);
    expect((await repo.list()).map((r) => r.id), ['a']);
  });

  test('latest picks the newest, ties by id; null when empty', () async {
    expect(await repo.latest(), isNull);
    await repo.save(make('a', 2000), png(1));
    await repo.save(make('c', 1000), png(1));
    await repo.save(make('b', 2000), png(1));
    expect((await repo.latest())!.id, 'b');
  });

  test('a missing raster reads as null', () async {
    await repo.save(make('d', 1000), png(1));
    file('d.r1000.png').deleteSync();
    expect(await repo.byId('d'), isNotNull);
    expect(await repo.rasterOf('d'), isNull);
  });

  test('ids that are not plain file names read as null', () async {
    expect(await repo.byId('../x'), isNull);
    expect(await repo.rasterOf(''), isNull);
    expect(await repo.previewOf('a/b'), isNull);
  });

  test('save rejects a record whose raster name does not match', () {
    final record = make('d', 1000);
    final wrong = DrawingRecord(
      id: 'd',
      created: record.created,
      modified: record.modified,
      width: 2048,
      height: 1536,
      raster: 'd.r999.png',
    );
    expect(() => repo.save(wrong, png(1)), throwsArgumentError);
    expect(repo.hasPendingSave('d'), isFalse);
  });

  test('changes report saved drawings and previews after the write', () async {
    final changes = <DrawingChange>[];
    final sub = repo.changes.listen(changes.add);
    addTearDown(sub.cancel);

    await repo.save(make('d', 1000), png(1));
    await repo.savePreview('d', at(1000), Uint8List.fromList([1]));
    await repo.save(
      make('d', 2000),
      Future<Uint8List>.error(StateError('no png')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(changes, hasLength(2));
    expect((changes[0] as DrawingSaved).record.modified, at(1000));
    final preview = changes[1] as DrawingPreviewSaved;
    expect(preview.drawingId, 'd');
    expect(preview.preview.sourceModified, at(1000));
    expect(preview.preview.file.path, endsWith('d.p1000.png'));
  });

  test('previews: versioned names, newest wins, older ones removed', () async {
    await repo.savePreview('d', at(1000), Uint8List.fromList([1]));
    final a = repo.savePreview('d', at(2000), Uint8List.fromList([2]));
    final b = repo.savePreview('e', at(500), Uint8List.fromList([3]));
    await Future.wait([a, b]);

    expect(names(), {'d.p2000.png', 'e.p500.png'});
    final previews = await repo.previews();
    expect(previews.keys, unorderedEquals(['d', 'e']));
    expect(previews['d']!.sourceModified, at(2000));
    expect((await repo.previewOf('d'))!.file.readAsBytesSync(), [2]);
    expect(await repo.previewOf('none'), isNull);
    await expectLater(
      repo.savePreview('../x', at(1), Uint8List(1)),
      throwsArgumentError,
    );
  });

  test('a missing folder lists nothing', () async {
    final missing = DrawingRepository(
      () async => Directory('${dir.path}/missing'),
    );
    addTearDown(missing.dispose);
    expect(await missing.list(), isEmpty);
    expect(await missing.latest(), isNull);
    expect(await missing.previews(), isEmpty);
  });
}

/// [real] whose first [list] runs [onFirstList] and then lists the folder
/// without the names it returned.
class _HookedDirectory implements Directory {
  _HookedDirectory(this.real, {required this.onFirstList});

  final Directory real;
  Future<Set<String>> Function()? onFirstList;

  @override
  String get path => real.path;

  @override
  Future<bool> exists() => real.exists();

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    final hook = onFirstList;
    onFirstList = null;
    final hidden = hook == null ? const <String>{} : await hook();
    await for (final entity in real.list()) {
      if (!hidden.contains(entity.uri.pathSegments.last)) yield entity;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
