import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../model/drawing_record.dart';

/// The folder that holds the drawings. Tests override it with a temp dir.
final drawingsDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/drawings').create(recursive: true);
  },
);

final drawingRepositoryProvider = Provider<DrawingRepository>((ref) {
  final repository = DrawingRepository(ref.watch(drawingsDirectoryProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

/// The preview image of a drawing, drawn from the drawing as it was at
/// [sourceModified]. It is stale when that differs from the drawing's
/// `modified` (compared in milliseconds, never by file times).
typedef DrawingPreview = ({File file, DateTime sourceModified});

/// Something written to the drawings folder; emitted after the write
/// finished.
sealed class DrawingChange {
  const DrawingChange();
}

final class DrawingSaved extends DrawingChange {
  const DrawingSaved(this.record);

  final DrawingRecord record;
}

final class DrawingPreviewSaved extends DrawingChange {
  const DrawingPreviewSaved(this.drawingId, this.preview);

  final String drawingId;
  final DrawingPreview preview;
}

/// Drawings on disk (spec §12.1): `<id>.json` (a [DrawingRecord]), the
/// raster it names, `<id>.r<modifiedMillis>.png`, and the preview
/// `<id>.p<sourceModifiedMillis>.png`.
///
/// Saves of one drawing run one after another in a per-id queue that
/// [save] joins synchronously, and every read awaits the saves queued
/// before it, so a drawing reopened right after leaving shows its last
/// state (spec §12.2).
class DrawingRepository {
  DrawingRepository(this._directory);

  final Future<Directory> Function() _directory;
  final Map<String, Future<void>> _saveQueues = {};
  final Map<String, int> _pendingSaves = {};

  /// Saves ever started per drawing; [list] skips the files of a drawing
  /// whose count changed while it ran (its snapshot of the folder is stale).
  final Map<String, int> _saveCounts = {};
  final Map<String, Future<void>> _previewQueues = {};
  final Map<String, int> _pendingPreviews = {};
  final _changes = StreamController<DrawingChange>.broadcast();

  /// Saved drawings and previews, each emitted after its write finished.
  Stream<DrawingChange> get changes => _changes.stream;

  /// Queues a save of [record] with the raster [png] (still being encoded)
  /// right now, before this returns. The raster is written first (temp file
  /// + rename), then the JSON; then the older rasters and temp files of the
  /// drawing are deleted. Completes with false, logged and never thrown,
  /// when [png] fails, a write fails or the drawing's JSON exists but is
  /// unreadable; the files saved before stay as they were.
  Future<bool> save(DrawingRecord record, Future<Uint8List> png) {
    final id = record.id;
    if (DrawingRecord.fromJson(record.toJson()) == null ||
        record.raster != DrawingRecord.rasterName(id, record.modified)) {
      throw ArgumentError.value(record.raster, 'record', 'not a valid record');
    }
    // Handle a failing png now: it may fail before the queue reaches it.
    final bytes = png.then<Uint8List?>(
      (b) => b,
      onError: (Object e) {
        debugPrint('Drawing $id: raster encoding failed: $e');
        return null;
      },
    );
    _pendingSaves[id] = (_pendingSaves[id] ?? 0) + 1;
    _saveCounts[id] = (_saveCounts[id] ?? 0) + 1;
    final run = (_saveQueues[id] ?? Future.value())
        .then((_) => _write(record, bytes))
        .catchError((Object e) {
          debugPrint('Drawing $id: save failed: $e');
          return false;
        })
        .whenComplete(() {
          final left = _pendingSaves[id]! - 1;
          if (left == 0) {
            _pendingSaves.remove(id);
          } else {
            _pendingSaves[id] = left;
          }
        });
    _saveQueues[id] = run;
    return run;
  }

  /// Whether a save of [drawingId] is queued or running.
  bool hasPendingSave(String drawingId) => _pendingSaves.containsKey(drawingId);

  /// The drawing saved as [drawingId] once its queued saves finished, or
  /// null when it is missing, unreadable or holds another id.
  Future<DrawingRecord?> byId(String drawingId) async {
    if (!DrawingRecord.isPlainId(drawingId)) return null;
    await _saveQueues[drawingId];
    return _readRecord(await _directory(), drawingId);
  }

  /// The most recently modified readable drawing (ties by id), or null.
  Future<DrawingRecord?> latest() async {
    DrawingRecord? latest;
    for (final record in await list()) {
      if (latest == null || _newer(record, latest)) latest = record;
    }
    return latest;
  }

  /// Every readable drawing, in no particular order, once every queued save
  /// finished. Unreadable JSON files are skipped and never touched. Removes
  /// orphan rasters (no `<id>.json`) and leftover temp files of drawings
  /// with no save or preview write in flight, and none started since this
  /// call (the folder listing would be stale for them).
  Future<List<DrawingRecord>> list() async {
    final saveCounts = Map.of(_saveCounts);
    await Future.wait(_saveQueues.values.toList());
    final directory = await _directory();
    if (!await directory.exists()) return [];
    final names = <String>{};
    await for (final entity in directory.list()) {
      if (entity is File) names.add(entity.uri.pathSegments.last);
    }
    final records = <DrawingRecord>[];
    for (final name in names) {
      if (!name.endsWith('.json')) continue;
      final id = name.substring(0, name.length - '.json'.length);
      if (!DrawingRecord.isPlainId(id)) continue;
      final record = await _readRecord(directory, id);
      if (record != null) records.add(record);
    }
    for (final name in names) {
      final raster = _anyRasterName.firstMatch(name);
      final String id;
      if (raster != null) {
        id = raster.group(1)!;
        if (names.contains('$id.json')) continue;
      } else if (_anyTempName.firstMatch(name) case final temp?) {
        id = temp.group(1)!;
        if (_pendingPreviews.containsKey(id)) continue;
      } else {
        continue;
      }
      if (hasPendingSave(id) || _saveCounts[id] != saveCounts[id]) continue;
      await _deleteQuietly(File('${directory.path}/$name'));
    }
    return records;
  }

  /// The raster PNG of [drawingId] once its queued saves finished, or null
  /// when the drawing or its raster is missing or unreadable.
  Future<Uint8List?> rasterOf(String drawingId) async {
    final record = await byId(drawingId);
    if (record == null) return null;
    try {
      final file = File('${(await _directory()).path}/${record.raster}');
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on Object catch (e) {
      debugPrint('Drawing $drawingId: cannot read the raster: $e');
      return null;
    }
  }

  /// The newest preview of [drawingId], or null when it has none.
  Future<DrawingPreview?> previewOf(String drawingId) async {
    if (!DrawingRecord.isPlainId(drawingId)) return null;
    return (await previews())[drawingId];
  }

  /// The newest preview of every drawing that has one, keyed by drawing id,
  /// from a single listing of the folder.
  Future<Map<String, DrawingPreview>> previews() async {
    final directory = await _directory();
    final newest = <String, DrawingPreview>{};
    if (!await directory.exists()) return newest;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final match = _anyPreviewName.firstMatch(entity.uri.pathSegments.last);
      if (match == null) continue;
      final id = match.group(1)!;
      if (!DrawingRecord.isPlainId(id)) continue;
      final millis = int.parse(match.group(2)!);
      final known = newest[id];
      if (known == null ||
          millis > known.sourceModified.millisecondsSinceEpoch) {
        newest[id] = (file: entity, sourceModified: _utc(millis));
      }
    }
    return newest;
  }

  /// Writes [png] as the preview of [drawingId] drawn at [sourceModified]
  /// and removes its other previews. Writes of one drawing run one after
  /// another, so the last call wins; each replaces the file atomically.
  Future<void> savePreview(
    String drawingId,
    DateTime sourceModified,
    Uint8List png,
  ) {
    if (!DrawingRecord.isPlainId(drawingId)) {
      return Future.error(ArgumentError.value(drawingId, 'drawingId'));
    }
    _pendingPreviews[drawingId] = (_pendingPreviews[drawingId] ?? 0) + 1;
    final run = (_previewQueues[drawingId] ?? Future.value())
        .then((_) => _writePreview(drawingId, sourceModified, png))
        .whenComplete(() {
          final left = _pendingPreviews[drawingId]! - 1;
          if (left == 0) {
            _pendingPreviews.remove(drawingId);
          } else {
            _pendingPreviews[drawingId] = left;
          }
        });
    _previewQueues[drawingId] = run.catchError((Object _) {});
    return run;
  }

  /// Closes [changes].
  void dispose() => _changes.close();

  Future<bool> _write(DrawingRecord record, Future<Uint8List?> png) async {
    final id = record.id;
    final directory = await _directory();
    final json = File('${directory.path}/$id.json');
    if (await json.exists() && await _readRecord(directory, id) == null) {
      debugPrint('Drawing $id: the saved file is unreadable, not replacing');
      return false;
    }
    final bytes = await png;
    if (bytes == null) return false;
    await _writeAtomically(File('${directory.path}/${record.raster}'), bytes);
    await _writeAtomically(json, utf8.encode(jsonEncode(record.toJson())));
    // Older rasters of this drawing, and temp files a crash left behind.
    final stale = RegExp(
      '^${RegExp.escape(id)}\\.(?:r\\d+\\.png|json\\.tmp|r\\d+\\.png\\.tmp)\$',
    );
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name != record.raster && stale.hasMatch(name)) {
        await _deleteQuietly(entity);
      }
    }
    _emit(DrawingSaved(record));
    return true;
  }

  Future<void> _writePreview(
    String drawingId,
    DateTime sourceModified,
    Uint8List png,
  ) async {
    final directory = await _directory();
    final millis = sourceModified.millisecondsSinceEpoch;
    final file = File('${directory.path}/$drawingId.p$millis.png');
    await _writeAtomically(file, png);
    // Older previews of this drawing, and temp files a crash left behind.
    final name = RegExp(
      '^${RegExp.escape(drawingId)}\\.p\\d+\\.png(\\.tmp)?\$',
    );
    await for (final entity in directory.list()) {
      if (entity is! File || entity.path == file.path) continue;
      if (name.hasMatch(entity.uri.pathSegments.last)) {
        await _deleteQuietly(entity);
      }
    }
    _emit(
      DrawingPreviewSaved(drawingId, (
        file: file,
        sourceModified: _utc(millis),
      )),
    );
  }

  Future<DrawingRecord?> _readRecord(Directory directory, String id) async {
    try {
      final file = File('${directory.path}/$id.json');
      if (!await file.exists()) return null;
      final record = DrawingRecord.fromJson(
        jsonDecode(await file.readAsString()),
      );
      return record != null && record.id == id ? record : null;
    } on Object {
      return null;
    }
  }

  void _emit(DrawingChange change) {
    if (!_changes.isClosed) _changes.add(change);
  }

  static Future<void> _writeAtomically(File file, List<int> bytes) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  static bool _newer(DrawingRecord a, DrawingRecord b) {
    final byTime = a.modified.compareTo(b.modified);
    return byTime != 0 ? byTime > 0 : a.id.compareTo(b.id) > 0;
  }

  static DateTime _utc(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

  /// `<id>.r<millis>.png`; the id is everything before the last `.r`.
  static final _anyRasterName = RegExp(r'^(.+)\.r\d+\.png$');

  /// `<id>.p<millis>.png`; the id is everything before the last `.p`.
  static final _anyPreviewName = RegExp(r'^(.+)\.p(\d+)\.png$');

  /// A temp file of a JSON, raster or preview write.
  static final _anyTempName = RegExp(
    r'^(.+)\.(?:json|r\d+\.png|p\d+\.png)\.tmp$',
  );
}
