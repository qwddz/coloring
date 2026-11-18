import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

/// The gallery album that finished works are saved to.
const galleryAlbum = 'Animosaic Colors';

enum GallerySaveResult { saved, denied, failed }

/// Saves a PNG into the device gallery. Tests use a fake.
abstract class GalleryBackend {
  /// [name] has no extension.
  Future<GallerySaveResult> savePng(Uint8List bytes, {required String name});
}

/// The thin seam over the static `Gal` API, so tests never reach a platform
/// channel.
abstract class GalApi {
  Future<bool> hasPermission({required bool toAlbum});
  Future<bool> requestPermission({required bool toAlbum});
  Future<void> putImageBytes(
    Uint8List bytes, {
    required String album,
    required String name,
  });
}

class PluginGalApi implements GalApi {
  const PluginGalApi();

  @override
  Future<bool> hasPermission({required bool toAlbum}) =>
      Gal.hasPermission(toAlbum: toAlbum);

  @override
  Future<bool> requestPermission({required bool toAlbum}) =>
      Gal.requestPermission(toAlbum: toAlbum);

  @override
  Future<void> putImageBytes(
    Uint8List bytes, {
    required String album,
    required String name,
  }) => Gal.putImageBytes(bytes, album: album, name: name);
}

/// Saves through `gal`. Saving to an album needs the legacy storage permission
/// on Android 10 and older (API ≤ 29); `gal` reports access as granted
/// on newer versions, so there is no SDK branching here.
class GalGalleryBackend implements GalleryBackend {
  const GalGalleryBackend([this._api = const PluginGalApi()]);

  final GalApi _api;

  @override
  Future<GallerySaveResult> savePng(
    Uint8List bytes, {
    required String name,
  }) async {
    try {
      if (!await _api.hasPermission(toAlbum: true) &&
          !await _api.requestPermission(toAlbum: true)) {
        return GallerySaveResult.denied;
      }
      await _api.putImageBytes(bytes, album: galleryAlbum, name: name);
      return GallerySaveResult.saved;
    } on GalException catch (e) {
      return e.type == GalExceptionType.permissionDenied
          ? GallerySaveResult.denied
          : GallerySaveResult.failed;
    } on Exception {
      return GallerySaveResult.failed;
    }
  }
}

final galleryBackendProvider = Provider<GalleryBackend>(
  (ref) => const GalGalleryBackend(),
);
