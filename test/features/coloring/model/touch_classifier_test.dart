import 'dart:math';

import 'package:coloring/features/coloring/model/touch_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  late TouchClassifier c;
  setUp(() => c = TouchClassifier());

  test('hold 299 ms and move 9 dp is a tap', () {
    c.pointerDown(1, const Point(100, 100), ms(0));
    expect(c.pointerMove(1, const Point(109, 100), ms(100)), isEmpty);
    final out = c.pointerUp(1, const Point(109, 100), ms(299));
    expect(out, hasLength(1));
    expect((out.single as Tap).position, const Point(109.0, 100.0));
  });

  test('hold 300 ms is not a tap', () {
    c.pointerDown(1, const Point(0, 0), ms(0));
    expect(c.pointerUp(1, const Point(0, 0), ms(300)), isEmpty);
  });

  test('moving 10 dp is not a tap but a drag', () {
    c.pointerDown(1, const Point(0, 0), ms(0));
    final move = c.pointerMove(1, const Point(10, 0), ms(50));
    expect(move.first, isA<DragStart>());
    expect(move.last, isA<DragUpdate>());
    expect((move.last as DragUpdate).delta, const Point(10.0, 0.0));
    final up = c.pointerUp(1, const Point(10, 0), ms(100));
    expect(up.single, isA<DragEnd>());
  });

  test('drag updates carry deltas since the previous update', () {
    c.pointerDown(1, const Point(0, 0), ms(0));
    c.pointerMove(1, const Point(20, 0), ms(10));
    final out = c.pointerMove(1, const Point(25, 5), ms(20));
    expect((out.single as DragUpdate).delta, const Point(5.0, 5.0));
  });

  group('long press', () {
    test('tick at 499 emits nothing, at 500 once, never repeats', () {
      c.pointerDown(1, const Point(5, 5), ms(0));
      expect(c.tick(ms(499)), isEmpty);
      final out = c.tick(ms(500));
      expect(out.single, isA<LongPress>());
      expect((out.single as LongPress).position, const Point(5.0, 5.0));
      expect(c.tick(ms(600)), isEmpty);
      expect(c.pointerUp(1, const Point(5, 5), ms(700)), isEmpty);
    });

    test('move of 10 dp before 500 cancels it', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      c.pointerMove(1, const Point(10, 0), ms(100));
      expect(c.tick(ms(500)), isEmpty);
    });

    test('up before 500 cancels it', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      c.pointerUp(1, const Point(0, 0), ms(400));
      expect(c.tick(ms(500)), isEmpty);
    });

    test('a small jitter does not cancel it', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      c.pointerMove(1, const Point(3, 3), ms(100));
      expect(c.tick(ms(500)).single, isA<LongPress>());
    });

    test('moving past the slop after a long press turns into a drag', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      expect(c.tick(ms(500)).single, isA<LongPress>());
      expect(c.pointerMove(1, const Point(5, 0), ms(550)), isEmpty);
      final move = c.pointerMove(1, const Point(30, 0), ms(600));
      expect(move, hasLength(2));
      expect((move.first as DragStart).position, const Point(0.0, 0.0));
      expect((move.last as DragUpdate).delta, const Point(30.0, 0.0));
      final next = c.pointerMove(1, const Point(40, 0), ms(620));
      expect((next.single as DragUpdate).delta, const Point(10.0, 0.0));
      expect(
        c.pointerUp(1, const Point(40, 0), ms(700)).single,
        isA<DragEnd>(),
      );
    });

    test('second pointer cancels it', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      c.pointerDown(2, const Point(50, 0), ms(100));
      expect(c.tick(ms(500)), isEmpty);
    });
  });

  group('two fingers', () {
    test('second pointer starts scale and cancels the pending tap', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      final out = c.pointerDown(2, const Point(100, 0), ms(50));
      expect(out.single, isA<ScaleStart>());
      expect((out.single as ScaleStart).focal, const Point(50.0, 0.0));
      final up = c.pointerUp(2, const Point(100, 0), ms(100));
      expect(up.single, isA<ScaleEnd>());
      expect(c.pointerUp(1, const Point(0, 0), ms(120)), isEmpty);
    });

    test('scale updates report factor and focal pan', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      c.pointerDown(2, const Point(100, 0), ms(10));
      final out = c.pointerMove(2, const Point(200, 0), ms(20));
      final u = out.single as ScaleUpdate;
      expect(u.scaleFactor, closeTo(2, 1e-9));
      expect(u.focal, const Point(100.0, 0.0));
      expect(u.panDelta, const Point(50.0, 0.0));
    });

    test('a drag interrupted by a second finger ends with dragEnd', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      c.pointerMove(1, const Point(30, 0), ms(20));
      final out = c.pointerDown(2, const Point(100, 0), ms(40));
      expect(out, hasLength(2));
      expect(out.first, isA<DragEnd>());
      expect(out.last, isA<ScaleStart>());
    });

    test('a lingering finger after scale does not tap or drag', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      c.pointerDown(2, const Point(100, 0), ms(10));
      c.pointerUp(2, const Point(100, 0), ms(20));
      expect(c.pointerMove(1, const Point(80, 0), ms(30)), isEmpty);
      expect(c.pointerUp(1, const Point(80, 0), ms(40)), isEmpty);
      c.pointerDown(3, const Point(1, 1), ms(100));
      expect(c.pointerUp(3, const Point(1, 1), ms(150)).single, isA<Tap>());
    });
  });

  group('cancel of one pointer', () {
    test('ends the drag of the cancelled primary at its last position', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      c.pointerMove(1, const Point(30, 0), ms(20));
      final out = c.pointerCancel(1);
      expect((out.single as DragEnd).position, const Point(30.0, 0.0));
      expect(c.pointerUp(1, const Point(30, 0), ms(40)), isEmpty);
    });

    test('cancelling one of two scaling fingers keeps the other tracked', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      c.pointerDown(2, const Point(100, 0), ms(10));
      expect(c.pointerCancel(2).single, isA<ScaleEnd>());
      // Finger 1 is still down: it neither drags nor taps, and a new
      // finger does not start a fresh gesture until it is up.
      expect(c.pointerMove(1, const Point(80, 0), ms(30)), isEmpty);
      c.pointerDown(3, const Point(1, 1), ms(40));
      expect(c.pointerUp(3, const Point(1, 1), ms(60)), isEmpty);
      expect(c.pointerUp(1, const Point(80, 0), ms(70)), isEmpty);
      c.pointerDown(4, const Point(1, 1), ms(100));
      expect(c.pointerUp(4, const Point(1, 1), ms(150)).single, isA<Tap>());
    });

    test('an unknown pointer changes nothing', () {
      c.pointerDown(1, const Point(0, 0), ms(0));
      expect(c.pointerCancel(7), isEmpty);
      expect(c.pointerUp(1, const Point(0, 0), ms(100)).single, isA<Tap>());
    });
  });

  test('cancel emits nothing and resets', () {
    c.pointerDown(1, const Point(0, 0), ms(0));
    c.pointerCancel(1);
    expect(c.tick(ms(600)), isEmpty);
    expect(c.pointerUp(1, const Point(0, 0), ms(100)), isEmpty);
    c.pointerDown(1, const Point(0, 0), ms(1000));
    expect(c.pointerUp(1, const Point(0, 0), ms(1100)).single, isA<Tap>());
  });
}
