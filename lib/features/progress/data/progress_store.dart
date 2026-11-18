import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/json_file_store.dart';

/// The folder that holds `progress.json`. Tests override it with a temp dir.
final progressDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => getApplicationDocumentsDirectory,
);

final progressStoreProvider = Provider<JsonFileStore>(
  (ref) => JsonFileStore(ref.watch(progressDirectoryProvider), 'progress.json'),
);

const _version = 1;

/// Ids of completed pictures (the star), loaded from disk and saved on every
/// change. Kept even when the works of a picture are cleared or deleted.
class ProgressController extends AsyncNotifier<Set<String>> {
  /// False when the file exists but cannot be read (corrupt, or written by a
  /// newer app version). Progress then lives in memory only, so the file is
  /// never overwritten with less than it holds.
  bool _canWrite = true;

  Future<void> _lastWrite = Future.value();

  @override
  Future<Set<String>> build() async {
    final store = ref.read(progressStoreProvider);
    final ids = _decode(await store.read());
    if (ids != null) return ids;
    _canWrite = !await store.exists();
    return const {};
  }

  /// Marks [pictureId] completed; a repeated call changes nothing. Calls run
  /// one after another, each on top of the latest state.
  Future<void> markCompleted(String pictureId) =>
      _lastWrite = _lastWrite.then((_) async {
        final current = await future;
        if (!ref.mounted || current.contains(pictureId)) return;
        final updated = {...current, pictureId};
        state = AsyncData(updated);
        if (_canWrite) {
          await ref.read(progressStoreProvider).write({
            'version': _version,
            'completed': updated.toList()..sort(),
          });
        }
      });

  static Set<String>? _decode(Object? json) {
    if (json is! Map<String, Object?> || json['version'] != _version) {
      return null;
    }
    final completed = json['completed'];
    if (completed is! List || completed.any((id) => id is! String)) return null;
    return completed.cast<String>().toSet();
  }
}

final progressProvider = AsyncNotifierProvider<ProgressController, Set<String>>(
  ProgressController.new,
);
