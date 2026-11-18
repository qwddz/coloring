import 'dart:io';

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

final workRepositoryProvider = Provider<WorkRepository>(
  (ref) => WorkRepository(ref.watch(worksDirectoryProvider)),
);

/// Works on disk: one `<pictureId>-<millis>.json` file per work.
class WorkRepository {
  WorkRepository(this._directory);

  final Future<Directory> Function() _directory;
  final Map<String, JsonFileStore> _stores = {};

  /// Writes for one work go through one store, so they stay ordered.
  Future<void> save(Work work) => _store(work.id).write(work.toJson());

  /// The most recently modified readable work of [pictureId], or null.
  /// Unreadable files are skipped and never touched.
  Future<Work?> latestFor(String pictureId) async {
    final suffix = RegExp('^${RegExp.escape(pictureId)}-\\d+\\.json\$');
    Work? latest;
    for (final work in await list()) {
      if (work.pictureId != pictureId || !suffix.hasMatch('${work.id}.json')) {
        continue;
      }
      if (latest == null || work.modified.isAfter(latest.modified)) {
        latest = work;
      }
    }
    return latest;
  }

  /// Every readable work, in no particular order.
  Future<List<Work>> list() async {
    final directory = await _directory();
    if (!await directory.exists()) return [];
    final works = <Work>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.uri.pathSegments.last;
      final id = name.substring(0, name.length - '.json'.length);
      final work = Work.fromJson(await _store(id).read());
      if (work != null && work.id == id) works.add(work);
    }
    return works;
  }

  JsonFileStore _store(String id) =>
      _stores.putIfAbsent(id, () => JsonFileStore(_directory, '$id.json'));
}
