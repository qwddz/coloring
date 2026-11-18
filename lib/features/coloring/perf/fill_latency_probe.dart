import 'dart:developer' as developer;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// `--dart-define=COLORING_PERF_LOG=true`: log tap-to-pixels latency.
const bool coloringPerfLog = bool.fromEnvironment('COLORING_PERF_LOG');

/// `--dart-define=COLORING_PERF_OVERLAY=true`: FPS counter on the canvas and
/// the Flutter performance overlay.
const bool coloringPerfOverlay = bool.fromEnvironment('COLORING_PERF_OVERLAY');

/// Measures fill latency on a device (spec §10), from pointer-up to the
/// raster finish of the first frame that starts after it.
///
/// Clocks: [tapUp] takes `PointerEvent.timeStamp` and frames report
/// [FrameTiming] stamps, both from the engine's monotonic clock. Samples
/// below 0 or above 1 s (clock mismatch, app paused) are dropped and
/// counted.
class FillLatencyProbe {
  FillLatencyProbe({void Function(String message)? log, this.reportEvery = 20})
    : _log = log ?? _developerLog;

  /// On in debug or profile builds started with `COLORING_PERF_LOG`.
  static bool get enabled => (kProfileMode || kDebugMode) && coloringPerfLog;

  static const int maxLatencyMicros = 1000000;

  /// A running p50/p95 line is logged after every [reportEvery] samples.
  final int reportEvery;
  final void Function(String message) _log;

  final List<int> _samples = [];
  int _dropped = 0;
  int? _tapUpMicros;
  int _modelMicros = 0;
  bool _listening = false;

  /// Kept samples, µs, in arrival order.
  List<int> get samples => List.unmodifiable(_samples);

  /// Samples dropped as out of range.
  int get dropped => _dropped;

  /// A tap was classified; [timeStamp] is the pointer-up event's stamp.
  void tapUp(Duration timeStamp) => _tapUpMicros = timeStamp.inMicroseconds;

  /// The controller applied the tap ([modelTime] = lookup + fill); waits
  /// for the frame that shows it.
  void fillApplied(Duration modelTime) {
    if (_tapUpMicros == null) return;
    _modelMicros = modelTime.inMicroseconds;
    final binding = SchedulerBinding.instance;
    if (!_listening) {
      _listening = true;
      binding.addTimingsCallback(_onTimings);
    }
    binding.scheduleFrame();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final resolved = recordFrame(
        vsyncStartMicros: t.timestampInMicroseconds(FramePhase.vsyncStart),
        rasterFinishMicros: t.timestampInMicroseconds(FramePhase.rasterFinish),
      );
      if (resolved) {
        _stopListening();
        return;
      }
    }
  }

  /// Feeds one frame. Returns true when the pending tap is resolved
  /// (recorded or dropped) or there is none.
  @visibleForTesting
  bool recordFrame({
    required int vsyncStartMicros,
    required int rasterFinishMicros,
  }) {
    final t0 = _tapUpMicros;
    if (t0 == null) return true;
    if (vsyncStartMicros < t0 && t0 - vsyncStartMicros <= maxLatencyMicros) {
      // A frame that began before the tap; wait for the next one.
      return false;
    }
    _tapUpMicros = null;
    final latency = rasterFinishMicros - t0;
    if (vsyncStartMicros < t0 || latency < 0 || latency > maxLatencyMicros) {
      _dropped++;
      _log('fill_latency dropped=$_dropped');
      return true;
    }
    _samples.add(latency);
    _log('fill_latency total=${_ms(latency)}ms model=${_modelMicros}us');
    if (_samples.length % reportEvery == 0) {
      _log(
        'fill_latency n=${_samples.length} '
        'p50=${_ms(percentile(_samples, 0.5))}ms '
        'p95=${_ms(percentile(_samples, 0.95))}ms dropped=$_dropped',
      );
    }
    return true;
  }

  /// Nearest-rank percentile of [values] (unsorted), [p] in 0..1.
  static int percentile(List<int> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = List<int>.of(values)..sort();
    final rank = (p * sorted.length).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }

  void dispose() => _stopListening();

  void _stopListening() {
    if (!_listening) return;
    _listening = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  static String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

  static void _developerLog(String message) =>
      developer.log(message, name: 'coloring.perf');
}
