import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/content/data/picture_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_cdn.dart';

/// Serves asset keys from [files].
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);

  final Map<String, List<int>> files;

  @override
  Future<ByteData> load(String key) async {
    final bytes = files[key];
    if (bytes == null) throw StateError('no asset $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

Matcher failsWith(PictureLoadFailure failure) => throwsA(
  isA<PictureLoadException>().having((e) => e.failure, 'failure', failure),
);

/// Distinct bytes for each layer file.
Map<String, List<int>> layers([int seed = 1]) => {
  for (final (i, name) in PictureLayers.required.indexed)
    name: List<int>.generate(20000, (j) => (j * (i + 3) + seed) % 256),
};

Uint8List zipOf(Map<String, List<int>> files) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.addFile(ArchiveFile.bytes(key, value));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  const path = '/home/home_hamster_book.zip';
  late Map<String, List<int>> content;
  late Uint8List zip;
  late Directory dir;
  late FakeCdn cdn;
  late PictureStore store;

  PictureEntry entryFor(List<int> zip, {String? asset, bool free = false}) =>
      PictureEntry(
        id: 'home_hamster_book',
        categoryId: 'home',
        title: const LocalizedText({'en': 'Hamster reading'}),
        level: PictureLevel.medium,
        free: free,
        asset: asset,
        url: 'home/home_hamster_book.zip',
        sha256: sha256.convert(zip).toString(),
        bytes: zip.length,
      );

  setUp(() {
    content = layers();
    zip = zipOf(content);
    dir = Directory.systemTemp.createTempSync('picture_store');
    cdn = FakeCdn()..files[path] = zip;
    store = PictureStore(
      dio: cdn.dio,
      directory: () async => dir,
      cdnBaseUrl: 'https://cdn.test/',
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Directory folder() => Directory('${dir.path}/pictures/home_hamster_book');
  List<String> pictureFiles() => [
    for (final item in Directory('${dir.path}/pictures').listSync())
      item.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ]..sort();

  Future<void> expectLayers(PictureFiles files, Map<String, List<int>> want) =>
      Future.wait([
        for (final MapEntry(:key, :value) in want.entries)
          files.read(key).then((bytes) => expect(bytes, value, reason: key)),
      ]);

  test('downloads the zip once, then opens the layers offline', () async {
    final entry = entryFor(zip);
    final progress = <double>[];
    final files = await store.load(entry, onProgress: progress.add);
    await expectLayers(files, content);
    expect(cdn.requests, [path]);
    expect(progress.last, 1.0);
    expect(pictureFiles(), ['home_hamster_book']);

    cdn.offline = true;
    final again = <double>[];
    await expectLayers(await store.load(entry, onProgress: again.add), content);
    expect(cdn.requests, hasLength(1));
    expect(again, isEmpty);
  });

  test(
    'isLocal: only a complete download of the current zip, no fetch',
    () async {
      final entry = entryFor(zip);
      expect(await store.isLocal(entry), isFalse);
      expect(cdn.requests, isEmpty);
      await store.load(entry);
      expect(await store.isLocal(entry), isTrue);
      final newZip = zipOf(layers(2));
      expect(await store.isLocal(entryFor(newZip)), isFalse);
      File('${folder().path}/${PictureLayers.regions}').deleteSync();
      expect(await store.isLocal(entry), isFalse);
      expect(cdn.requests, hasLength(1));
    },
  );

  test('a cache folder missing a layer is downloaded again', () async {
    final entry = entryFor(zip);
    await store.load(entry);
    File('${folder().path}/${PictureLayers.regions}').deleteSync();
    await expectLayers(await store.load(entry), content);
    expect(cdn.requests, hasLength(2));
  });

  test('a picture updated in the manifest is downloaded again', () async {
    await store.load(entryFor(zip));
    final updated = layers(2);
    final newZip = zipOf(updated);
    cdn.files[path] = newZip;
    await expectLayers(await store.load(entryFor(newZip)), updated);
    expect(cdn.requests, hasLength(2));
    expect(pictureFiles(), ['home_hamster_book']);
  });

  test('a download with the wrong checksum is rejected and not kept', () async {
    final entry = entryFor(zip);
    cdn.files[path] = [...zip.take(zip.length - 1), zip.last ^ 1];
    await expectLater(store.load(entry), failsWith(PictureLoadFailure.corrupt));
    expect(pictureFiles(), isEmpty);
  });

  test('a zip without every layer is corrupt and not kept', () async {
    final partial = zipOf({...content}..remove(PictureLayers.regionsJson));
    cdn.files[path] = partial;
    await expectLater(
      store.load(entryFor(partial)),
      failsWith(PictureLoadFailure.corrupt),
    );
    expect(pictureFiles(), isEmpty);
  });

  group('declared sizes', () {
    /// A zip of the real layers plus a deflated filler of zeros; zeros
    /// compress to almost nothing, like a zip bomb.
    Uint8List withFiller(List<int> sizes) => zipOf({
      ...content,
      for (final (i, size) in sizes.indexed) 'filler$i.bin': Uint8List(size),
    });

    Future<void> expectCorrupt(Uint8List bomb) async {
      cdn.files[path] = bomb;
      await expectLater(
        store.load(entryFor(bomb)),
        failsWith(PictureLoadFailure.corrupt),
      );
      expect(pictureFiles(), isEmpty);
    }

    test('an entry over 32 MiB is corrupt', () async {
      await expectCorrupt(withFiller([(32 << 20) + 1]));
    });

    test('entries over 64 MiB in total are corrupt', () async {
      await expectCorrupt(withFiller([30 << 20, 30 << 20, 5 << 20]));
    });

    test('an entry of exactly 32 MiB is accepted', () async {
      final ok = withFiller([32 << 20]);
      cdn.files[path] = ok;
      await expectLayers(await store.load(entryFor(ok)), content);
    });
  });

  test('a file that is not a zip is corrupt even with its checksum', () async {
    final notZip = utf8.encode('<html>not a zip</html>');
    cdn.files[path] = notZip;
    await expectLater(
      store.load(entryFor(notZip)),
      failsWith(PictureLoadFailure.corrupt),
    );
    expect(pictureFiles(), isEmpty);
  });

  test(
    'zip folders are flattened and hidden or escaping names stay in',
    () async {
      final nested = zipOf({
        for (final MapEntry(:key, :value) in content.entries)
          'home_hamster_book/$key': value,
        '__MACOSX/home_hamster_book/._lines.png': [1, 2, 3],
        '.DS_Store': [4],
        '../escape.txt': [5],
      });
      cdn.files[path] = nested;
      await expectLayers(await store.load(entryFor(nested)), content);
      final names = [
        for (final file in folder().listSync()) file.uri.pathSegments.last,
      ]..sort();
      expect(names, [
        '.sha256',
        'colored.webp',
        'escape.txt',
        'lines.png',
        'regions.json',
        'regions.png',
      ]);
      expect(File('${dir.path}/pictures/escape.txt').existsSync(), isFalse);
      expect(File('${dir.path}/escape.txt').existsSync(), isFalse);
    },
  );

  test('offline without a cached copy fails with a network error', () async {
    cdn.offline = true;
    await expectLater(
      store.load(entryFor(zip)),
      failsWith(PictureLoadFailure.network),
    );
    expect(pictureFiles(), isEmpty);
  });

  test('two opens at once share one download', () async {
    final entry = entryFor(zip);
    final first = <double>[], second = <double>[];
    final results = await Future.wait([
      store.load(entry, onProgress: first.add),
      store.load(entry, onProgress: second.add),
    ]);
    for (final files in results) {
      await expectLayers(files, content);
    }
    expect(cdn.requests, hasLength(1));
    expect(first.last, 1.0);
    expect(second.last, 1.0);
    expect(pictureFiles(), ['home_hamster_book']);
  });

  test('without a CDN address a downloadable picture is unavailable', () {
    final offlineStore = PictureStore(
      dio: cdn.dio,
      directory: () async => dir,
      cdnBaseUrl: '',
    );
    expect(
      offlineStore.load(entryFor(zip)),
      failsWith(PictureLoadFailure.unavailable),
    );
  });

  test('a CDN error answer is unavailable, not a network error', () async {
    cdn.files.remove(path);
    await expectLater(
      store.load(entryFor(zip)),
      failsWith(PictureLoadFailure.unavailable),
    );
    expect(pictureFiles(), isEmpty);
  });

  test('leftover partial downloads are removed on first use', () async {
    final pictures = Directory('${dir.path}/pictures')..createSync();
    File('${pictures.path}/home_fox.zip.part').writeAsBytesSync([1]);
    Directory('${pictures.path}/home_fox.tmp').createSync();
    File('${pictures.path}/home_fox.tmp/lines.png').writeAsBytesSync([2]);
    Directory('${pictures.path}/home_owl').createSync();
    await store.load(entryFor(zip));
    expect(pictureFiles(), ['home_hamster_book', 'home_owl']);
  });

  group('a picture with both bundled and CDN sources', () {
    const asset = 'coloring/free/home_hamster_book/';
    final bundled = layers(9);
    PictureStore storeWith(Set<String> assets) => PictureStore(
      dio: cdn.dio,
      directory: () async => dir,
      cdnBaseUrl: 'https://cdn.test/',
      bundle: _FakeBundle({
        for (final MapEntry(:key, :value) in bundled.entries)
          'assets/$asset$key': value,
      }),
      bundledAssets: () async => assets,
    );

    test('opens the bundled layers when this build ships them', () async {
      final store = storeWith({
        for (final name in bundled.keys) 'assets/$asset$name',
      });
      final files = await store.load(entryFor(zip, asset: asset, free: true));
      expect(files, isA<BundledPictureFiles>());
      await expectLayers(files, bundled);
      expect(cdn.requests, isEmpty);
    });

    test(
      'downloads from the CDN when the asset is not in this build',
      () async {
        final files = await storeWith({})
            .load(entryFor(zip, asset: asset, free: true));
        await expectLayers(files, content);
        expect(cdn.requests, [path]);
      },
    );

    test('is unavailable without either source', () {
      const bundledOnly = PictureEntry(
        id: 'home_hamster_book',
        categoryId: 'home',
        title: LocalizedText({'en': 'Hamster reading'}),
        level: PictureLevel.medium,
        free: true,
        asset: asset,
      );
      expect(
        storeWith({}).load(bundledOnly),
        failsWith(PictureLoadFailure.unavailable),
      );
    });
  });
}
