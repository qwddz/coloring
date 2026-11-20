import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/drawing/data/drawing_preview_service.dart';
import 'package:coloring/features/drawing/data/drawing_repository.dart';
import 'package:coloring/features/drawing/data/drawings_provider.dart';
import 'package:coloring/features/drawing/model/drawing_record.dart';
import 'package:coloring/features/gallery/data/my_works_controller.dart';
import 'package:coloring/features/gallery/data/work_exporter.dart';
import 'package:coloring/features/gallery/data/work_preview_service.dart';
import 'package:coloring/features/gallery/data/works_provider.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../coloring/fakes.dart';
import '../drawing/fakes.dart';
import 'fake_preview_service.dart';

class SlowPreviewService extends FakePreviewService {
  final done = Completer<void>();

  @override
  Future<void> backfill(List<WorkSummary> works) async {
    await super.backfill(works);
    await done.future;
  }
}

class SlowDrawingPreviewService extends FakeDrawingPreviewService {
  final done = Completer<void>();

  @override
  Future<void> backfill(List<DrawingSummary> drawings) async {
    await super.backfill(drawings);
    await done.future;
  }
}

void main() {
  late InMemoryWorkRepository works;
  late InMemoryDrawingRepository drawings;
  late SlowPreviewService previews;
  late SlowDrawingPreviewService drawingPreviews;
  late Directory temp;

  setUp(() async {
    works = InMemoryWorkRepository();
    drawings = InMemoryDrawingRepository();
    previews = SlowPreviewService();
    drawingPreviews = SlowDrawingPreviewService();
    temp = Directory.systemTemp.createTempSync('my_works_controller');
    final modified = DateTime.utc(2026, 11, 18, 12);
    await works.save(
      Work(
        id: 'w-1',
        pictureId: 'farm_piglet_picnic',
        mode: ColoringMode.free,
        colors: Uint32List(6),
        modified: modified,
      ),
    );
    await drawings.save(
      DrawingRecord(
        id: 'd-1',
        created: modified,
        modified: modified,
        width: 4,
        height: 3,
        raster: DrawingRecord.rasterName('d-1', modified),
      ),
      Future.value(Uint8List(1)),
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        workRepositoryProvider.overrideWithValue(works),
        workPreviewServiceProvider.overrideWithValue(previews),
        drawingRepositoryProvider.overrideWithValue(drawings),
        drawingPreviewServiceProvider.overrideWithValue(drawingPreviews),
        shareDirectoryProvider.overrideWithValue(
          () async => Directory('${temp.path}/share'),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('backfilling counts the work and drawing backfills apart', () async {
    final c = container();
    c.listen(myWorksControllerProvider, (_, _) {});
    await flush();
    expect(previews.backfills, hasLength(1));
    expect(drawingPreviews.backfills.single.single.record.id, 'd-1');
    expect(c.read(myWorksControllerProvider).backfills, 2);

    drawingPreviews.done.complete();
    await flush();
    expect(c.read(myWorksControllerProvider).backfills, 1);
    expect(c.read(myWorksControllerProvider).backfilling, isTrue);

    previews.done.complete();
    await flush();
    expect(c.read(myWorksControllerProvider).backfills, 0);
    expect(c.read(myWorksControllerProvider).backfilling, isFalse);
  });

  test('fresh drawing previews start no drawing backfill', () async {
    final record = (await drawings.byId('d-1'))!;
    await drawings.savePreview('d-1', record.modified, Uint8List(1));
    final c = container();
    c.listen(myWorksControllerProvider, (_, _) {});
    await flush();
    expect(drawingPreviews.backfills, isEmpty);
    expect(c.read(myWorksControllerProvider).backfills, 1);
  });

  test('leaving cancels both backfills', () async {
    final c = container();
    final sub = c.listen(myWorksControllerProvider, (_, _) {});
    await flush();
    sub.close();
    await flush();
    expect(previews.cancelBackfillCalls, 1);
    expect(drawingPreviews.cancelBackfillCalls, 1);
  });
}
