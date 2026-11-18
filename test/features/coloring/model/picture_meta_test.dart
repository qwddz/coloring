import 'dart:convert';
import 'dart:io';

import 'package:coloring/features/coloring/model/picture_meta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('PictureMeta.fromJson', () {
    test('parses the real home_fox_cocoa regions.json', () {
      final json = jsonDecode(
        File('assets/coloring/free/home_fox_cocoa/regions.json')
            .readAsStringSync(),
      );
      final meta = PictureMeta.fromJson(json);

      expect(meta.width, 2048);
      expect(meta.height, 1536);
      expect(meta.level, 'simple');
      expect(meta.regionCount, 141);
      expect(meta.palette, hasLength(10));
      expect(meta.backgroundId, 137);
      expect(meta.palette.first, 0xFFF7EACE);
      for (var id = 1; id <= meta.regionCount; id++) {
        expect(meta.region(id).id, id);
      }
      final r1 = meta.region(1);
      expect(r1.paletteIndex, 7);
      expect(r1.number, 8);
      expect(r1.color, 0xFFBE4037);
      expect(r1.area, 1570);
      expect([r1.bboxX, r1.bboxY, r1.bboxWidth, r1.bboxHeight], [0, 0, 63, 28]);
      expect([r1.labelX, r1.labelY, r1.labelRadius], [50.0, 12.0, 13.0]);
      expect(meta.correctColorOf(1), meta.palette[7]);
    });

    test('accepts regions listed out of order', () {
      final json = fixtureJson();
      json['regions'] = (json['regions']! as List).reversed.toList();
      final meta = PictureMeta.fromJson(json);
      expect([for (final r in meta.regions) r.id], [1, 2, 3, 4, 5]);
    });

    test('rejects non-contiguous ids', () {
      final json = fixtureJson();
      ((json['regions']! as List).last as Map)['id'] = 7;
      expect(() => PictureMeta.fromJson(json), throwsFormatException);
    });

    test('rejects duplicate ids', () {
      final json = fixtureJson();
      ((json['regions']! as List).last as Map)['id'] = 1;
      expect(() => PictureMeta.fromJson(json), throwsFormatException);
    });

    test('rejects a bad hex color in the palette or a region', () {
      final json = fixtureJson();
      json['palette'] = ['#ff0000', '#00ff0', '#0000ff'];
      expect(() => PictureMeta.fromJson(json), throwsFormatException);

      final json2 = fixtureJson();
      ((json2['regions']! as List).first as Map)['color'] = 'red';
      expect(() => PictureMeta.fromJson(json2), throwsFormatException);
    });

    test('rejects a palette index out of range', () {
      final json = fixtureJson();
      ((json['regions']! as List).first as Map)['palette'] = 3;
      expect(() => PictureMeta.fromJson(json), throwsFormatException);

      final json2 = fixtureJson();
      ((json2['regions']! as List).first as Map)['palette'] = -1;
      expect(() => PictureMeta.fromJson(json2), throwsFormatException);
    });

    test('rejects a non-positive size and a non-object', () {
      final json = fixtureJson()..['width'] = 0;
      expect(() => PictureMeta.fromJson(json), throwsFormatException);
      final json2 = fixtureJson()..['height'] = '1536';
      expect(() => PictureMeta.fromJson(json2), throwsFormatException);
      expect(() => PictureMeta.fromJson(null), throwsFormatException);
      expect(() => PictureMeta.fromJson([1]), throwsFormatException);
    });

    test('rejects a side over 4096', () {
      expect(PictureMeta.fromJson(fixtureJson()..['width'] = 4096).width, 4096);
      final json = fixtureJson()..['width'] = 4097;
      expect(() => PictureMeta.fromJson(json), throwsFormatException);
      final json2 = fixtureJson()..['height'] = 1e9;
      expect(() => PictureMeta.fromJson(json2), throwsFormatException);
    });

    test('rejects an empty palette or one over 256 colors', () {
      final json = fixtureJson()..['palette'] = <String>[];
      expect(() => PictureMeta.fromJson(json), throwsFormatException);
      final json2 = fixtureJson()..['palette'] = List.filled(257, '#ff0000');
      expect(() => PictureMeta.fromJson(json2), throwsFormatException);
      final json3 = fixtureJson()..['palette'] = List.filled(256, '#ff0000');
      expect(PictureMeta.fromJson(json3).palette, hasLength(256));
    });

    test('rejects non-finite region numbers', () {
      // jsonDecode turns 1e400 into infinity.
      final huge = jsonDecode('1e400') as double;
      for (final edit in <void Function(Map<Object?, Object?>)>[
        (r) => r['label'] = [huge, 1.0],
        (r) => r['label'] = [1.0, double.nan],
        (r) => r['label_radius'] = huge,
        (r) => r['area'] = huge,
        (r) => r['bbox'] = [0, 0, huge, 1],
      ]) {
        final json = fixtureJson();
        edit((json['regions']! as List).first as Map<Object?, Object?>);
        expect(() => PictureMeta.fromJson(json), throwsFormatException);
      }
    });

    test('rejects a bbox or label outside the image', () {
      for (final edit in <void Function(Map<Object?, Object?>)>[
        (r) => r['bbox'] = [-1, 0, 1, 1],
        (r) => r['bbox'] = [0, 0, -1, 1],
        (r) => r['bbox'] = [10, 0, 7, 1], // 10 + 7 > 16
        (r) => r['bbox'] = [0, 6, 1, 7], // 6 + 7 > 12
        (r) => r['label'] = [-0.5, 1.0],
        (r) => r['label'] = [16.5, 1.0],
        (r) => r['label'] = [1.0, 12.5],
      ]) {
        final json = fixtureJson();
        edit((json['regions']! as List).first as Map<Object?, Object?>);
        expect(() => PictureMeta.fromJson(json), throwsFormatException);
      }
      final edge = fixtureJson();
      ((edge['regions']! as List).first as Map)
        ..['bbox'] = [0, 0, 16, 12]
        ..['label'] = [16.0, 12.0];
      expect(() => PictureMeta.fromJson(edge), returnsNormally);
    });

    test('rejects a label radius that is not positive', () {
      for (final radius in [0, -1.5]) {
        final json = fixtureJson();
        ((json['regions']! as List).first as Map)['label_radius'] = radius;
        expect(() => PictureMeta.fromJson(json), throwsFormatException);
      }
    });

    test('rejects a background id outside 1..N', () {
      final json = fixtureJson()..['background'] = 6;
      expect(() => PictureMeta.fromJson(json), throwsFormatException);
    });
  });

  test('parseHexColor gives opaque ARGB', () {
    expect(parseHexColor('#be4037'), 0xFFBE4037);
    expect(parseHexColor('#FFFFFF'), 0xFFFFFFFF);
    expect(() => parseHexColor('be4037'), throwsFormatException);
    expect(() => parseHexColor('#be40378'), throwsFormatException);
    expect(() => parseHexColor(0xbe4037), throwsFormatException);
  });
}
