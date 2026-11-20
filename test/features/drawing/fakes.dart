import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coloring/features/drawing/data/drawing_preview_service.dart';
import 'package:coloring/features/drawing/data/drawing_repository.dart';
import 'package:coloring/features/drawing/data/drawings_provider.dart';
import 'package:coloring/features/drawing/model/drawing_record.dart';

/// Drawings kept in memory with the same save queue contract as
/// [DrawingRepository]: [save] queues at once, reads await the saves queued
/// before them, a failing png leaves the previous state.
class InMemoryDrawingRepository implements DrawingRepository {
  final records = <String, DrawingRecord>{};
  final rasters = <String, Uint8List>{};
  final previewBytes = <String, Uint8List>{};
  final saves = <DrawingRecord>[];
  final _previews = <String, DrawingPreview>{};
  final _queues = <String, Future<bool>>{};
  final _pending = <String, int>{};
  final _changes = StreamController<DrawingChange>.broadcast();
  int listCalls = 0;

  @override
  Stream<DrawingChange> get changes => _changes.stream;

  @override
  Future<bool> save(DrawingRecord record, Future<Uint8List> png) {
    final id = record.id;
    final bytes = png.then<Uint8List?>((b) => b, onError: (Object _) => null);
    _pending[id] = (_pending[id] ?? 0) + 1;
    final run = (_queues[id] ?? Future.value(true))
        .then((_) async {
          final raster = await bytes;
          if (raster == null) return false;
          saves.add(record);
          records[id] = record;
          rasters[id] = Uint8List.fromList(raster);
          if (!_changes.isClosed) _changes.add(DrawingSaved(record));
          return true;
        })
        .whenComplete(() {
          final left = _pending[id]! - 1;
          if (left == 0) {
            _pending.remove(id);
          } else {
            _pending[id] = left;
          }
        });
    _queues[id] = run;
    return run;
  }

  @override
  bool hasPendingSave(String drawingId) => _pending.containsKey(drawingId);

  @override
  Future<DrawingRecord?> byId(String drawingId) async {
    await _queues[drawingId];
    return records[drawingId];
  }

  @override
  Future<DrawingRecord?> latest() async {
    DrawingRecord? latest;
    for (final record in await list()) {
      if (latest == null ||
          record.modified.isAfter(latest.modified) ||
          (record.modified == latest.modified &&
              record.id.compareTo(latest.id) > 0)) {
        latest = record;
      }
    }
    return latest;
  }

  @override
  Future<List<DrawingRecord>> list() async {
    listCalls++;
    await Future.wait(_queues.values.toList());
    return records.values.toList();
  }

  @override
  Future<Uint8List?> rasterOf(String drawingId) async {
    await _queues[drawingId];
    return rasters[drawingId];
  }

  @override
  Future<DrawingPreview?> previewOf(String drawingId) async =>
      _previews[drawingId];

  @override
  Future<Map<String, DrawingPreview>> previews() async => Map.of(_previews);

  @override
  Future<void> savePreview(
    String drawingId,
    DateTime sourceModified,
    Uint8List png,
  ) async {
    final millis = sourceModified.millisecondsSinceEpoch;
    final preview = (
      file: File('memory/$drawingId.p$millis.png'),
      sourceModified: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
    );
    previewBytes[drawingId] = Uint8List.fromList(png);
    _previews[drawingId] = preview;
    if (!_changes.isClosed) {
      _changes.add(DrawingPreviewSaved(drawingId, preview));
    }
  }

  @override
  void dispose() => _changes.close();
}

/// One [DrawingPreviewService.renderAfterLeave] call. [cloneValid] says
/// whether the image clone was still usable when the call came in.
typedef DrawingPreviewCall = ({
  String drawingId,
  DateTime sourceModified,
  int width,
  int height,
  bool cloneValid,
});

/// Records preview requests instead of drawing them, and disposes every
/// image clone it receives like the real service.
class FakeDrawingPreviewService implements DrawingPreviewService {
  final calls = <DrawingPreviewCall>[];
  final backfills = <List<DrawingSummary>>[];
  int cancelBackfillCalls = 0;
  bool disposed = false;

  @override
  Future<void> get idle => Future.value();

  @override
  void renderAfterLeave({
    required String drawingId,
    required DateTime sourceModified,
    required ui.Image imageClone,
  }) {
    final valid = !imageClone.debugDisposed;
    calls.add((
      drawingId: drawingId,
      sourceModified: sourceModified,
      width: valid ? imageClone.width : 0,
      height: valid ? imageClone.height : 0,
      cloneValid: valid,
    ));
    if (valid) imageClone.dispose();
  }

  @override
  Future<void> backfill(List<DrawingSummary> drawings) async {
    backfills.add(List.of(drawings));
  }

  @override
  void cancelBackfill() => cancelBackfillCalls++;

  @override
  void dispose() => disposed = true;
}
