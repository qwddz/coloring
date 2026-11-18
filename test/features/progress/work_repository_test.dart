import 'dart:io';

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
}
