import 'dart:convert';
import 'dart:io';

import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/content/data/picture_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = 'assets/coloring/free';

/// Ids of the bundled pictures, read from the asset folders.
List<String> _pictureIds() {
  final ids = [
    for (final dir in Directory(_root).listSync().whereType<Directory>())
      dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ]..sort();
  return ids;
}

/// Bundled files with one layer replaced.
class _PatchedFiles implements PictureFiles {
  _PatchedFiles(
    this._inner,
    this._bytes, [
    this._name = PictureLayers.regionsJson,
  ]);

  final PictureFiles _inner;
  final Uint8List _bytes;
  final String _name;

  @override
  Future<Uint8List> read(String name) async =>
      name == _name ? _bytes : _inner.read(name);
}

/// [png] with the IHDR width and height replaced (the CRC is left stale:
/// the header check runs before any decoder sees it).
Uint8List _withIhdrSize(Uint8List png, int width, int height) {
  final out = Uint8List.fromList(png);
  ByteData.sublistView(out)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return out;
}

/// Chunk types of a PNG file, in order.
List<String> _pngChunks(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) throw const FormatException('not a PNG');
  }
  final data = ByteData.sublistView(bytes);
  final chunks = <String>[];
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final length = data.getUint32(offset);
    chunks.add(ascii.decode(bytes.sublist(offset + 4, offset + 8)));
    offset += 12 + length;
  }
  return chunks;
}

void main() {
  final ids = _pictureIds();

  test('finds all 10 bundled pictures', () {
    expect(ids, hasLength(10));
  });

  testWidgets('loads every bundled picture', (tester) async {
    await tester.runAsync(() async {
      for (final id in ids) {
        final picture = await PictureLoader.decode(
          BundledPictureFiles(rootBundle, '$_root/$id/'),
        );
        try {
          expect(picture.regionsImage.width, 2048, reason: id);
          expect(picture.regionsImage.height, 1536, reason: id);
          expect(picture.linesImage.width, 2048, reason: id);
          expect(picture.linesImage.height, 1536, reason: id);
          expect(picture.map.maxId, picture.meta.regionCount, reason: id);
          for (final region in picture.meta.regions) {
            expect(
              picture.map.idAt(region.labelX.floor(), region.labelY.floor()),
              region.id,
              reason: '$id region ${region.id}',
            );
          }
        } finally {
          picture.dispose();
        }
      }
    });
  });

  testWidgets('rejects a map whose max id differs from the region count', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final files = BundledPictureFiles(rootBundle, '$_root/${ids.first}/');
      final json = jsonDecode(
        utf8.decode(await files.read(PictureLayers.regionsJson)),
      ) as Map<String, Object?>;
      final regions = (json['regions']! as List).toList()..removeLast();
      final patched = {...json, 'regions': regions};
      await expectLater(
        PictureLoader.decode(
          _PatchedFiles(files, utf8.encode(jsonEncode(patched))),
        ),
        throwsFormatException,
      );
    });
  });

  group('PNG header check', () {
    test('reads the IHDR size and refuses a non-PNG', () {
      final png = File('$_root/${ids.first}/${PictureLayers.regions}')
          .readAsBytesSync();
      expect(PictureLoader.pngSize(png, 'regions.png'), (2048, 1536));
      expect(
        () => PictureLoader.pngSize(Uint8List(24), 'regions.png'),
        throwsFormatException,
      );
      expect(
        () => PictureLoader.pngSize(png.sublist(0, 20), 'regions.png'),
        throwsFormatException,
      );
    });

    for (final layer in [PictureLayers.regions, PictureLayers.lines]) {
      testWidgets('a $layer of another size fails before decoding', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final files = BundledPictureFiles(rootBundle, '$_root/${ids.first}/');
          // 60000 x 60000 would be ~14 GB decoded; the header check must
          // refuse it without ever reaching the codec.
          final huge = _withIhdrSize(await files.read(layer), 60000, 60000);
          await expectLater(
            PictureLoader.decode(_PatchedFiles(files, huge, layer)),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                contains('60000 x 60000'),
              ),
            ),
          );
        });
      });
    }
  });

  test('bundled regions.png files carry no color-management chunks', () {
    for (final id in ids) {
      final chunks = _pngChunks(
        File('$_root/$id/${PictureLayers.regions}').readAsBytesSync(),
      );
      expect(chunks.first, 'IHDR', reason: id);
      expect(chunks.last, 'IEND', reason: id);
      for (final banned in ['gAMA', 'iCCP', 'sRGB', 'cHRM']) {
        expect(chunks, isNot(contains(banned)), reason: '$id has $banned');
      }
    }
  });
}
