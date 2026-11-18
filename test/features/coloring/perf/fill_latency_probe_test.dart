import 'package:coloring/features/coloring/perf/fill_latency_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('percentile', () {
    test('nearest rank on unsorted values', () {
      final values = [for (var i = 20; i >= 1; i--) i * 1000];
      expect(FillLatencyProbe.percentile(values, 0.5), 10000);
      expect(FillLatencyProbe.percentile(values, 0.95), 19000);
      expect(FillLatencyProbe.percentile(values, 1), 20000);
      expect(FillLatencyProbe.percentile([7], 0.95), 7);
      expect(FillLatencyProbe.percentile([], 0.5), 0);
    });
  });

  group('recordFrame', () {
    late List<String> log;
    late FillLatencyProbe probe;

    setUp(() {
      log = [];
      probe = FillLatencyProbe(log: log.add, reportEvery: 4);
    });

    test('latency is measured from pointer-up to raster finish', () {
      probe.tapUp(const Duration(microseconds: 1000000));
      expect(
        probe.recordFrame(
          vsyncStartMicros: 1004000,
          rasterFinishMicros: 1030000,
        ),
        isTrue,
      );
      expect(probe.samples, [30000]);
      expect(log.single, startsWith('fill_latency total=30.0ms'));
    });

    test('a frame that started before the tap is skipped', () {
      probe.tapUp(const Duration(microseconds: 1000000));
      expect(
        probe.recordFrame(
          vsyncStartMicros: 990000,
          rasterFinishMicros: 1005000,
        ),
        isFalse,
      );
      expect(probe.samples, isEmpty);
      probe.recordFrame(vsyncStartMicros: 1010000, rasterFinishMicros: 1020000);
      expect(probe.samples, [20000]);
    });

    test('samples over 1 s or under 0 are dropped and counted', () {
      probe.tapUp(const Duration(microseconds: 1000000));
      probe.recordFrame(vsyncStartMicros: 1500000, rasterFinishMicros: 2500000);
      // Frame clock far behind the pointer clock: negative, dropped.
      probe.tapUp(const Duration(microseconds: 5000000));
      probe.recordFrame(vsyncStartMicros: 1000, rasterFinishMicros: 2000);
      expect(probe.samples, isEmpty);
      expect(probe.dropped, 2);
    });

    test('a frame with no pending tap is ignored', () {
      expect(
        probe.recordFrame(vsyncStartMicros: 10, rasterFinishMicros: 20),
        isTrue,
      );
      expect(probe.samples, isEmpty);
      expect(probe.dropped, 0);
    });

    test('logs p50/p95 with the drop count every reportEvery samples', () {
      for (var i = 1; i <= 4; i++) {
        probe.tapUp(Duration(seconds: i));
        probe.recordFrame(
          vsyncStartMicros: i * 1000000 + 1000,
          rasterFinishMicros: i * 1000000 + i * 10000,
        );
      }
      expect(log.last, 'fill_latency n=4 p50=20.0ms p95=40.0ms dropped=0');
    });
  });
}
