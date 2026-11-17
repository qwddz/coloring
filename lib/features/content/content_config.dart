import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// CDN base URL from `--dart-define=CDN_BASE_URL=…`. Empty turns the CDN off:
/// the app then runs on the bundled manifest and pictures only. Release
/// builds refuse to start without it, see [checkCdnConfigured].
const cdnBaseUrlFromEnvironment = String.fromEnvironment('CDN_BASE_URL');

final cdnBaseUrlProvider = Provider<String>((ref) => cdnBaseUrlFromEnvironment);

/// Throws in release builds made without `CDN_BASE_URL`: every paid picture
/// would otherwise fail to download with a misleading "no internet" message.
void checkCdnConfigured({required bool release, required String baseUrl}) {
  if (release && baseUrl.isEmpty) {
    throw StateError(
      'CDN_BASE_URL is empty. Build with --dart-define=CDN_BASE_URL=<url>.',
    );
  }
}

/// Absolute address for a manifest [url]: absolute `http(s)` URLs are kept,
/// relative ones are joined to [baseUrl]. Null when the CDN is off or either
/// address is malformed.
Uri? resolveCdnUrl(String baseUrl, String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.hasScheme) return uri;
  if (baseUrl.isEmpty) return null;
  final base = Uri.tryParse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
  return base?.resolve(url.startsWith('/') ? url.substring(1) : url);
}

/// Asset paths bundled with this build, like `assets/coloring/free/home_fox_cocoa/thumb.webp`.
/// The manifest may name assets a slimmer build does not ship.
Future<Set<String>> loadBundledAssets(AssetBundle bundle) async =>
    (await AssetManifest.loadFromAssetBundle(bundle)).listAssets().toSet();

final bundledAssetsProvider = FutureProvider<Set<String>>(
  (ref) => loadBundledAssets(rootBundle),
);

final dioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  ),
);

/// Where the CDN manifest copy and downloaded pictures are kept.
final contentDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => getApplicationSupportDirectory,
);

/// Version name of the installed app, like `1.0.0`.
final appVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// Compares dotted versions number by number: `1.10.0` is newer than `1.9.2`.
/// A build suffix (`+3`) and missing parts are ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
    for (final part in v.split('+').first.split('.'))
      int.tryParse(part.trim()) ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final diff = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (diff != 0) return diff.sign;
  }
  return 0;
}
