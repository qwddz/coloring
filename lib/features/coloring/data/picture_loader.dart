import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/domain/content_manifest.dart';
import '../../content/data/picture_store.dart';
import '../model/picture_meta.dart';
import '../model/region_map.dart';

/// One opened picture (spec §7): the GPU images, the region map and the
/// metadata.
///
/// The loader's caller owns the images and calls [dispose] when done.
/// Anyone else who keeps an image (the game, a renderer) takes its own
/// `image.clone()` and disposes that clone, never these handles.
class LoadedPicture {
  LoadedPicture({
    required this.regionsImage,
    required this.linesImage,
    required this.map,
    required this.meta,
  });

  /// `regions.png`, sampled by the fill shader.
  final ui.Image regionsImage;

  /// `lines.png`, drawn on top of the fills.
  final ui.Image linesImage;

  final RegionMap map;
  final PictureMeta meta;

  void dispose() {
    regionsImage.dispose();
    linesImage.dispose();
  }
}

/// Opens pictures: finds the layers through [PictureStore], then decodes
/// them with [decode].
class PictureLoader {
  const PictureLoader(this._store);

  final PictureStore _store;

  /// Throws [PictureLoadException] when the layers cannot be fetched and
  /// [FormatException] when they do not fit together.
  Future<LoadedPicture> load(
    PictureEntry entry, {
    void Function(double progress)? onProgress,
  }) async => decode(await _store.load(entry, onProgress: onProgress));

  /// Decodes `regions.png`, `lines.png` and `regions.json` with `dart:ui`
  /// and checks that their sizes and region count agree. The PNG headers
  /// are checked against `regions.json` before decoding, so a layer of the
  /// wrong (possibly huge) size is never decoded.
  static Future<LoadedPicture> decode(PictureFiles files) async {
    final (regionsBytes, linesBytes, jsonBytes) = await (
      files.read(PictureLayers.regions),
      files.read(PictureLayers.lines),
      files.read(PictureLayers.regionsJson),
    ).wait;
    final meta = PictureMeta.fromJson(jsonDecode(utf8.decode(jsonBytes)));
    for (final (name, bytes) in [
      ('regions', regionsBytes),
      ('lines', linesBytes),
    ]) {
      final (width, height) = pngSize(bytes, '$name.png');
      if (width != meta.width || height != meta.height) {
        throw FormatException(
          '$name.png is $width x $height, regions.json says '
          '${meta.width} x ${meta.height}',
        );
      }
    }

    ui.Image? regions;
    ui.Image? lines;
    try {
      regions = await _decodeImage(regionsBytes);
      lines = await _decodeImage(linesBytes);
      for (final (name, image) in [('regions', regions), ('lines', lines)]) {
        if (image.width != meta.width || image.height != meta.height) {
          throw FormatException(
            '$name.png is ${image.width} x ${image.height}, regions.json '
            'says ${meta.width} x ${meta.height}',
          );
        }
      }
      final map = await _regionMap(regions);
      map.checkMatches(meta);
      return LoadedPicture(
        regionsImage: regions,
        linesImage: lines,
        map: map,
        meta: meta,
      );
    } on Object {
      regions?.dispose();
      lines?.dispose();
      rethrow;
    }
  }

  /// Width and height from the IHDR chunk of a PNG (bytes 16–24, big
  /// endian). Throws [FormatException] when [bytes] is not a PNG.
  static (int, int) pngSize(Uint8List bytes, String name) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13];
    const ihdr = [73, 72, 68, 82];
    var ok = bytes.length >= 24;
    for (var i = 0; ok && i < signature.length; i++) {
      ok = bytes[i] == signature[i];
    }
    for (var i = 0; ok && i < ihdr.length; i++) {
      ok = bytes[12 + i] == ihdr[i];
    }
    if (!ok) throw FormatException('$name is not a PNG');
    final data = ByteData.sublistView(bytes, 16, 24);
    return (data.getUint32(0), data.getUint32(4));
  }

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// The 12 MiB RGBA copy lives only inside this call; the map keeps its
  /// own 6 MiB of ids. `regions.png` is opaque RGB, so straight and
  /// premultiplied alpha give the same R and G.
  static Future<RegionMap> _regionMap(ui.Image regions) async {
    final data = await regions.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) {
      throw const FormatException('regions.png could not be read');
    }
    return RegionMap.fromRgba(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      regions.width,
      regions.height,
    );
  }
}

final pictureLoaderProvider = Provider<PictureLoader>(
  (ref) => PictureLoader(ref.watch(pictureStoreProvider)),
);
