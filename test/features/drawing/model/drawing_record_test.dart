import 'dart:convert';

import 'package:coloring/features/drawing/model/drawing_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime.utc(2026, 11, 20, 9);
  final modified = DateTime.utc(2026, 11, 20, 10, 30);
  const id = 'drawing-1763600000000';

  Map<String, Object?> validJson() => {
    'v': 1,
    'id': id,
    'created': '2026-11-20T09:00:00.000Z',
    'modified': '2026-11-20T10:30:00.000Z',
    'width': 2048,
    'height': 1536,
    'raster': '$id.r${modified.millisecondsSinceEpoch}.png',
  };

  test('round trip through JSON text', () {
    final record = DrawingRecord(
      id: id,
      created: created,
      modified: modified,
      width: 2048,
      height: 1536,
      raster: DrawingRecord.rasterName(id, modified),
    );
    final back = DrawingRecord.fromJson(
      jsonDecode(jsonEncode(record.toJson())),
    )!;
    expect(back.id, id);
    expect(back.created, created);
    expect(back.modified, modified);
    expect(back.width, 2048);
    expect(back.height, 1536);
    expect(back.raster, '$id.r${modified.millisecondsSinceEpoch}.png');
    expect(record.toJson(), validJson());
  });

  test('local times are stored as UTC', () {
    final local = DateTime(2026, 11, 20, 12);
    final record = DrawingRecord(
      id: id,
      created: local,
      modified: local,
      width: 1,
      height: 1,
      raster: DrawingRecord.rasterName(id, local),
    );
    final back = DrawingRecord.fromJson(record.toJson())!;
    expect(back.modified.isUtc, isTrue);
    expect(back.modified, local.toUtc());
  });

  test('malformed records are null', () {
    final cases = <String, Object? Function(Map<String, Object?>)>{
      'not a map': (_) => [1, 2],
      'other version': (j) => j..['v'] = 2,
      'missing id': (j) => j..remove('id'),
      'path id': (j) => j..['id'] = '../x',
      'dot id': (j) => j..['id'] = '..',
      'bad created': (j) => j..['created'] = 'yesterday',
      'missing modified': (j) => j..remove('modified'),
      'zero width': (j) => j..['width'] = 0,
      'string height': (j) => j..['height'] = '1536',
      'double width': (j) => j..['width'] = 2048.0,
      'missing raster': (j) => j..remove('raster'),
      'raster of another id': (j) => j..['raster'] = 'drawing-1.r5.png',
      'raster path': (j) => j..['raster'] = '$id.r5/../x.png',
      'raster not png': (j) => j..['raster'] = '$id.r5.jpg',
    };
    for (final entry in cases.entries) {
      expect(
        DrawingRecord.fromJson(entry.value(validJson())),
        isNull,
        reason: entry.key,
      );
    }
    expect(DrawingRecord.fromJson(null), isNull);
    expect(DrawingRecord.fromJson(validJson()), isNotNull);
  });

  test('plain ids', () {
    expect(DrawingRecord.isPlainId('drawing-123-1'), isTrue);
    expect(DrawingRecord.isPlainId('a_b.c'), isTrue);
    for (final bad in ['', '.', '..', 'a/b', r'a\b', 'a b', 'ä']) {
      expect(DrawingRecord.isPlainId(bad), isFalse, reason: bad);
    }
  });

  test('newDrawingId adds a counter within one millisecond', () {
    final t = DateTime.utc(2030, 1, 1, 0, 0, 0, 5);
    final millis = t.millisecondsSinceEpoch;
    expect(newDrawingId(t), 'drawing-$millis');
    expect(newDrawingId(t), 'drawing-$millis-1');
    expect(newDrawingId(t), 'drawing-$millis-2');
    final later = t.add(const Duration(milliseconds: 1));
    expect(newDrawingId(later), 'drawing-${millis + 1}');
  });

  test('newDrawingId never repeats when the clock goes back', () {
    final t = DateTime.utc(2031, 1, 1);
    final ids = {
      newDrawingId(t),
      newDrawingId(t.subtract(const Duration(seconds: 1))),
      newDrawingId(t.subtract(const Duration(seconds: 2))),
    };
    expect(ids, hasLength(3));
    expect(ids.every(DrawingRecord.isPlainId), isTrue);
  });
}
