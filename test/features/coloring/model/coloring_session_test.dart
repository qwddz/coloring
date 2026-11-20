import 'dart:typed_data';

import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/coloring_session.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:coloring/features/coloring/model/picture_meta.dart';
import 'package:coloring/features/coloring/model/region_map.dart';
import 'package:coloring/features/coloring/model/undo_history.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Fills every region with its correct color in numbers mode.
void fillAllCorrect(ColoringSession s) {
  for (final id in fixturePaletteIndex.keys) {
    s.selectPaletteIndex(fixturePaletteIndex[id]!);
    tapRegion(s, id);
  }
}

void main() {
  test('rejects a fill state of another picture', () {
    expect(
      () => ColoringSession(
        meta: fixtureMeta(),
        map: fixtureMap(),
        fill: FillState(4),
      ),
      throwsArgumentError,
    );
  });

  group('free mode', () {
    test('a tap fills the selected color with one undo step', () {
      final s = fixtureSession()..selectColor(base);
      final r = tapRegion(s, 3);
      expect(r.outcome, FillOutcome.changed);
      expect(r.regionId, 3);
      expect(r.changes, [const RegionChange(3, 0, base)]);
      expect(r.justCompleted, isFalse);
      expect(s.fill.colorOf(3), base);
      expect(s.canUndo, isTrue);
    });

    test('refilling with the same color makes no undo step', () {
      final s = fixtureSession()..selectColor(base);
      tapRegion(s, 3);
      s.undo();
      expect(s.canUndo, isFalse);
      tapRegion(s, 3);
      final again = tapRegion(s, 3);
      expect(again.outcome, FillOutcome.unchanged);
      expect(again.changes, isEmpty);
      s.undo();
      expect(s.canUndo, isFalse);
      expect(s.fill.colorOf(3), 0);
    });

    test('a tap on a line uses the tolerance; too far is a miss', () {
      final s = fixtureSession()..selectColor(base);
      expect(s.tap(6.5, 2.5, tolerance: 4).regionId, 1);
      final miss = s.tap(6.5, 4.5, tolerance: 1);
      expect(miss.outcome, FillOutcome.miss);
      expect(miss.regionId, 0);
      expect(s.tap(-5, 2, tolerance: 4).outcome, FillOutcome.miss);
    });

    test('the eraser clears a region; erasing empty changes nothing', () {
      final s = fixtureSession()..selectColor(base);
      tapRegion(s, 2);
      s.selectEraser();
      expect(s.tool, ColoringTool.eraser);
      final r = tapRegion(s, 2);
      expect(r.changes, [const RegionChange(2, base, 0)]);
      expect(s.fill.isFilled(2), isFalse);
      expect(tapRegion(s, 2).outcome, FillOutcome.unchanged);
      // Selecting a color goes back to the brush.
      s.selectColor(red);
      expect(s.tool, ColoringTool.brush);
    });

    test('clearAll empties everything in one undoable step', () {
      final s = fixtureSession();
      for (final id in [1, 2, 5]) {
        s.selectColor(base);
        tapRegion(s, id);
      }
      final r = s.clearAll();
      expect(r.changes.map((c) => c.id), [1, 2, 5]);
      expect(s.fill.filledCount, 0);
      final u = s.undo();
      expect(u.changes, hasLength(3));
      expect(s.fill.filledCount, 3);
      expect(s.fill.colorOf(5), base);
      expect(s.clearAll().changes, hasLength(3));
      expect(s.clearAll().outcome, FillOutcome.unchanged);
    });

    test('canFinish flips at exactly 80 %; finish completes once', () {
      final s = fixtureSession()..selectColor(base);
      for (final id in [1, 2, 3]) {
        tapRegion(s, id);
      }
      expect(s.canFinish, isFalse);
      expect(s.finish().justCompleted, isFalse);
      tapRegion(s, 4);
      expect(s.filledFraction, closeTo(0.8, 1e-12));
      expect(s.canFinish, isTrue);
      tapRegion(s, 5);
      expect(s.completed, isFalse, reason: 'free mode never auto-completes');
      expect(s.finish().justCompleted, isTrue);
      expect(s.completed, isTrue);
      expect(s.canFinish, isFalse, reason: 'Done is off once completed');
      expect(s.finish().justCompleted, isFalse);
    });

    test('canFinish is false for a work restored as completed', () {
      final fill = FillState(5);
      for (var id = 1; id <= 5; id++) {
        fill.setColor(id, base);
      }
      final s = ColoringSession(
        meta: fixtureMeta(),
        map: fixtureMap(),
        fill: fill,
        completed: true,
      );
      expect(s.canFinish, isFalse);
    });

    test('long press hint gives the correct color without filling', () {
      final s = fixtureSession()..selectColor(base);
      final (x, y) = fixtureLabels[3]!;
      final hint = s.hintColorAt(x, y, tolerance: 4)!;
      expect(hint.regionId, 3);
      expect(hint.color, blue);
      expect(s.fill.isFilled(3), isFalse);
      expect(s.selectedColor, base);
      expect(s.canUndo, isFalse);
      expect(s.hintColorAt(6.5, 4.5, tolerance: 1), isNull);
      s.setMode(ColoringMode.numbers);
      expect(s.hintColorAt(x, y, tolerance: 4), isNull);
    });

    test('undo with nothing to undo is unchanged', () {
      expect(fixtureSession().undo().outcome, FillOutcome.unchanged);
    });

    test('selectColor rejects a transparent color', () {
      expect(() => fixtureSession().selectColor(0), throwsArgumentError);
      expect(
        () => fixtureSession().selectColor(0x80FF0000),
        throwsArgumentError,
      );
    });
  });

  group('numbers mode', () {
    test('a wrong number is rejected with no change', () {
      final s = fixtureSession(mode: ColoringMode.numbers);
      expect(s.selectedPaletteIndex, 0);
      final r = tapRegion(s, 2); // palette index 1
      expect(r.outcome, FillOutcome.rejected);
      expect(r.regionId, 2);
      expect(r.changes, isEmpty);
      expect(s.fill.isFilled(2), isFalse);
      expect(s.canUndo, isFalse);
    });

    test('a correct fill uses the palette color and hides the number', () {
      final s = fixtureSession(mode: ColoringMode.numbers)
        ..selectPaletteIndex(1);
      expect(s.showsNumberOf(2), isTrue);
      final r = tapRegion(s, 2);
      expect(r.changes, [const RegionChange(2, 0, green)]);
      expect(s.showsNumberOf(2), isFalse);
      expect(s.paletteProgress[1].correct, 1);
    });

    test('unfinishedRegionsOf lists the regions still showing a number', () {
      final s = fixtureSession(mode: ColoringMode.numbers);
      expect(s.unfinishedRegionsOf(0), [1, 4]);
      expect(s.unfinishedRegionsOf(1), [2, 5]);
      tapRegion(s, 1);
      expect(s.unfinishedRegionsOf(0), [4]);
      tapRegion(s, 4);
      expect(s.unfinishedRegionsOf(0), isEmpty);
      expect(s.unfinishedRegionsOf(2), [3]);
    });

    test('free-mode colors still count as to do (D1) and get replaced', () {
      final s = fixtureSession()..selectColor(base);
      for (final id in fixturePaletteIndex.keys) {
        tapRegion(s, id);
      }
      s.setMode(ColoringMode.numbers);
      expect(s.fill.colorOf(1), base, reason: 'colors are kept');
      for (final id in fixturePaletteIndex.keys) {
        expect(s.showsNumberOf(id), isTrue);
      }
      expect(s.isComplete, isFalse);
      s.selectPaletteIndex(0);
      final r = tapRegion(s, 1);
      expect(r.changes, [const RegionChange(1, base, red)]);
      expect(s.showsNumberOf(1), isFalse);
    });

    test('auto-complete fires once', () {
      final s = fixtureSession(mode: ColoringMode.numbers);
      final results = <FillResult>[];
      for (final id in fixturePaletteIndex.keys) {
        s.selectPaletteIndex(fixturePaletteIndex[id]!);
        results.add(tapRegion(s, id));
      }
      expect(results.map((r) => r.justCompleted), [
        false,
        false,
        false,
        false,
        true,
      ]);
      expect(s.completed, isTrue);
      // Later edits keep the flag and never fire again.
      s.selectEraser();
      tapRegion(s, 1);
      expect(s.completed, isTrue);
      s.selectPaletteIndex(0);
      expect(tapRegion(s, 1).justCompleted, isFalse);
    });

    test('the eraser works in numbers mode', () {
      final s = fixtureSession(mode: ColoringMode.numbers);
      tapRegion(s, 1);
      s.selectEraser();
      expect(tapRegion(s, 1).changes, [const RegionChange(1, red, 0)]);
    });

    test('selectColor of a base color is refused in numbers mode', () {
      final s = fixtureSession(mode: ColoringMode.numbers);
      expect(() => s.selectColor(base), throwsArgumentError);
      expect(s.selectedPaletteIndex, 0);
      s.selectColor(blue);
      expect(s.selectedPaletteIndex, 2);
      expect(() => s.selectPaletteIndex(3), throwsRangeError);
    });
  });

  group('magic mode', () {
    test('a tap fills the correct color', () {
      final s = fixtureSession(mode: ColoringMode.magic)..selectColor(base);
      expect(tapRegion(s, 3).changes, [const RegionChange(3, 0, blue)]);
    });

    test('a stroke fills each touched region once, as one undo step', () {
      final s = fixtureSession(mode: ColoringMode.magic);
      s.beginStroke();
      expect(s.isStroking, isTrue);
      // Region 1 → line → region 2 → back to region 1 → down to 5.
      final a = s.strokeTo(1.5, 1.5, tolerance: 4);
      expect(a.changes, [const RegionChange(1, 0, red)]);
      final b = s.strokeTo(12.5, 1.5, tolerance: 4);
      expect(b.changes, [const RegionChange(2, 0, green)]);
      expect(s.strokeTo(2.5, 2.5, tolerance: 4).changes, isEmpty);
      final c = s.strokeTo(2.5, 10.5, tolerance: 4);
      expect(c.changes.map((e) => e.id), [3, 5]);
      final end = s.endStroke();
      expect(end.changes.map((e) => e.id), [1, 2, 3, 5]);
      expect(end.justCompleted, isFalse);
      expect(s.isStroking, isFalse);

      s.undo();
      expect(s.fill.filledCount, 0);
      expect(s.canUndo, isFalse);
    });

    test('a stroke over already-correct regions makes no undo step', () {
      final s = fixtureSession(mode: ColoringMode.magic);
      tapRegion(s, 1);
      s.undo();
      tapRegion(s, 1);
      s
        ..beginStroke()
        ..strokeTo(1.5, 1.5, tolerance: 4);
      expect(s.endStroke().outcome, FillOutcome.unchanged);
      s.undo();
      expect(s.canUndo, isFalse);
    });

    test('segment sampling hits a 2 px region between two far points', () {
      // 64×8, no lines: region 1 at x < 30, region 2 at x 30..31, region 3
      // at x >= 32.
      final ids = Uint16List(64 * 8);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 64; x++) {
          ids[y * 64 + x] = x < 30 ? 1 : (x < 32 ? 2 : 3);
        }
      }
      final meta = PictureMeta.fromJson({
        'width': 64,
        'height': 8,
        'level': 'simple',
        'background': 1,
        'palette': ['#ff0000', '#00ff00', '#0000ff'],
        'regions': [
          for (var id = 1; id <= 3; id++)
            {
              'id': id,
              'palette': id - 1,
              'color': '#000000',
              'area': 1,
              'bbox': [0, 0, 1, 1],
              'label': [0, 0],
              'label_radius': 1,
            },
        ],
      });
      for (final (from, to) in [
        ((2.0, 4.0), (62.0, 4.0)),
        ((2.0, 0.5), (62.0, 7.5)),
        ((62.7, 6.1), (1.3, 1.9)),
      ]) {
        final s = ColoringSession(
          meta: meta,
          map: RegionMap(64, 8, ids),
          mode: ColoringMode.magic,
        );
        s
          ..beginStroke()
          ..strokeTo(from.$1, from.$2, tolerance: 4)
          ..strokeTo(to.$1, to.$2, tolerance: 4);
        final end = s.endStroke();
        expect(end.changes.map((c) => c.id).toSet(), {1, 2, 3});
        expect(end.justCompleted, isTrue);
      }
    });

    test(
      'auto-complete fires on the stroke end that fills the last region',
      () {
        final s = fixtureSession(mode: ColoringMode.magic);
        s
          ..beginStroke()
          ..strokeTo(2.5, 1.5, tolerance: 4)
          ..strokeTo(10.5, 1.5, tolerance: 4)
          ..strokeTo(10.5, 6.5, tolerance: 4)
          ..strokeTo(2.5, 6.5, tolerance: 4);
        expect(s.endStroke().justCompleted, isFalse);
        s.beginStroke();
        final last = s.strokeTo(8.5, 10.5, tolerance: 4);
        expect(last.justCompleted, isFalse);
        expect(s.endStroke().justCompleted, isTrue);
        expect(s.completed, isTrue);
      },
    );

    test('auto-complete fires on a tap too', () {
      final s = fixtureSession(mode: ColoringMode.magic);
      final results = [
        for (final id in [1, 2, 3, 4, 5]) tapRegion(s, id),
      ];
      expect(results.last.justCompleted, isTrue);
      expect(results.where((r) => r.justCompleted), hasLength(1));
    });

    test('strokes do nothing outside magic mode or before beginStroke', () {
      final s = fixtureSession();
      s.beginStroke();
      expect(s.isStroking, isFalse);
      expect(s.strokeTo(2, 2, tolerance: 4).changes, isEmpty);
      expect(s.endStroke().outcome, FillOutcome.miss);
      expect(s.fill.filledCount, 0);
    });

    test('the eraser is unavailable and resets on switching to magic', () {
      final s = fixtureSession()..selectEraser();
      s.setMode(ColoringMode.magic);
      expect(s.tool, ColoringTool.brush);
      s.selectEraser();
      expect(s.tool, ColoringTool.brush);
    });

    test('wrong free colors keep magic incomplete until stroked over (D1)', () {
      final s = fixtureSession()..selectColor(base);
      for (final id in [1, 2, 3, 4, 5]) {
        tapRegion(s, id);
      }
      s.setMode(ColoringMode.magic);
      expect(tapRegion(s, 1).justCompleted, isFalse);
      expect(s.completed, isFalse);
      s
        ..beginStroke()
        ..strokeTo(10.5, 1.5, tolerance: 4)
        ..strokeTo(10.5, 6.5, tolerance: 4)
        ..strokeTo(2.5, 6.5, tolerance: 4);
      expect(s.endStroke().justCompleted, isFalse, reason: 'region 5 wrong');
      s
        ..beginStroke()
        ..strokeTo(8.5, 10.5, tolerance: 4);
      expect(s.endStroke().justCompleted, isTrue);
      expect(s.completed, isTrue);
    });

    group('a command that commits a completing stroke completes', () {
      /// Opens a stroke over the last empty region 5; 1..4 are done.
      ColoringSession lastRegionStroking() {
        final s = fixtureSession(mode: ColoringMode.magic);
        for (final id in [1, 2, 3, 4]) {
          tapRegion(s, id);
        }
        s
          ..beginStroke()
          ..strokeTo(8.5, 10.5, tolerance: 4);
        expect(s.completed, isFalse);
        return s;
      }

      test('a tap (even a miss)', () {
        final s = lastRegionStroking();
        final r = s.tap(-5, -5, tolerance: 1);
        expect(r.outcome, FillOutcome.miss);
        expect(r.justCompleted, isTrue);
        expect(s.completed, isTrue);
      });

      test('a tap on a region', () {
        final s = lastRegionStroking();
        final r = tapRegion(s, 1);
        expect(r.outcome, FillOutcome.unchanged);
        expect(r.justCompleted, isTrue);
      });

      test('undo', () {
        final s = lastRegionStroking();
        final r = s.undo();
        expect(r.justCompleted, isTrue);
        expect(s.completed, isTrue);
        expect(s.fill.isFilled(5), isFalse, reason: 'the stroke is undone');
      });

      test('setMode', () {
        final s = lastRegionStroking();
        expect(s.setMode(ColoringMode.free), isTrue);
        expect(s.completed, isTrue);
        expect(s.setMode(ColoringMode.magic), isFalse);
      });
    });

    test('undo during a stroke commits the stroke first', () {
      final s = fixtureSession(mode: ColoringMode.magic);
      s
        ..beginStroke()
        ..strokeTo(2.5, 1.5, tolerance: 4)
        ..strokeTo(10.5, 1.5, tolerance: 4);
      expect(s.undo().changes, hasLength(2));
      expect(s.fill.filledCount, 0);
      expect(s.isStroking, isFalse);
    });
  });

  group('mode switch', () {
    test('keeps colors and undo history and never completes by itself', () {
      final s = fixtureSession(mode: ColoringMode.magic);
      for (final id in [1, 2, 3, 4]) {
        tapRegion(s, id);
      }
      s.selectColor(green); // region 5's correct color, picked by hand
      s.setMode(ColoringMode.free);
      tapRegion(s, 5);
      expect(s.completed, isFalse);
      s.setMode(ColoringMode.magic);
      expect(s.isComplete, isTrue);
      expect(s.completed, isFalse, reason: 'A10: no completion on switch');
      expect(s.fill.colorOf(5), green);
      // The next change can complete.
      s.undo();
      final r = tapRegion(s, 5);
      expect(r.justCompleted, isTrue);
      // History survived the switches: undo back to empty.
      while (s.canUndo) {
        s.undo();
      }
      expect(s.fill.filledCount, 0);
    });

    test('setMode to the same mode is a no-op', () {
      final s = fixtureSession()..selectColor(base);
      s.setMode(ColoringMode.free);
      expect(s.selectedColor, base);
      expect(s.mode, ColoringMode.free);
    });
  });

  group('initial selection (spec §2.6)', () {
    test('free starts on palette[0]', () {
      final s = fixtureSession();
      expect(s.mode, ColoringMode.free);
      expect(s.selectedColor, red);
      expect(s.selectedPaletteIndex, 0);
      expect(s.tool, ColoringTool.brush);
    });

    test('numbers starts on the first incomplete palette index', () {
      final fill = FillState(5)
        ..setColor(1, red)
        ..setColor(4, red);
      final s = fixtureSession(mode: ColoringMode.numbers, fill: fill);
      expect(s.selectedPaletteIndex, 1);
      expect(s.selectedColor, green);
    });

    test('numbers starts on 0 when every color is done', () {
      final s = fixtureSession(mode: ColoringMode.numbers);
      fillAllCorrect(s);
      final again = fixtureSession(mode: ColoringMode.numbers, fill: s.fill);
      expect(again.selectedPaletteIndex, 0);
    });

    test('free → numbers → free keeps the selection', () {
      final s = fixtureSession()..selectColor(blue);
      s.setMode(ColoringMode.numbers);
      expect(s.selectedPaletteIndex, 2);
      s.setMode(ColoringMode.free);
      expect(s.selectedColor, blue);
      s.setMode(ColoringMode.numbers);
      s.selectPaletteIndex(1);
      s.setMode(ColoringMode.free);
      expect(s.selectedColor, green);
      expect(s.selectedPaletteIndex, 1);
    });

    test('a base color then numbers picks the first incomplete index', () {
      final fill = FillState(5)
        ..setColor(1, red)
        ..setColor(4, red);
      final s = fixtureSession(fill: fill)..selectColor(base);
      expect(s.selectedPaletteIndex, isNull);
      s.setMode(ColoringMode.numbers);
      expect(s.selectedPaletteIndex, 1);
      expect(s.selectedColor, green);
    });
  });
}
