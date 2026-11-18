import 'dart:math' as math;

import 'package:coloring/features/coloring/game/fill_animations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timing math', () {
    test('ease-out starts at 0, ends at 1 and front-loads the motion', () {
      expect(easeOutCubic(0), 0);
      expect(easeOutCubic(1), 1);
      expect(easeOutCubic(2), 1);
      expect(easeOutCubic(-1), 0);
      expect(easeOutCubic(0.5), greaterThan(0.5));
    });

    test('wave radius reaches the farthest bbox corner at 250 ms', () {
      // Tap at (10, 10) in a bbox (0, 0, 40, 30): farthest corner (40, 30).
      final max = waveMaxRadius(10, 10, 0, 0, 40, 30);
      expect(max, closeTo(math.sqrt(30 * 30 + 20 * 20), 1e-9));
      expect(waveRadiusAt(0, max), 0);
      expect(waveRadiusAt(0.125, max), greaterThan(max / 2));
      expect(waveRadiusAt(waveSeconds, max), closeTo(max, 1e-9));
      expect(waveRadiusAt(1, max), closeTo(max, 1e-9));
    });

    test('pulse cycles over 1.2 s between 0 and 1', () {
      expect(pulseAt(0), closeTo(0.5, 1e-9));
      expect(pulseAt(0.3), closeTo(1, 1e-9));
      expect(pulseAt(0.9), closeTo(0, 1e-9));
      expect(pulseAt(1.2), closeTo(0.5, 1e-9));
    });

    test('flash is a 300 ms bump, zero outside it', () {
      expect(flashAmountAt(0), 0);
      expect(flashAmountAt(0.15), closeTo(1, 1e-9));
      expect(flashAmountAt(0.3), 0);
      expect(flashAmountAt(0.5), 0);
    });

    test('wiggle stays within ±3 dp and stops after 300 ms', () {
      for (var t = 0.0; t < 0.4; t += 0.01) {
        expect(wiggleOffsetAt(t).abs(), lessThanOrEqualTo(3 + 1e-9));
      }
      // First quarter of the first of three cycles: full amplitude.
      expect(wiggleOffsetAt(0.025), closeTo(3, 1e-9));
      expect(wiggleOffsetAt(0.3), 0);
    });
  });

  group('WaveAnimation', () {
    test('a wave grows and ends after 250 ms', () {
      final w = WaveAnimation()
        ..startWave(
          regionId: 4,
          x: 0,
          y: 0,
          maxRadius: 100,
          oldColor: 0,
          newColor: 0xFFFF0000,
          instant: false,
        );
      expect(w.active, isTrue);
      w.advance(1 / 60);
      expect(w.radius, greaterThan(0));
      expect(w.radius, lessThan(100));
      w.advance(0.2);
      expect(w.active, isTrue);
      w.advance(0.05);
      expect(w.active, isFalse);
    });

    test('an instant wave lasts exactly one frame at the huge radius', () {
      final w = WaveAnimation()
        ..startWave(
          regionId: 4,
          x: 0,
          y: 0,
          maxRadius: 100,
          oldColor: 0,
          newColor: 0xFFFF0000,
          instant: true,
        );
      w.advance(1 / 60);
      expect(w.active, isTrue);
      expect(w.radius, instantRadius);
      expect(w.radius.isFinite, isTrue);
      w.advance(1 / 60);
      expect(w.active, isFalse);
    });

    test('a hint covers the region for 600 ms', () {
      final w = WaveAnimation()
        ..startHint(regionId: 2, oldColor: 0, color: 0xFF00FF00);
      w.advance(0.5);
      expect(w.active, isTrue);
      expect(w.radius, instantRadius);
      expect(w.newColor, 0xFF00FF00);
      w.advance(0.11);
      expect(w.active, isFalse);
    });
  });

  test('FlashAnimation fades out and wiggles for 300 ms', () {
    final f = FlashAnimation()..start(3);
    f.advance(0.15);
    expect(f.amount, closeTo(1, 1e-9));
    f.advance(0.1);
    expect(f.active, isTrue);
    expect(f.wiggleDp, isNot(0));
    f.advance(0.06);
    expect(f.active, isFalse);
    expect(f.amount, 0);
    expect(f.wiggleDp, 0);
  });
}
