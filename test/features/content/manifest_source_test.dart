import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/core/json_file_store.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/content/content_config.dart';
import 'package:coloring/features/content/data/manifest_source.dart';

import 'fake_cdn.dart';

Map<String, Object?> manifestJson(
  int version, {
  String? minAppVersion,
  List<String> ids = const ['home_fox_cocoa'],
}) => {
  'version': version,
  'minAppVersion': ?minAppVersion,
  'categories': [
    {
      'id': 'home',
      'title': {'en': 'Home'},
      'pictures': [
        for (final id in ids)
          {
            'id': id,
            'title': {'en': 'Fox'},
            'level': 'simple',
            'asset': 'coloring/free/$id/',
          },
      ],
    },
  ],
};

/// Ten pictures, `p0` … `p9`.
final tenIds = [for (var i = 0; i < 10; i++) 'p$i'];

void main() {
  late Directory dir;
  late FakeCdn cdn;
  late JsonFileStore cache;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('manifest_source');
    cdn = FakeCdn();
    cache = JsonFileStore(() async => dir, 'cdn_manifest.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ManifestSource source({
    String baseUrl = 'https://cdn.test',
    List<String> bundledIds = const ['home_fox_cocoa'],
  }) => ManifestSource(
    loadBundled: () async => jsonEncode(manifestJson(2, ids: bundledIds)),
    cache: cache,
    dio: cdn.dio,
    cdnBaseUrl: baseUrl,
    appVersion: () async => '1.2.0',
  );

  void serve(Object json) =>
      cdn.files['/manifest.json'] = utf8.encode(jsonEncode(json));

  test('a newer CDN manifest is accepted and cached', () async {
    serve(manifestJson(3, minAppVersion: '1.2.0'));
    final local = await source().loadLocal();
    expect(local.version, 2);
    final newer = await source().fetchNewer(local);
    expect(newer?.version, 3);
    expect(cdn.requests, ['/manifest.json']);
    // Next start picks the cached copy without the network.
    cdn.offline = true;
    expect((await source().loadLocal()).version, 3);
  });

  test('older, broken and too new for the app manifests are ignored', () async {
    final local = await source().loadLocal();
    for (final body in [
      jsonEncode(manifestJson(1)),
      jsonEncode(manifestJson(2)),
      '{not json',
      jsonEncode({'version': 9, 'categories': 'none'}),
      jsonEncode(manifestJson(9, minAppVersion: '1.10.0')),
    ]) {
      cdn.files['/manifest.json'] = utf8.encode(body);
      expect(await source().fetchNewer(local), isNull, reason: body);
    }
    expect(await cache.exists(), isFalse);
  });

  test(
    'an empty manifest or one dropping over 10% of pictures is rejected',
    () async {
      final local = await source(bundledIds: tenIds).loadLocal();
      for (final ids in [
        const <String>[],
        tenIds.skip(2).toList(),
        ['other', ...tenIds.skip(2)],
      ]) {
        serve(manifestJson(3, ids: ids));
        expect(
          await source(bundledIds: tenIds).fetchNewer(local),
          isNull,
          reason: '$ids',
        );
      }
      expect(await cache.exists(), isFalse);
      // Dropping one of ten is still fine.
      serve(manifestJson(3, ids: tenIds.skip(1).toList()));
      expect((await source(bundledIds: tenIds).fetchNewer(local))?.version, 3);
    },
  );

  test('a cached copy that fails the checks is ignored', () async {
    for (final json in [
      manifestJson(5, ids: const []),
      manifestJson(5, ids: tenIds.skip(2).toList()),
      manifestJson(5, ids: tenIds, minAppVersion: '2.0.0'),
    ]) {
      await cache.write(json);
      expect(
        (await source(bundledIds: tenIds).loadLocal()).version,
        2,
        reason: '$json',
      );
    }
    await cache.write(manifestJson(5, ids: tenIds.skip(1).toList()));
    expect((await source(bundledIds: tenIds).loadLocal()).version, 5);
  });

  test('offline start uses the cached copy and stays on it', () async {
    await cache.write(manifestJson(5));
    cdn.offline = true;
    final local = await source().loadLocal();
    expect(local.version, 5);
    expect(await source().fetchNewer(local), isNull);
    expect((await cache.read() as Map)['version'], 5);
  });

  test('an older or broken cached copy loses to the bundled one', () async {
    await cache.write(manifestJson(1));
    expect((await source().loadLocal()).version, 2);
    File('${dir.path}/cdn_manifest.json').writeAsStringSync('{broken');
    expect((await source().loadLocal()).version, 2);
  });

  test('without a CDN address nothing is fetched', () async {
    serve(manifestJson(3));
    final local = await source(baseUrl: '').loadLocal();
    expect(await source(baseUrl: '').fetchNewer(local), isNull);
    expect(cdn.requests, isEmpty);
  });

  test('the catalog switches to the CDN manifest when it arrives', () async {
    serve(manifestJson(4));
    final container = ProviderContainer(
      overrides: [manifestSourceProvider.overrideWithValue(source())],
    );
    addTearDown(container.dispose);
    final versions = <int>[];
    container.listen(
      manifestProvider,
      (_, next) => next.whenData((m) => versions.add(m.version)),
    );
    await container.read(remoteManifestProvider.future);
    expect((await container.read(manifestProvider.future)).version, 4);
    expect(versions, [2, 4]);
  });

  test('versions compare number by number', () {
    expect(compareVersions('1.10.0', '1.9.2'), 1);
    expect(compareVersions('1.0', '1.0.0+7'), 0);
    expect(compareVersions('1.0.0', '1.0.1'), -1);
  });
}
