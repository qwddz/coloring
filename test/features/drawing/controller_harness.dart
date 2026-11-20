import 'dart:async';
import 'dart:typed_data';

import 'package:coloring/features/coloring/feedback.dart';
import 'package:coloring/features/drawing/drawing_controller.dart';
import 'package:coloring/features/drawing/drawing_route.dart';
import 'package:coloring/features/drawing/drawing_state.dart';
import 'package:coloring/features/drawing/model/stroke.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/coloring_overrides.dart';
import '../coloring/fakes.dart';
import 'fakes.dart';

/// An autosave timer the test fires by hand.
class ManualTimer implements Timer {
  ManualTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

/// Records every timer the controller starts.
class ManualTimers {
  final started = <ManualTimer>[];

  Timer call(Duration delay, void Function() callback) {
    final timer = ManualTimer(delay, callback);
    started.add(timer);
    return timer;
  }

  List<ManualTimer> get active => [
    for (final t in started)
      if (t.isActive) t,
  ];
}

/// The drawing pieces of a test: an in-memory repository and preview fake,
/// hand-fired timers, a ticking clock and recorded feedback, shared by
/// every container [container] makes (an app restart is a new container on
/// the same [drawings]).
class DrawingHarness {
  DrawingHarness(this.prefs, {InMemoryDrawingRepository? drawings})
    : drawings = drawings ?? InMemoryDrawingRepository();

  final SharedPreferences prefs;
  final InMemoryDrawingRepository drawings;
  final previews = FakeDrawingPreviewService();
  final timers = ManualTimers();
  final feedback = RecordingFeedback();
  int ticks = 0;

  DateTime now() => DateTime.utc(2026, 11, 20).add(Duration(seconds: ticks++));

  /// A container; disposed at the end of the test unless the test did.
  ProviderContainer container({Stream<bool> Function()? fullAccess}) {
    final c = ProviderContainer(
      overrides: [
        ...drawingScreenOverrides(
          drawings: drawings,
          drawingPreviews: previews,
        ),
        sharedPreferencesProvider.overrideWithValue(prefs),
        fullAccessProvider.overrideWith(
          (ref) => fullAccess?.call() ?? Stream.value(false),
        ),
        drawingSaveTimerProvider.overrideWithValue(timers.call),
        drawingClockProvider.overrideWithValue(now),
        coloringFeedbackProvider.overrideWithValue(feedback),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }
}

/// Opens [request] in [c], keeps the auto-dispose controller alive and
/// returns it.
Future<DrawingController> openDrawing(
  ProviderContainer c, [
  DrawingRequest request = const DrawingRequest(),
]) async {
  c.listen(drawingControllerProvider(request), (_, _) {});
  await c.read(drawingControllerProvider(request).future);
  return c.read(drawingControllerProvider(request).notifier);
}

DrawingState stateOf(
  ProviderContainer c, [
  DrawingRequest request = const DrawingRequest(),
]) => c.read(drawingControllerProvider(request)).requireValue;

/// A finger stroke through [points] (canvas pixels).
void drawStroke(DrawingController controller, List<(double, double)> points) {
  for (var i = 0; i < points.length; i++) {
    final p = StrokePoint(points[i].$1, points[i].$2, tMillis: i * 16);
    if (i == 0) {
      controller.strokeBegin(p);
    } else {
      controller.strokeAdd(p);
    }
  }
  controller.strokeEnd();
}

/// The committed pixels after every queued change (a copy).
Future<Uint8List> pixelsOf(DrawingController controller) async {
  await controller.idle;
  return Uint8List.fromList(await controller.engine!.readback());
}

/// ARGB of pixel (x, y) of a canvas-wide RGBA buffer [rgba] [width] wide.
int argbAt(Uint8List rgba, int width, int x, int y) {
  final o = (y * width + x) * 4;
  return rgba[o + 3] << 24 | rgba[o] << 16 | rgba[o + 1] << 8 | rgba[o + 2];
}

/// Waits (real time) until [condition] holds.
Future<void> until(bool Function() condition, {String? reason}) async {
  for (var i = 0; i < 500; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('timed out waiting${reason == null ? '' : ' for $reason'}');
}
