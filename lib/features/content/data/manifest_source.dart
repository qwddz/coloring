import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/json_file_store.dart';
import '../../catalog/domain/content_manifest.dart';
import '../content_config.dart';

/// Picks the content manifest: the bundled one, the CDN copy saved on disk,
/// or a newer one fetched from the CDN.
class ManifestSource {
  ManifestSource({
    required this._loadBundled,
    required this._cache,
    required this._dio,
    required this._cdnBaseUrl,
    required this._appVersion,
  });

  final Future<String> Function() _loadBundled;
  final JsonFileStore _cache;
  final Dio _dio;
  final String _cdnBaseUrl;
  final Future<String> Function() _appVersion;

  /// The newer of the bundled manifest and the cached CDN copy. A cached
  /// copy that no longer parses or fails [_isSane] is ignored.
  Future<ContentManifest> loadLocal() async {
    final bundled = ContentManifest.fromJson(jsonDecode(await _loadBundled()));
    final cached = _tryParse(await _cache.read());
    if (cached == null || cached.version <= bundled.version) return bundled;
    try {
      return await _isSane(cached, bundled) ? cached : bundled;
    } on Object {
      return bundled;
    }
  }

  /// Fetches `<base>/manifest.json` and returns it when it is newer than
  /// [current] and passes [_isSane]; it is also saved to disk.
  /// Null when the CDN is off, unreachable or has nothing better.
  Future<ContentManifest?> fetchNewer(ContentManifest current) async {
    final uri = resolveCdnUrl(_cdnBaseUrl, 'manifest.json');
    if (uri == null) return null;
    try {
      final response = await _dio.getUri<String>(
        uri,
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(response.data!);
      final fetched = _tryParse(json);
      if (fetched == null || fetched.version <= current.version) return null;
      if (!await _isSane(fetched, current)) return null;
      await _cache.write(json);
      return fetched;
    } on Object {
      return null;
    }
  }

  /// Guards against a broken upload replacing the catalog: [candidate] must
  /// be supported by this app version, have pictures and keep at least 90% of
  /// the picture ids of [current].
  Future<bool> _isSane(
    ContentManifest candidate,
    ContentManifest current,
  ) async {
    if (compareVersions(candidate.minAppVersion, await _appVersion()) > 0) {
      return false;
    }
    final ids = {for (final picture in candidate.pictures) picture.id};
    if (ids.isEmpty) return false;
    final currentIds = current.pictures.map((p) => p.id).toSet();
    final dropped = currentIds.difference(ids).length;
    return dropped * 10 <= currentIds.length;
  }

  static ContentManifest? _tryParse(Object? json) {
    if (json == null) return null;
    try {
      return ContentManifest.fromJson(json);
    } on Object {
      return null;
    }
  }
}

final manifestSourceProvider = Provider<ManifestSource>(
  (ref) => ManifestSource(
    loadBundled: () => rootBundle.loadString('assets/manifest.json'),
    cache: JsonFileStore(
      ref.watch(contentDirectoryProvider),
      'cdn_manifest.json',
    ),
    dio: ref.watch(dioProvider),
    cdnBaseUrl: ref.watch(cdnBaseUrlProvider),
    appVersion: () => ref.read(appVersionProvider.future),
  ),
);

/// Manifest available without network: bundled or cached from the CDN.
final localManifestProvider = FutureProvider<ContentManifest>(
  (ref) => ref.watch(manifestSourceProvider).loadLocal(),
);

/// Newer manifest from the CDN, fetched once in the background.
final remoteManifestProvider = FutureProvider<ContentManifest?>((ref) async {
  final local = await ref.watch(localManifestProvider.future);
  return ref.watch(manifestSourceProvider).fetchNewer(local);
});
