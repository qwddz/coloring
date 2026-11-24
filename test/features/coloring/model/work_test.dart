import 'dart:convert';

import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 18, 10);
  DateTime clock() => t0;

  Map<String, Object?> validJson() => {
    'v': 1,
    'id': 'home_fox_cocoa-1763450000000',
    'pictureId': 'home_fox_cocoa',
    'mode': 'numbers',
    'colors': [0, 4294901760, 0, base],
    'modified': '2026-11-18T10:00:00.000Z',
    'completed': false,
    'completedAt': null,
  };

  test('create uses the injected clock for id and time', () {
    final w = Work.create(pictureId: 'fox', regionCount: 5, now: clock);
    expect(w.id, 'fox-${t0.millisecondsSinceEpoch}');
    expect(w.pictureId, 'fox');
    expect(w.mode, ColoringMode.free, reason: 'D4 default');
    expect(w.colors, List.filled(6, 0));
    expect(w.modified, t0);
    expect(w.completed, isFalse);
    expect(w.completedAt, isNull);
  });

  test('JSON round trip through a string', () {
    final w = Work.fromJson(validJson())!;
    final back = Work.fromJson(jsonDecode(jsonEncode(w.toJson())))!;
    expect(back.id, w.id);
    expect(back.pictureId, 'home_fox_cocoa');
    expect(back.mode, ColoringMode.numbers);
    expect(back.colors, [0, 0xFFFF0000, 0, base]);
    expect(back.modified, t0);
    expect(back.completed, isFalse);
    expect(back.completedAt, isNull);
    expect(w.toJson(), validJson());
  });

  test('completed works keep completedAt', () {
    final json = validJson()
      ..['completed'] = true
      ..['completedAt'] = '2026-11-18T11:00:00.000Z';
    final w = Work.fromJson(json)!;
    expect(w.completed, isTrue);
    expect(w.completedAt, DateTime.utc(2026, 11, 18, 11));
    expect(
      Work.fromJson(jsonDecode(jsonEncode(w.toJson())))!.completedAt,
      w.completedAt,
    );
  });

  test('another version gives null', () {
    expect(Work.fromJson(validJson()..['v'] = 2), isNull);
    expect(Work.fromJson(validJson()..['v'] = 0), isNull);
    expect(Work.fromJson(validJson()..remove('v')), isNull);
  });

  test('malformed data gives null', () {
    expect(Work.fromJson(null), isNull);
    expect(Work.fromJson('x'), isNull);
    expect(Work.fromJson(validJson()..['mode'] = 'paint'), isNull);
    expect(Work.fromJson(validJson()..['id'] = ''), isNull);
    expect(Work.fromJson(validJson()..['pictureId'] = 3), isNull);
    expect(Work.fromJson(validJson()..['colors'] = 'red'), isNull);
    expect(Work.fromJson(validJson()..['colors'] = [0, 'red']), isNull);
    expect(Work.fromJson(validJson()..['colors'] = [0, -1]), isNull);
    expect(Work.fromJson(validJson()..['colors'] = [0, 0x00FF0000]), isNull);
    expect(Work.fromJson(validJson()..['modified'] = 'yesterday'), isNull);
    expect(Work.fromJson(validJson()..['completed'] = 'no'), isNull);
    expect(Work.fromJson(validJson()..['completedAt'] = 'soon'), isNull);
  });

  test('added regions keep the colors and reset completion', () {
    final w = Work.fromJson(
      validJson()
        ..['completed'] = true
        ..['completedAt'] = '2026-11-18T11:00:00.000Z',
    )!;
    expect(identical(w.fitTo(3), w), isTrue);
    final fitted = w.fitTo(5);
    expect(fitted.colors, [...w.colors, 0, 0]);
    expect(fitted.mode, ColoringMode.numbers);
    expect(fitted.completed, isFalse);
    expect(fitted.completedAt, isNull);
    expect(fitted.id, w.id);
  });

  test('fewer regions reset the colors', () {
    final w = Work.fromJson(validJson())!;
    final fitted = w.fitTo(2);
    expect(fitted.colors, List.filled(3, 0));
    expect(fitted.completed, isFalse);
    expect(fitted.id, w.id);
  });

  test('toFillState restores colors and flags a mismatch', () {
    final w = Work.fromJson(validJson())!;
    expect(w.toFillState(3).colorOf(3), base);
    expect(w.toFillState(3).wasReset, isFalse);
    expect(w.toFillState(4).wasReset, isTrue);
  });

  test('withSession copies colors, mode and completion', () {
    var now = t0;
    DateTime tick() => now;
    final work = Work.create(pictureId: 'fixture', regionCount: 5, now: tick);
    final s = fixtureSession(mode: ColoringMode.magic);
    tapRegion(s, 1);

    now = t0.add(const Duration(minutes: 1));
    final saved = work.withSession(s, now: tick);
    expect(saved.id, work.id);
    expect(saved.mode, ColoringMode.magic);
    expect(saved.colors[1], red);
    expect(saved.modified, now);
    expect(saved.completed, isFalse);
    expect(saved.completedAt, isNull);

    for (final id in [2, 3, 4, 5]) {
      tapRegion(s, id);
    }
    now = t0.add(const Duration(minutes: 2));
    final done = saved.withSession(s, now: tick);
    expect(done.completed, isTrue);
    expect(done.completedAt, now);

    // The colors are a snapshot, and completedAt keeps the first time.
    s.clearAll();
    expect(done.colors[1], red);
    now = t0.add(const Duration(minutes: 3));
    final later = done.withSession(s, now: tick);
    expect(later.completed, isTrue);
    expect(later.completedAt, t0.add(const Duration(minutes: 2)));
  });
}
