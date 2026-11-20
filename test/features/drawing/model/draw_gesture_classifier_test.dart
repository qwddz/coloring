import 'dart:math';

import 'package:coloring/features/drawing/model/draw_gesture_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

Duration ms(int v) => Duration(milliseconds: v);

const touch = PointerKind.touch;
const stylus = PointerKind.stylus;

void main() {
  late DrawGestureClassifier c;
  setUp(() => c = DrawGestureClassifier());

  List<DrawGesture> down(
    int id,
    double x,
    double y,
    int t, {
    PointerKind kind = touch,
    double pressure = 0.4,
  }) => c.pointerDown(id, kind, Point(x, y), pressure, ms(t));

  List<DrawGesture> move(int id, double x, double y, int t, {double p = 0.4}) =>
      c.pointerMove(id, Point(x, y), p, ms(t));

  List<DrawGesture> up(int id, double x, double y, int t) =>
      c.pointerUp(id, Point(x, y), ms(t));

  group('drawing', () {
    test('a stroke starts on first contact and commits on lift', () {
      final begin = down(1, 10, 20, 0).single as StrokeBegin;
      expect(begin.position, const Point(10.0, 20.0));
      expect(begin.pressure, 1, reason: 'touch pressure is ignored');
      expect(begin.kind, touch);
      expect(begin.erases, isFalse);
      final add = move(1, 12, 20, 16).single as StrokeAdd;
      expect(add.position, const Point(12.0, 20.0));
      expect(add.time, ms(16));
      expect(up(1, 12, 20, 30).single, isA<StrokeEnd>());
    });

    test('mouse draws like touch', () {
      expect(
        down(1, 0, 0, 0, kind: PointerKind.mouse).single,
        isA<StrokeBegin>(),
      );
      expect(up(1, 0, 0, 10).single, isA<StrokeEnd>());
    });

    test('stylus pressure passes through, inverted stylus erases', () {
      final begin =
          down(1, 0, 0, 0, kind: stylus, pressure: 0.3).single as StrokeBegin;
      expect(begin.pressure, 0.3);
      expect((move(1, 5, 0, 10, p: 0.8).single as StrokeAdd).pressure, 0.8);
      expect((move(1, 6, 0, 11, p: 1.7).single as StrokeAdd).pressure, 1);
      up(1, 6, 0, 20);
      final eraser =
          down(2, 0, 0, 1000, kind: PointerKind.invertedStylus).single
              as StrokeBegin;
      expect(eraser.erases, isTrue);
    });

    test('cancel of the drawing pointer commits the stroke', () {
      down(1, 0, 0, 0);
      move(1, 50, 0, 100);
      expect(c.pointerCancel(1, ms(120)).single, isA<StrokeEnd>());
      expect(move(1, 60, 0, 130), isEmpty);
    });
  });

  group('second finger', () {
    test('short by distance: the stroke is discarded, then zoom', () {
      down(1, 100, 100, 0);
      move(1, 105, 100, 400); // 5 dp, old enough
      final out = down(2, 200, 100, 400);
      expect(out, hasLength(2));
      expect(out[0], isA<StrokeDiscard>());
      expect((out[1] as ScaleStart).focal, const Point(152.5, 100.0));
    });

    test('short by age: the stroke is discarded, then zoom', () {
      down(1, 100, 100, 0);
      move(1, 160, 100, 100); // 60 dp in 249 ms
      final out = down(2, 300, 100, 249);
      expect(out.first, isA<StrokeDiscard>());
      expect(out.last, isA<ScaleStart>());
    });

    test('a long stroke is committed, then zoom', () {
      down(1, 100, 100, 0);
      move(1, 110, 100, 100);
      final out = down(2, 300, 100, 250); // 10 dp and 250 ms
      expect(out.first, isA<StrokeEnd>());
      expect(out.last, isA<ScaleStart>());
    });

    test('zoom updates, ends when a finger lifts, rest ignored until up', () {
      down(1, 0, 0, 0);
      down(2, 100, 0, 10);
      final update = move(2, 200, 0, 20).single as ScaleUpdate;
      expect(update.scaleFactor, closeTo(2, 1e-9));
      expect(update.panDelta, const Point(50.0, 0.0));
      expect(down(3, 50, 50, 25), isEmpty, reason: 'third finger');
      expect(up(2, 200, 0, 30).single, isA<ScaleEnd>());
      expect(move(1, 10, 0, 40), isEmpty);
      expect(down(4, 10, 10, 50), isEmpty, reason: 'locked until all up');
      expect(up(1, 10, 0, 60), isEmpty);
      expect(up(3, 50, 50, 61), isEmpty);
      expect(up(4, 10, 10, 62), isEmpty);
      expect(down(5, 0, 0, 70).single, isA<StrokeBegin>());
    });

    test('cancel of a scale pointer ends the scale', () {
      down(1, 0, 0, 0);
      down(2, 100, 0, 10);
      expect(c.pointerCancel(1, ms(20)).single, isA<ScaleEnd>());
      expect(move(2, 50, 0, 30), isEmpty);
    });
  });

  group('fill', () {
    setUp(() => c.fillMode = true);

    test('fires on lift at the down position', () {
      expect(down(1, 40, 50, 0), isEmpty);
      expect(move(1, 45, 50, 100), isEmpty);
      final tap = up(1, 49, 50, 900).single as FillTap;
      expect(tap.position, const Point(40.0, 50.0));
    });

    test('nothing when the pointer moved 10 dp', () {
      down(1, 0, 0, 0);
      move(1, 10, 0, 50);
      move(1, 0, 0, 60);
      expect(up(1, 0, 0, 70), isEmpty);
    });

    test('nothing when a scale started during the contact', () {
      down(1, 0, 0, 0);
      expect(down(2, 100, 0, 10).single, isA<ScaleStart>());
      expect(up(2, 100, 0, 20).single, isA<ScaleEnd>());
      expect(up(1, 0, 0, 30), isEmpty);
    });

    test('cancel does nothing', () {
      down(1, 0, 0, 0);
      expect(c.pointerCancel(1, ms(10)), isEmpty);
    });

    test('a stylus taps too', () {
      down(1, 7, 8, 0, kind: stylus);
      expect(up(1, 7, 8, 10).single, isA<FillTap>());
    });

    test('an inverted stylus still erases', () {
      final begin =
          down(1, 7, 8, 0, kind: PointerKind.invertedStylus).single
              as StrokeBegin;
      expect(begin.erases, isTrue);
      expect(move(1, 20, 8, 16).single, isA<StrokeAdd>());
      expect(up(1, 20, 8, 30).single, isA<StrokeEnd>());
    });
  });

  group('stylus', () {
    test('discards a live touch stroke (stamps included) and draws', () {
      down(1, 0, 0, 0);
      move(1, 100, 0, 500);
      final out = down(2, 300, 300, 600, kind: stylus, pressure: 0.6);
      expect(out, hasLength(2));
      expect(out[0], isA<StrokeDiscard>());
      final begin = out[1] as StrokeBegin;
      expect(begin.position, const Point(300.0, 300.0));
      expect(begin.pressure, 0.6);
      expect(move(1, 120, 0, 610), isEmpty, reason: 'touch ignored');
      expect(up(1, 120, 0, 620), isEmpty);
      expect(move(2, 310, 300, 630).single, isA<StrokeAdd>());
      expect(up(2, 310, 300, 640).single, isA<StrokeEnd>());
    });

    test('during a touch scale it ends the scale and draws', () {
      down(1, 0, 0, 0);
      down(2, 100, 0, 10);
      final out = down(3, 50, 50, 20, kind: stylus);
      expect(out[0], isA<ScaleEnd>());
      expect(out[1], isA<StrokeBegin>());
      expect(move(1, 10, 0, 30), isEmpty);
      expect(move(2, 90, 0, 30), isEmpty);
      expect(move(3, 60, 50, 40).single, isA<StrokeAdd>());
    });

    test('never starts a scale', () {
      down(1, 0, 0, 0, kind: stylus);
      expect(down(2, 100, 0, 10, kind: touch), isEmpty, reason: 'palm');
      expect(move(1, 10, 0, 20).single, isA<StrokeAdd>());
    });

    test('a second stylus is ignored', () {
      down(1, 0, 0, 0, kind: stylus);
      expect(down(2, 100, 0, 10, kind: stylus), isEmpty);
      expect(move(2, 110, 0, 20), isEmpty);
      expect(up(2, 110, 0, 30), isEmpty);
      expect(move(1, 5, 0, 40).single, isA<StrokeAdd>());
    });

    test('palm touches during and 300 ms after the stylus are ignored', () {
      down(1, 0, 0, 0, kind: stylus);
      expect(down(2, 500, 500, 10), isEmpty, reason: 'during');
      up(1, 0, 0, 1000);
      expect(up(2, 500, 500, 1100), isEmpty);
      expect(down(3, 400, 400, 1300), isEmpty, reason: '300 ms after');
      expect(move(3, 450, 400, 1400), isEmpty, reason: 'whole contact');
      expect(up(3, 450, 400, 1500), isEmpty);
      // The palm window starts at the lift, not at a later stroke.
      expect(down(4, 400, 400, 1301).single, isA<StrokeBegin>());
    });

    test('cancel of the stylus commits and starts the palm window', () {
      down(1, 0, 0, 0, kind: stylus);
      expect(c.pointerCancel(1, ms(100)).single, isA<StrokeEnd>());
      expect(down(2, 0, 0, 400), isEmpty);
      up(2, 0, 0, 450);
      expect(down(3, 0, 0, 401 + 100).single, isA<StrokeBegin>());
    });
  });
}
