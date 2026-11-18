import 'dart:io';

import 'package:coloring/features/progress/data/progress_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('progress_test');
    file = File('${dir.path}/progress.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer makeContainer() {
    final c = ProviderContainer(
      overrides: [progressDirectoryProvider.overrideWithValue(() async => dir)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts empty without a file and writes nothing', () async {
    final c = makeContainer();
    expect(await c.read(progressProvider.future), isEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('markCompleted round trips through a new container', () async {
    final c1 = makeContainer();
    await c1.read(progressProvider.notifier).markCompleted('fox');
    await c1.read(progressProvider.notifier).markCompleted('cat');
    expect(c1.read(progressProvider).requireValue, {'fox', 'cat'});

    final c2 = makeContainer();
    expect(await c2.read(progressProvider.future), {'fox', 'cat'});
  });

  test('markCompleted is idempotent and writes once', () async {
    final c = makeContainer();
    final notifier = c.read(progressProvider.notifier);
    await notifier.markCompleted('fox');
    file.writeAsStringSync('{"version":1,"completed":["fox"]}');
    await notifier.markCompleted('fox');
    expect(c.read(progressProvider).requireValue, {'fox'});
    expect(file.readAsStringSync(), '{"version":1,"completed":["fox"]}');
  });

  test('concurrent calls all land', () async {
    final c = makeContainer();
    final notifier = c.read(progressProvider.notifier);
    await Future.wait([
      notifier.markCompleted('a'),
      notifier.markCompleted('b'),
      notifier.markCompleted('a'),
    ]);
    final fresh = makeContainer();
    expect(await fresh.read(progressProvider.future), {'a', 'b'});
  });

  test('a corrupt file reads as empty and is never overwritten', () async {
    file.writeAsStringSync('{not json');
    final c = makeContainer();
    expect(await c.read(progressProvider.future), isEmpty);
    await c.read(progressProvider.notifier).markCompleted('fox');
    expect(c.read(progressProvider).requireValue, {'fox'});
    expect(file.readAsStringSync(), '{not json');
  });

  test('an unknown version or wrong shape counts as corrupt', () async {
    file.writeAsStringSync('{"version":2,"completed":["fox"]}');
    final c = makeContainer();
    expect(await c.read(progressProvider.future), isEmpty);
    await c.read(progressProvider.notifier).markCompleted('cat');
    expect(file.readAsStringSync(), contains('"version":2'));
  });
}
