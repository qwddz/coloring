import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/features/drawing/data/drawing_repository.dart';
import 'package:coloring/features/drawing/data/drawings_provider.dart';
import 'package:coloring/features/drawing/model/drawing_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

DrawingRecord make(String id, int millis) => DrawingRecord(
  id: id,
  created: at(0),
  modified: at(millis),
  width: 2048,
  height: 1536,
  raster: DrawingRecord.rasterName(id, at(millis)),
);

Future<Uint8List> png() async => Uint8List.fromList([1]);

void main() {
  late Directory dir;
  late DrawingRepository repo;
  late ProviderContainer container;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('drawings_provider');
    repo = DrawingRepository(() async => dir);
    container = ProviderContainer(
      overrides: [drawingRepositoryProvider.overrideWithValue(repo)],
    );
  });
  tearDown(() {
    container.dispose();
    repo.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<List<DrawingSummary>> read() async {
    final sub = container.listen(drawingsProvider, (_, _) {});
    addTearDown(sub.close);
    return container.read(drawingsProvider.future);
  }

  List<String> ids() => [
    for (final s in container.read(drawingsProvider).value!) s.record.id,
  ];

  /// Lets the change stream deliver and the controller apply it.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('lists drawings newest first with their previews', () async {
    await repo.save(make('a', 1000), png());
    await repo.save(make('b', 3000), png());
    await repo.save(make('c', 2000), png());
    await repo.savePreview('c', at(2000), Uint8List(1));
    await repo.savePreview('b', at(2500), Uint8List(1));

    final list = await read();

    expect(list.map((s) => s.record.id), ['b', 'c', 'a']);
    expect(list.map((s) => s.previewStale), [true, false, true]);
    expect(list[1].preview!.sourceModified, at(2000));
  });

  test('ties are ordered by id, so the order is stable', () async {
    await repo.save(make('a', 1000), png());
    await repo.save(make('b', 1000), png());
    expect((await read()).map((s) => s.record.id), ['b', 'a']);
  });

  test('follows saves and previews without listing again', () async {
    await repo.save(make('a', 1000), png());
    await repo.savePreview('a', at(1000), Uint8List(1));
    await read();

    await repo.save(make('b', 2000), png());
    await settle();
    expect(ids(), ['b', 'a']);

    // A newer save of a keeps its old preview, now stale.
    await repo.save(make('a', 3000), png());
    await settle();
    expect(ids(), ['a', 'b']);
    final a = container.read(drawingsProvider).value!.first;
    expect(a.preview!.sourceModified, at(1000));
    expect(a.previewStale, isTrue);

    await repo.savePreview('a', at(3000), Uint8List(1));
    await settle();
    expect(container.read(drawingsProvider).value!.first.previewStale, false);
  });

  test('a save queued before the listing is part of it', () async {
    final encoding = Completer<Uint8List>();
    unawaited(repo.save(make('a', 1000), encoding.future));
    final listing = read();
    encoding.complete(Uint8List.fromList([1]));

    expect((await listing).map((s) => s.record.id), ['a']);
  });
}
