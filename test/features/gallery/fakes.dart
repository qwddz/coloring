import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/features/gallery/data/gallery_backend.dart';
import 'package:coloring/features/gallery/data/share_backend.dart';

class FakeGalleryBackend implements GalleryBackend {
  FakeGalleryBackend([this.result = GallerySaveResult.saved]);

  GallerySaveResult result;
  final List<Uint8List> savedBytes = [];
  final List<String> savedNames = [];

  /// The album the real backend saves to.
  String get album => galleryAlbum;

  @override
  Future<GallerySaveResult> savePng(
    Uint8List bytes, {
    required String name,
  }) async {
    savedBytes.add(bytes);
    savedNames.add(name);
    return result;
  }
}

/// Records each shared file and its bytes at the moment it was shared (the
/// exporter deletes the file once the sheet returns).
class FakeShareBackend implements ShareBackend {
  final List<File> shared = [];
  final List<Uint8List> sharedBytes = [];

  @override
  Future<void> sharePng(File file) async {
    shared.add(file);
    sharedBytes.add(await file.readAsBytes());
  }
}
