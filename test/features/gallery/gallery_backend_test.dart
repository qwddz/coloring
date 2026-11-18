import 'package:coloring/features/gallery/data/gallery_backend.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';

class _FakeGalApi implements GalApi {
  _FakeGalApi({this.hasPermissionValue = true, this.requestResult = true});

  final bool hasPermissionValue;
  final bool requestResult;
  Object? putError;
  final List<bool> hasPermissionCalls = [];
  final List<bool> requestCalls = [];
  final List<({Uint8List bytes, String album, String name})> puts = [];

  @override
  Future<bool> hasPermission({required bool toAlbum}) async {
    hasPermissionCalls.add(toAlbum);
    return hasPermissionValue;
  }

  @override
  Future<bool> requestPermission({required bool toAlbum}) async {
    requestCalls.add(toAlbum);
    return requestResult;
  }

  @override
  Future<void> putImageBytes(
    Uint8List bytes, {
    required String album,
    required String name,
  }) async {
    puts.add((bytes: bytes, album: album, name: name));
    final error = putError;
    if (error != null) throw error;
  }
}

GalException _galError(GalExceptionType type) => GalException(
  type: type,
  platformException: PlatformException(code: type.code),
  stackTrace: StackTrace.empty,
);

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  test('access already granted: saves to the album without asking', () async {
    final api = _FakeGalApi();
    final result = await GalGalleryBackend(api).savePng(bytes, name: 'pic');

    expect(result, GallerySaveResult.saved);
    expect(api.hasPermissionCalls, [true]);
    expect(api.requestCalls, isEmpty);
    expect(api.puts.single.bytes, bytes);
    expect(api.puts.single.album, 'Animosaic Colors');
    expect(api.puts.single.name, 'pic');
  });

  test('access missing: asks once, then saves when granted', () async {
    final api = _FakeGalApi(hasPermissionValue: false);
    final result = await GalGalleryBackend(api).savePng(bytes, name: 'pic');

    expect(result, GallerySaveResult.saved);
    expect(api.requestCalls, [true]);
    expect(api.puts, hasLength(1));
  });

  test('access refused: denied and nothing is written', () async {
    final api = _FakeGalApi(hasPermissionValue: false, requestResult: false);
    final result = await GalGalleryBackend(api).savePng(bytes, name: 'pic');

    expect(result, GallerySaveResult.denied);
    expect(api.puts, isEmpty);
  });

  test('GalException permissionDenied maps to denied', () async {
    final api = _FakeGalApi()
      ..putError = _galError(GalExceptionType.permissionDenied);
    final result = await GalGalleryBackend(api).savePng(bytes, name: 'pic');

    expect(result, GallerySaveResult.denied);
  });

  test('other GalException types map to failed', () async {
    for (final type in GalExceptionType.values) {
      if (type == GalExceptionType.permissionDenied) continue;
      final api = _FakeGalApi()..putError = _galError(type);
      final result = await GalGalleryBackend(api).savePng(bytes, name: 'pic');

      expect(result, GallerySaveResult.failed, reason: type.name);
    }
  });

  test('a non-gal exception maps to failed', () async {
    final api = _FakeGalApi()..putError = const FormatException('boom');
    final result = await GalGalleryBackend(api).savePng(bytes, name: 'pic');

    expect(result, GallerySaveResult.failed);
  });
}
