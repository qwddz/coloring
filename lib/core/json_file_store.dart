import 'dart:convert';
import 'dart:io';

/// One JSON document on disk. Writes run one after another and replace the
/// file atomically, so a crash never leaves half a document.
class JsonFileStore {
  JsonFileStore(this._directory, this.fileName);

  final Future<Directory> Function() _directory;
  final String fileName;
  Future<void> _pending = Future.value();

  Future<File> get _file async =>
      File('${(await _directory()).path}/$fileName');

  /// The decoded document, or null when it is missing or unreadable.
  Future<Object?> read() async {
    try {
      await _pending;
      final file = await _file;
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } on Object {
      return null;
    }
  }

  /// Whether the document exists, readable or not.
  Future<bool> exists() async {
    await _pending;
    return (await _file).exists();
  }

  /// Encodes [json] now and writes it after earlier writes finish.
  Future<void> write(Object? json) {
    final text = jsonEncode(json);
    return _enqueue(() async {
      final file = await _file;
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(text, flush: true);
      await temp.rename(file.path);
    });
  }

  Future<void> delete() => _enqueue(() async {
    final file = await _file;
    if (await file.exists()) await file.delete();
  });

  /// A failed write is dropped; the next change writes the document again.
  Future<void> _enqueue(Future<void> Function() action) =>
      _pending = _pending.then((_) => action()).catchError((Object _) {});
}
