import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coloring/features/coloring/model/region_map.dart';
import 'package:coloring/features/gallery/data/work_preview_service.dart';
import 'package:coloring/features/gallery/data/works_provider.dart';

/// One [WorkPreviewService.renderAfterLeave] call. [cloneValid] says whether
/// the lines clone was still usable when the call came in.
typedef PreviewCall = ({
  String workId,
  DateTime sourceModified,
  RegionMap map,
  Uint32List colors,
  bool cloneValid,
});

/// Records preview requests instead of drawing them, and disposes every
/// lines clone it receives like the real service. [onRender] runs inside
/// the call, before the clone is disposed.
class FakePreviewService implements WorkPreviewService {
  FakePreviewService({this.onRender});

  void Function(PreviewCall call)? onRender;
  final calls = <PreviewCall>[];
  final backfills = <List<WorkSummary>>[];
  int cancelBackfillCalls = 0;
  bool disposed = false;

  @override
  Future<void> get idle => Future.value();

  @override
  void renderAfterLeave({
    required String workId,
    required DateTime sourceModified,
    required RegionMap map,
    required Uint32List colors,
    required ui.Image linesClone,
  }) {
    final call = (
      workId: workId,
      sourceModified: sourceModified,
      map: map,
      colors: Uint32List.fromList(colors),
      cloneValid: !linesClone.debugDisposed,
    );
    calls.add(call);
    try {
      onRender?.call(call);
    } finally {
      linesClone.dispose();
    }
  }

  @override
  Future<void> backfill(List<WorkSummary> works) async {
    backfills.add(List.of(works));
  }

  @override
  void cancelBackfill() => cancelBackfillCalls++;

  @override
  void dispose() => disposed = true;
}
