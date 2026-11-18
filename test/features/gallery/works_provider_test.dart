import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/gallery/data/works_provider.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../coloring/fakes.dart';

Work make(String picture, int millis, {int fill = 0, bool completed = false}) {
  final colors = Uint32List(4);
  colors[1] = fill;
  return Work(
    id: '$picture-$millis',
    pictureId: picture,
    mode: ColoringMode.free,
    colors: colors,
    modified: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
    completed: completed,
  );
}

/// [work] with a later modified time and [fill] in region 1.
Work touched(Work work, int millis, int fill) {
  final colors = Uint32List.fromList(work.colors);
  colors[1] = fill;
  return Work(
    id: work.id,
    pictureId: work.pictureId,
    mode: work.mode,
    colors: colors,
    modified: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
  );
}

DateTime at(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

final png = Uint8List.fromList([1, 2, 3]);

ProviderContainer containerFor(WorkRepository repo) {
  final c = ProviderContainer(
    overrides: [workRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

/// Keeps [worksProvider] alive and returns its loaded value.
Future<List<WorkSummary>> listen(ProviderContainer c) async {
  c.listen(worksProvider, (_, _) {});
  return c.read(worksProvider.future);
}

List<String> ids(List<WorkSummary> works) => [for (final s in works) s.work.id];

/// Reads the works when [list] is called, then holds the result until
/// [releaseList], like a slow folder listing that already read the files.
class GatedListRepository extends InMemoryWorkRepository {
  final listStarted = Completer<void>();
  final _gate = Completer<void>();

  void releaseList() => _gate.complete();

  @override
  Future<List<Work>> list() async {
    final works = await super.list();
    listStarted.complete();
    await _gate.future;
    return works;
  }
}

/// The works folder, counting how often it is listed.
class CountingDirectory implements Directory {
  CountingDirectory(this._inner);

  final Directory _inner;
  int lists = 0;

  @override
  String get path => _inner.path;

  @override
  Future<bool> exists() => _inner.exists();

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    lists++;
    return _inner.list(recursive: recursive, followLinks: followLinks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('with the in-memory repository', () {
    late InMemoryWorkRepository repo;
    late ProviderContainer c;

    setUp(() {
      repo = InMemoryWorkRepository();
      c = containerFor(repo);
    });

    test('sorted newest first with previews and staleness', () async {
      await repo.save(make('fox', 1000));
      await repo.save(make('cat', 3000, completed: true));
      await repo.save(make('owl', 2000));
      await repo.savePreview('fox-1000', at(1000), png);
      await repo.savePreview('owl-2000', at(1500), png);

      final works = await listen(c);
      expect(ids(works), ['cat-3000', 'owl-2000', 'fox-1000']);
      expect(works[0].preview, isNull);
      expect(works[0].previewStale, isTrue);
      expect(works[0].work.completed, isTrue);
      expect(works[1].preview!.sourceModified, at(1500));
      expect(works[1].previewStale, isTrue);
      expect(works[2].preview!.file.path, endsWith('fox-1000.p1000.png'));
      expect(works[2].previewStale, isFalse);
    });

    test('staleness compares milliseconds, not microseconds', () {
      final work = make('fox', 1000);
      final precise = Work(
        id: work.id,
        pictureId: work.pictureId,
        mode: work.mode,
        colors: work.colors,
        modified: at(1000).add(const Duration(microseconds: 250)),
      );
      final preview = (file: File('x.png'), sourceModified: at(1000));
      expect(WorkSummary(precise, preview: preview).previewStale, isFalse);
    });

    test('10 saves while listened update in place, no re-listing', () async {
      final fox = make('fox', 1000);
      await repo.save(fox);
      await repo.save(make('cat', 1500));
      expect(ids(await listen(c)), ['cat-1500', 'fox-1000']);
      expect(repo.listCalls, 1);

      for (var i = 1; i <= 10; i++) {
        await repo.save(touched(fox, 2000 + i, i));
      }
      await pumpEventQueue();

      expect(repo.listCalls, lessThanOrEqualTo(1));
      final works = c.read(worksProvider).requireValue;
      expect(ids(works), ['fox-1000', 'cat-1500']);
      expect(works.first.work.colors[1], 10);
      expect(works.first.work.modified, at(2010));
    });

    test('a new work is inserted in order', () async {
      await repo.save(make('fox', 1000));
      await listen(c);
      await repo.save(make('cat', 5000));
      await repo.save(make('owl', 500));
      await pumpEventQueue();
      expect(ids(c.read(worksProvider).requireValue), [
        'cat-5000',
        'fox-1000',
        'owl-500',
      ]);
      expect(repo.listCalls, 1);
    });

    test('a saved work keeps its preview until a new one arrives', () async {
      final fox = make('fox', 1000);
      await repo.save(fox);
      await repo.savePreview(fox.id, fox.modified, png);
      await listen(c);
      await repo.save(touched(fox, 2000, 7));
      await pumpEventQueue();
      final summary = c.read(worksProvider).requireValue.single;
      expect(summary.preview!.sourceModified, at(1000));
      expect(summary.previewStale, isTrue);
    });

    test('PreviewSaved updates only that entry', () async {
      await repo.save(make('fox', 1000));
      await repo.save(make('cat', 2000));
      await repo.savePreview('cat-2000', at(1000), png);
      final before = await listen(c);
      final cat = before.firstWhere((s) => s.work.id == 'cat-2000');

      await repo.savePreview('fox-1000', at(1000), png);
      await pumpEventQueue();

      final after = c.read(worksProvider).requireValue;
      final fox = after.firstWhere((s) => s.work.id == 'fox-1000');
      expect(fox.preview!.sourceModified, at(1000));
      expect(fox.previewStale, isFalse);
      expect(after.firstWhere((s) => s.work.id == 'cat-2000'), same(cat));
      expect(repo.listCalls, 1);
    });

    test('previews are read in one call, never per work', () async {
      for (var i = 1; i <= 5; i++) {
        await repo.save(make('fox', i * 1000));
        await repo.savePreview('fox-${i * 1000}', at(i * 1000), png);
      }
      final works = await listen(c);
      expect(works, hasLength(5));
      expect(works.every((s) => !s.previewStale), isTrue);
      expect(repo.previewsCalls, 1);
      expect(repo.previewOfCalls, 0);
    });

    test('a change during the first listing is not lost', () async {
      final gated = GatedListRepository();
      final c = containerFor(gated);
      await gated.save(make('fox', 1000));
      c.listen(worksProvider, (_, _) {});
      await gated.listStarted.future;
      // Saved after the folder was read, before the listing returned.
      await gated.save(make('cat', 2000));
      await pumpEventQueue();
      gated.releaseList();
      await c.read(worksProvider.future);
      await pumpEventQueue();
      expect(ids(c.read(worksProvider).requireValue), ['cat-2000', 'fox-1000']);
    });

    test('disposes when nobody listens', () async {
      await repo.save(make('fox', 1000));
      final sub = c.listen(worksProvider, (_, _) {});
      await c.read(worksProvider.future);
      sub.close();
      await pumpEventQueue();
      expect(c.read(worksProvider.exists), isFalse);

      await repo.save(make('cat', 2000));
      expect(ids(await listen(c)), ['cat-2000', 'fox-1000']);
      expect(repo.listCalls, 2);
    });
  });

  group('with the real repository on a temp dir', () {
    late Directory dir;
    late WorkRepository repo;
    late ProviderContainer c;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('works_provider_test');
      repo = WorkRepository(() async => dir);
      c = containerFor(repo);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('lists, attaches previews and skips a corrupt file', () async {
      await repo.save(make('fox', 1000));
      await repo.save(make('cat', 2000));
      await repo.savePreview('fox-1000', at(1000), png);
      File('${dir.path}/owl-3000.json').writeAsStringSync('{oops');

      final works = await listen(c);
      expect(ids(works), ['cat-2000', 'fox-1000']);
      expect(works[1].previewStale, isFalse);
      expect(works[1].preview!.file.readAsBytesSync(), png);
    });

    test('listing N works scans the folder once for the previews', () async {
      final counting = CountingDirectory(dir);
      final c = containerFor(WorkRepository(() async => counting));
      for (var i = 1; i <= 6; i++) {
        await repo.save(make('fox', i * 1000));
        await repo.savePreview('fox-${i * 1000}', at(i * 1000), png);
      }
      final works = await listen(c);
      expect(works, hasLength(6));
      expect(works.every((s) => !s.previewStale), isTrue);
      // One listing for the works, one for the previews.
      expect(counting.lists, 2);
    });

    test('saves and previews apply in place', () async {
      final fox = make('fox', 1000);
      await repo.save(fox);
      await repo.save(make('cat', 1500));
      await listen(c);

      for (var i = 1; i <= 10; i++) {
        await repo.save(touched(fox, 2000 + i, i));
      }
      await repo.savePreview(fox.id, at(2010), png);
      await pumpEventQueue();

      final works = c.read(worksProvider).requireValue;
      expect(ids(works), ['fox-1000', 'cat-1500']);
      expect(works.first.work.colors[1], 10);
      expect(works.first.previewStale, isFalse);
      expect(works.first.preview!.file.path, endsWith('fox-1000.p2010.png'));
    });
  });
}
