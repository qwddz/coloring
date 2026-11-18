import 'dart:math';
import 'dart:typed_data';

import 'package:coloring/features/coloring/model/region_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('RegionMap.fromRgba', () {
    test('id = R * 256 + G, ignoring B and A', () {
      final rgba = Uint8List.fromList([
        0, 1, 99, 255, // 1
        1, 44, 0, 0, // 300
        1, 45, 7, 128, // 301
        0, 0, 255, 255, // 0 (line)
      ]);
      final map = RegionMap.fromRgba(rgba, 2, 2);
      expect(map.ids, [1, 300, 301, 0]);
      expect(map.idAt(1, 0), 300);
      expect(map.idAt(0, 1), 301);
      expect(map.maxId, 301);
    });

    test('round-trips the fixture', () {
      final ids = idsFromRows(fixtureRows);
      final map = RegionMap.fromRgba(rgbaFromIds(ids), 16, 12);
      expect(map.ids, ids);
      expect(map.maxId, 5);
    });

    test('rejects a buffer of the wrong length', () {
      expect(
        () => RegionMap.fromRgba(Uint8List(16 * 12 * 4 - 1), 16, 12),
        throwsArgumentError,
      );
      expect(() => RegionMap.fromRgba(Uint8List(0), 0, 0), throwsArgumentError);
      expect(() => RegionMap(4, 4, Uint16List(15)), throwsArgumentError);
    });
  });

  group('idAt', () {
    test('reads row-major ids and returns 0 out of bounds', () {
      final map = fixtureMap();
      expect(map.idAt(0, 0), 1);
      expect(map.idAt(15, 0), 2);
      expect(map.idAt(6, 0), 0);
      expect(map.idAt(15, 11), 5);
      expect(map.idAt(-1, 0), 0);
      expect(map.idAt(0, -1), 0);
      expect(map.idAt(16, 0), 0);
      expect(map.idAt(0, 12), 0);
    });
  });

  group('lookup', () {
    final map = fixtureMap();

    test('returns the id under a region pixel', () {
      expect(map.lookup(2.9, 1.1, tolerance: 4), 1);
      expect(map.lookup(10, 6, tolerance: 0), 4);
    });

    test('on a line returns the nearest region', () {
      // (6, 9) lies in region 5; (6, 8) is a line one pixel above it, with
      // regions 3 and 4 diagonal (d² = 2) and region 5 straight below (d² = 1).
      expect(map.lookup(6.5, 8.5, tolerance: 4), 5);
      // Row 4, column 0: region 1 above and region 3 below, both d² = 1.
      expect(map.lookup(0.5, 4.5, tolerance: 4), 1);
    });

    test('breaks ties deterministically towards the smaller id', () {
      // (6, 2): region 1 left and region 2 right, both one pixel away.
      expect(map.lookup(6.5, 2.5, tolerance: 4), 1);
      // (6, 4): only diagonals hit regions 1, 2, 3, 4 at d² = 2.
      expect(map.lookup(6.5, 4.5, tolerance: 4), 1);
      // (8, 8): region 4 above and region 5 below.
      expect(map.lookup(8.5, 8.5, tolerance: 4), 4);
    });

    test('returns 0 when no region is within the tolerance', () {
      expect(map.lookup(6.5, 2.5, tolerance: 0.5), 0);
      // Diagonal neighbours are sqrt(2) away: outside tolerance 1.
      expect(map.lookup(6.5, 4.5, tolerance: 1), 0);
      expect(map.lookup(6.5, 4.5, tolerance: 1.5), 1);

      final blob = RegionMap(9, 9, Uint16List(81)..[0] = 3);
      expect(blob.lookup(8.5, 8.5, tolerance: 4), 0);
      expect(blob.lookup(8.5, 8.5, tolerance: 12), 3);
    });

    test('nearest is Euclidean, not the first ring with a hit', () {
      // From (5, 5): region 1 at (8, 8) is on ring 3 with d² = 18, region 2
      // at (9, 5) is on ring 4 with d² = 16, so region 2 is nearer.
      final ids = Uint16List(121);
      ids[8 * 11 + 8] = 1;
      ids[5 * 11 + 9] = 2;
      final m = RegionMap(11, 11, ids);
      expect(m.lookup(5.5, 5.5, tolerance: 6), 2);
    });

    test('returns 0 outside the image', () {
      expect(map.lookup(-0.1, 2, tolerance: 4), 0);
      expect(map.lookup(2, 12, tolerance: 4), 0);
      expect(map.lookup(16, 2, tolerance: 4), 0);
      expect(map.lookup(double.nan, 2, tolerance: 4), 0);
    });

    test('near the edge does not read outside the map', () {
      final m = RegionMap(3, 3, Uint16List(9)..[8] = 2);
      expect(m.lookup(0.5, 0.5, tolerance: 4), 2);
      expect(m.lookup(2.5, 0.5, tolerance: 4), 2);
    });

    test('1000 lookups with tolerance 16 on 2048x1536 take < 5 ms each', () {
      const w = 2048;
      const h = 1536;
      // 32 px square regions in a 64 px grid: line areas up to ~22 px from
      // any region, so many lookups scan the whole tolerance disc.
      final ids = Uint16List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (x % 64 < 32 && y % 64 < 32) {
            ids[y * w + x] = 1 + (y ~/ 64) * 32 + (x ~/ 64);
          }
        }
      }
      final map = RegionMap(w, h, ids);
      final rnd = Random(7);
      final points = [
        for (var i = 0; i < 1000; i++)
          (rnd.nextDouble() * w, rnd.nextDouble() * h),
      ];
      // Warm up the JIT.
      for (final (x, y) in points.take(100)) {
        map.lookup(x, y, tolerance: 16);
      }
      final sw = Stopwatch();
      var slowest = Duration.zero;
      var found = 0;
      for (final (x, y) in points) {
        sw
          ..reset()
          ..start();
        if (map.lookup(x, y, tolerance: 16) != 0) found++;
        sw.stop();
        if (sw.elapsed > slowest) slowest = sw.elapsed;
      }
      expect(found, greaterThan(250));
      expect(slowest, lessThan(const Duration(milliseconds: 5)));
    });
  });

  test('checkMatches compares size and max id with the meta', () {
    final meta = fixtureMeta();
    fixtureMap().checkMatches(meta);
    final ids = idsFromRows(fixtureRows);
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] == 5) ids[i] = 4;
    }
    expect(
      () => RegionMap(16, 12, ids).checkMatches(meta),
      throwsFormatException,
    );
    expect(
      () => RegionMap(12, 16, idsFromRows(fixtureRows)).checkMatches(meta),
      throwsFormatException,
    );
  });
}
