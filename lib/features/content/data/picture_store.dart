import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/domain/content_manifest.dart';
import '../content_config.dart';

/// Layer files of one picture, all 2048 × 1536 (`PLAN.md`, «Данные одной
/// картинки»). A bundled picture keeps them in its asset folder, a paid one
/// ships them in one zip.
abstract final class PictureLayers {
  static const lines = 'lines.png';
  static const regions = 'regions.png';
  static const colored = 'colored.webp';
  static const regionsJson = 'regions.json';
  static const thumb = 'thumb.webp';

  /// A downloaded zip without one of these is treated as corrupt.
  static const required = [lines, regions, colored, regionsJson];
}

/// Reads the layer files of one picture by name, like [PictureLayers.lines].
abstract interface class PictureFiles {
  Future<Uint8List> read(String name);
}

/// Layers bundled with the app, in an asset folder ending with `/`.
class BundledPictureFiles implements PictureFiles {
  const BundledPictureFiles(this._bundle, this.folder);

  final AssetBundle _bundle;
  final String folder;

  @override
  Future<Uint8List> read(String name) async {
    final data = await _bundle.load('$folder$name');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

/// Layers unpacked from a downloaded zip.
class CachedPictureFiles implements PictureFiles {
  const CachedPictureFiles(this.directory);

  final Directory directory;

  @override
  Future<Uint8List> read(String name) =>
      File('${directory.path}/$name').readAsBytes();
}

enum PictureLoadFailure {
  /// The CDN could not be reached and there is no cached copy.
  network,

  /// The CDN answered with an error (404, 403, 5xx), or this build has
  /// neither the bundled picture nor a CDN address for it.
  unavailable,

  /// The downloaded zip does not match its checksum, does not unpack or
  /// lacks a layer.
  corrupt,
}

class PictureLoadException implements Exception {
  const PictureLoadException(this.failure, [this.cause]);

  final PictureLoadFailure failure;
  final Object? cause;

  @override
  String toString() => 'PictureLoadException($failure, $cause)';
}

/// Picture layers: bundled assets as they are, CDN pictures downloaded once
/// as a zip, checked by sha256 and unpacked into a disk cache. The unpacked
/// folder remembers the checksum of its zip, so a picture updated in the
/// manifest is downloaded again.
class PictureStore {
  PictureStore({
    required this._dio,
    required this._directory,
    required this._cdnBaseUrl,
    AssetBundle? bundle,
    Future<Set<String>> Function()? bundledAssets,
  }) : _bundle = bundle ?? rootBundle,
       _loadBundledAssets = bundledAssets;

  /// Written last into an unpacked folder: holds the zip checksum.
  static const _checksumFile = '.sha256';

  final Dio _dio;
  final Future<Directory> Function() _directory;
  final String _cdnBaseUrl;
  final AssetBundle _bundle;
  final Future<Set<String>> Function()? _loadBundledAssets;

  /// Asset paths this build ships, loaded once; a failed load is retried
  /// on the next open.
  Future<Set<String>>? _bundledAssets;

  Future<Set<String>> _assetList() => _bundledAssets ??= () async {
    try {
      return await (_loadBundledAssets?.call() ?? loadBundledAssets(_bundle));
    } on Object {
      _bundledAssets = null;
      rethrow;
    }
  }();

  /// The pictures folder, opened once per app start.
  Future<Directory>? _folder;

  /// Loads in progress by picture id and checksum, so two opens of the same
  /// picture share one download.
  final _loads = <String, _Load>{};

  /// [onProgress] gets the downloaded share from 0 to 1; it is not called
  /// for bundled or cached pictures.
  Future<PictureFiles> load(
    PictureEntry entry, {
    void Function(double progress)? onProgress,
  }) async {
    final assetPath = entry.assetPath;
    if (assetPath != null &&
        (await _assetList()).contains('$assetPath${PictureLayers.lines}')) {
      return BundledPictureFiles(_bundle, assetPath);
    }
    if (entry.url == null || entry.sha256 == null) {
      throw const PictureLoadException(PictureLoadFailure.unavailable);
    }
    final key = '${entry.id}:${entry.sha256}';
    final running = _loads[key];
    if (running != null) {
      if (onProgress != null) running.listeners.add(onProgress);
      return running.future;
    }
    final load = _Load();
    if (onProgress != null) load.listeners.add(onProgress);
    _loads[key] = load;
    try {
      return await (load.future = _loadCached(entry, load));
    } finally {
      _loads.remove(key);
    }
  }

  /// Creates the folder and drops `.part` zips and `.tmp` folders left by
  /// downloads that were cut off when the app was killed.
  Future<Directory> _openFolder() async {
    try {
      final folder = Directory('${(await _directory()).path}/pictures');
      await folder.create(recursive: true);
      await for (final item in folder.list()) {
        if (item.path.endsWith('.part') || item.path.endsWith('.tmp')) {
          await item.delete(recursive: true);
        }
      }
      return folder;
    } on Object {
      _folder = null;
      rethrow;
    }
  }

  Future<PictureFiles> _loadCached(PictureEntry entry, _Load load) async {
    final folder = await (_folder ??= _openFolder());
    final target = Directory('${folder.path}/${entry.id}');
    if (await _isComplete(target, entry.sha256!)) {
      return CachedPictureFiles(target);
    }
    final uri = resolveCdnUrl(_cdnBaseUrl, entry.url!);
    if (uri == null) {
      throw const PictureLoadException(PictureLoadFailure.unavailable);
    }
    final zip = File('${target.path}.zip.part');
    final unpacked = Directory('${target.path}.tmp');
    try {
      try {
        await _dio.downloadUri(
          uri,
          zip.path,
          onReceiveProgress: (received, total) {
            final size = total > 0 ? total : entry.bytes ?? 0;
            if (size <= 0) return;
            final progress = (received / size).clamp(0.0, 1.0);
            for (final listener in load.listeners) {
              listener(progress);
            }
          },
        );
      } on DioException catch (e) {
        throw PictureLoadException(
          e.type == DioExceptionType.badResponse
              ? PictureLoadFailure.unavailable
              : PictureLoadFailure.network,
          e,
        );
      }
      final bytes = await zip.readAsBytes();
      if (!_matches(entry, bytes)) {
        throw const PictureLoadException(PictureLoadFailure.corrupt);
      }
      await _unpack(bytes, unpacked);
      await File('${unpacked.path}/$_checksumFile')
          .writeAsString(entry.sha256!.toLowerCase(), flush: true);
      if (await target.exists()) await target.delete(recursive: true);
      await unpacked.rename(target.path);
      return CachedPictureFiles(target);
    } finally {
      for (final leftover in [zip, unpacked]) {
        try {
          if (await leftover.exists()) await leftover.delete(recursive: true);
        } on FileSystemException {
          // Left for the next start's cleanup in [_openFolder].
        }
      }
    }
  }

  /// Unpacks the files of [zip] flat into [into]: folders inside the zip
  /// are ignored, hidden files (`.DS_Store`, `__MACOSX/._x`) skipped.
  static Future<void> _unpack(Uint8List zip, Directory into) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zip, verify: true);
    } on Object catch (e) {
      throw PictureLoadException(PictureLoadFailure.corrupt, e);
    }
    if (await into.exists()) await into.delete(recursive: true);
    await into.create(recursive: true);
    final names = <String>{};
    for (final file in archive.files) {
      if (!file.isFile || file.isSymbolicLink) continue;
      final name = file.name.split('/').last;
      if (name.isEmpty || name.startsWith('.')) continue;
      final data = file.readBytes();
      if (data == null) continue;
      await File('${into.path}/$name').writeAsBytes(data, flush: true);
      names.add(name);
    }
    if (!PictureLayers.required.every(names.contains)) {
      throw const PictureLoadException(PictureLoadFailure.corrupt);
    }
  }

  /// Whether [folder] was fully unpacked from the zip with [sha256].
  static Future<bool> _isComplete(Directory folder, String sha256) async {
    final checksum = File('${folder.path}/$_checksumFile');
    if (!await checksum.exists()) return false;
    if ((await checksum.readAsString()).trim() != sha256.toLowerCase()) {
      return false;
    }
    for (final name in PictureLayers.required) {
      if (!await File('${folder.path}/$name').exists()) return false;
    }
    return true;
  }

  static bool _matches(PictureEntry entry, Uint8List bytes) {
    final size = entry.bytes;
    if (size != null && bytes.length != size) return false;
    return sha256.convert(bytes).toString() == entry.sha256?.toLowerCase();
  }
}

class _Load {
  final listeners = <void Function(double progress)>[];
  late Future<PictureFiles> future;
}

final pictureStoreProvider = Provider<PictureStore>(
  (ref) => PictureStore(
    dio: ref.watch(dioProvider),
    directory: ref.watch(contentDirectoryProvider),
    cdnBaseUrl: ref.watch(cdnBaseUrlProvider),
    bundledAssets: () => ref.read(bundledAssetsProvider.future),
  ),
);

/// Download progress of one picture from 0 to 1, null when not downloading.
class PictureDownloadProgress extends Notifier<double?> {
  PictureDownloadProgress(this.pictureId);

  final String pictureId;

  @override
  double? build() => null;

  /// Whole percents only, so a download rebuilds the screen at most 100 times.
  void report(double? progress) {
    final rounded = progress == null ? null : (progress * 100).floor() / 100;
    if (rounded != state) state = rounded;
  }
}

final pictureDownloadProgressProvider =
    NotifierProvider.family<PictureDownloadProgress, double?, String>(
      PictureDownloadProgress.new,
    );
