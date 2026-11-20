import 'dart:async';
import 'dart:typed_data';

import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/drawing/data/drawing_repository.dart';
import 'package:coloring/features/drawing/model/drawing_record.dart';
import 'package:coloring/features/gallery/data/gallery_items_provider.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../coloring/fakes.dart';
import '../drawing/fakes.dart';

Work workAt(String id, DateTime modified) => Work(
  id: id,
  pictureId: 'farm_piglet_picnic',
  mode: ColoringMode.free,
  colors: Uint32List(6),
  modified: modified,
);

DrawingRecord drawingAt(String id, DateTime modified) => DrawingRecord(
  id: id,
  created: modified,
  modified: modified,
  width: 4,
  height: 3,
  raster: DrawingRecord.rasterName(id, modified),
);

/// Drawings whose listing waits for [gate], or fails with [error].
class GatedDrawingRepository extends InMemoryDrawingRepository {
  Completer<void>? gate;
  Object? error;

  @override
  Future<List<DrawingRecord>> list() async {
    await gate?.future;
    if (error case final error?) throw error;
    return super.list();
  }
}

void main() {
  late InMemoryWorkRepository works;
  late GatedDrawingRepository drawings;

  setUp(() {
    works = InMemoryWorkRepository();
    drawings = GatedDrawingRepository();
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        workRepositoryProvider.overrideWithValue(works),
        drawingRepositoryProvider.overrideWithValue(drawings),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Keeps the provider alive and waits until it leaves loading.
  Future<AsyncValue<List<GalleryItem>>> settled(ProviderContainer c) async {
    c.listen(galleryItemsProvider, (_, _) {});
    for (var i = 0; i < 20 && c.read(galleryItemsProvider).isLoading; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c.read(galleryItemsProvider);
  }

  Future<void> saveDrawing(DrawingRecord record) =>
      drawings.save(record, Future.value(Uint8List(1)));

  test('works and drawings merge newest first, ties by id', () async {
    final t = DateTime.utc(2026, 11, 18, 12);
    await works.save(workAt('w-old', t));
    await works.save(workAt('w-new', t.add(const Duration(minutes: 3))));
    await works.save(workAt('a-tie', t.add(const Duration(minutes: 1))));
    await saveDrawing(drawingAt('d-mid', t.add(const Duration(minutes: 2))));
    await saveDrawing(drawingAt('z-tie', t.add(const Duration(minutes: 1))));

    final items = (await settled(container())).requireValue;
    expect(
      [for (final i in items) (i.runtimeType, i.id)],
      [
        (ColoringItem, 'w-new'),
        (DrawingItem, 'd-mid'),
        (DrawingItem, 'z-tie'),
        (ColoringItem, 'a-tie'),
        (ColoringItem, 'w-old'),
      ],
    );
  });

  test('no works and no drawings is an empty list', () async {
    expect((await settled(container())).requireValue, isEmpty);
  });

  test('loading while the drawings load', () async {
    await works.save(workAt('w', DateTime.utc(2026, 11, 18)));
    final gate = drawings.gate = Completer<void>();
    final c = container();
    c.listen(galleryItemsProvider, (_, _) {});
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(c.read(galleryItemsProvider), isA<AsyncLoading<void>>());
    gate.complete();
    final items = (await settled(c)).requireValue;
    expect(items.single, isA<ColoringItem>());
  });

  test('an error when the drawings fail', () async {
    await works.save(workAt('w', DateTime.utc(2026, 11, 18)));
    drawings.error = StateError('disk');
    final value = await settled(container());
    expect(value.hasError, isTrue);
    expect(value.error, isA<StateError>());
  });

  test('a new drawing joins the list in place', () async {
    final t = DateTime.utc(2026, 11, 18, 12);
    await works.save(workAt('w', t));
    final c = container();
    expect((await settled(c)).requireValue, hasLength(1));
    await saveDrawing(drawingAt('d', t.add(const Duration(minutes: 1))));
    await Future<void>.delayed(Duration.zero);
    final items = c.read(galleryItemsProvider).requireValue;
    expect([for (final i in items) i.id], ['d', 'w']);
  });
}
