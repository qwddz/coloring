import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/core/json_file_store.dart';

void main() {
  test('the last of several quick writes wins', () async {
    final dir = Directory.systemTemp.createTempSync('store');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = JsonFileStore(() async => dir, 'doc.json');
    await Future.wait([
      for (var i = 0; i < 20; i++) store.write({'n': i}),
    ]);
    expect(await store.read(), {'n': 19});
    await store.delete();
    expect(await store.read(), isNull);
    expect(await store.exists(), isFalse);
  });

  test('an unreadable file reads as null but still exists', () async {
    final dir = Directory.systemTemp.createTempSync('store');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/doc.json').writeAsStringSync('{broken');
    final store = JsonFileStore(() async => dir, 'doc.json');
    expect(await store.read(), isNull);
    expect(await store.exists(), isTrue);
  });
}
