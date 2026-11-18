import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/json_file_store.dart';
import '../../coloring/model/work.dart';

/// The folder that holds the work files. Tests override it with a temp dir.
final worksDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/works').create(recursive: true);
  },
);

final workRepositoryProvider = Provider<WorkRepository>((ref) {
  final repository = WorkRepository(ref.watch(worksDirectoryProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

/// The preview image of a work, drawn from the work as it was at
/// [sourceModified]. It is stale when that differs from the work's
/// `modified` (compared in milliseconds, never by file times).
typedef WorkPreview = ({File file, DateTime sourceModified});

/// Something written to the works folder; emitted after the write finished.
sealed class WorkChange {
  const WorkChange();
}

final class WorkSaved extends WorkChange {
  const WorkSaved(this.work);

  final Work work;
}

final class PreviewSaved extends WorkChange {
  const PreviewSaved(this.workId, this.preview);

  final String workId;
  final WorkPreview preview;
}

/// Works on disk: one `<pictureId>-<millis>.json` file per work, plus its
/// preview `<workId>.p<sourceModifiedMillis>.png`.
class WorkRepository {
  WorkRepository(this._directory);

  final Future<Directory> Function() _directory;
  final Map<String, JsonFileStore> _stores = {};
  final Map<String, Future<void>> _previewQueues = {};
  final _changes = StreamController<WorkChange>.broadcast();

  /// Saved works and previews, each emitted after its write finished.
  Stream<WorkChange> get changes => _changes.stream;

  /// Writes for one work go through one store, so they stay ordered.
  Future<void> save(Work work) async {
    await _store(work.id).write(work.toJson());
    _emit(WorkSaved(work));
  }

  /// The work saved as [workId], or null when it is missing, unreadable or
  /// holds another id.
  Future<Work?> byId(String workId) async {
    if (!Work.isPlainId(workId)) return null;
    final work = Work.fromJson(await _store(workId).read());
    return work != null && work.id == workId ? work : null;
  }

  /// Every readable work of [pictureId], read fresh from disk, in no
  /// particular order. `fox` never matches the works of `fox_cocoa`.
  Future<List<Work>> worksFor(String pictureId) async {
    final name = RegExp('^${RegExp.escape(pictureId)}-\\d+\\.json\$');
    final works = <Work>[];
    for (final work in await _read((file) => name.hasMatch(file))) {
      if (work.pictureId == pictureId) works.add(work);
    }
    return works;
  }

  /// The most recently modified readable work of [pictureId], or null.
  /// Unreadable files are skipped and never touched.
  Future<Work?> latestFor(String pictureId) async {
    Work? latest;
    for (final work in await worksFor(pictureId)) {
      if (latest == null || work.modified.isAfter(latest.modified)) {
        latest = work;
      }
    }
    return latest;
  }

  /// Every readable work, in no particular order.
  Future<List<Work>> list() => _read((file) => file.endsWith('.json'));

  /// The newest preview of [workId], or null when it has none.
  Future<WorkPreview?> previewOf(String workId) async {
    if (!Work.isPlainId(workId)) return null;
    return (await previews())[workId];
  }

  /// The newest preview of every work that has one, keyed by work id, from
  /// a single listing of the folder.
  Future<Map<String, WorkPreview>> previews() async {
    final directory = await _directory();
    final newest = <String, WorkPreview>{};
    if (!await directory.exists()) return newest;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final match = _anyPreviewName.firstMatch(entity.uri.pathSegments.last);
      if (match == null) continue;
      final workId = match.group(1)!;
      if (!Work.isPlainId(workId)) continue;
      final millis = int.parse(match.group(2)!);
      final known = newest[workId];
      if (known == null ||
          millis > known.sourceModified.millisecondsSinceEpoch) {
        newest[workId] = (
          file: entity,
          sourceModified: DateTime.fromMillisecondsSinceEpoch(
            millis,
            isUtc: true,
          ),
        );
      }
    }
    return newest;
  }

  /// Writes [png] as the preview of [workId] drawn at [sourceModified] and
  /// removes its other previews. Writes of one work run one after another,
  /// so the last call wins; each replaces the file atomically.
  Future<void> savePreview(
    String workId,
    DateTime sourceModified,
    Uint8List png,
  ) {
    if (!Work.isPlainId(workId)) {
      return Future.error(ArgumentError.value(workId, 'workId'));
    }
    final run = (_previewQueues[workId] ?? Future.value()).then(
      (_) => _writePreview(workId, sourceModified, png),
    );
    _previewQueues[workId] = run.catchError((Object _) {});
    return run;
  }

  /// Closes [changes].
  void dispose() => _changes.close();

  Future<void> _writePreview(
    String workId,
    DateTime sourceModified,
    Uint8List png,
  ) async {
    final directory = await _directory();
    final millis = sourceModified.millisecondsSinceEpoch;
    final file = File('${directory.path}/$workId.p$millis.png');
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(png, flush: true);
    await temp.rename(file.path);
    // Older previews of this work, and temp files a crash left behind.
    final name = _previewName(workId);
    await for (final entity in directory.list()) {
      if (entity is! File || entity.path == file.path) continue;
      if (name.hasMatch(entity.uri.pathSegments.last)) await entity.delete();
    }
    _emit(
      PreviewSaved(workId, (
        file: file,
        sourceModified: DateTime.fromMillisecondsSinceEpoch(
          millis,
          isUtc: true,
        ),
      )),
    );
  }

  Future<List<Work>> _read(bool Function(String fileName) include) async {
    final directory = await _directory();
    if (!await directory.exists()) return [];
    final works = <Work>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.json') || !include(name)) continue;
      final id = name.substring(0, name.length - '.json'.length);
      final work = Work.fromJson(await _store(id).read());
      if (work != null && work.id == id) works.add(work);
    }
    return works;
  }

  void _emit(WorkChange change) {
    if (!_changes.isClosed) _changes.add(change);
  }

  /// `<workId>.p<millis>.png`; the id is everything before the last `.p`.
  static final _anyPreviewName = RegExp(r'^(.+)\.p(\d+)\.png$');

  static RegExp _previewName(String workId) =>
      RegExp('^${RegExp.escape(workId)}\\.p\\d+\\.png(\\.tmp)?\$');

  JsonFileStore _store(String id) =>
      _stores.putIfAbsent(id, () => JsonFileStore(_directory, '$id.json'));
}
