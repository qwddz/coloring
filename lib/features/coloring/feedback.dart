import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_controller.dart';
import '../settings/data/settings_controller.dart';

/// Vibration calls; tests override [hapticsBackendProvider] with a fake.
abstract interface class HapticsBackend {
  void light();
  void selection();
  void medium();
}

class PlatformHapticsBackend implements HapticsBackend {
  const PlatformHapticsBackend();

  @override
  void light() => HapticFeedback.lightImpact();

  @override
  void selection() => HapticFeedback.selectionClick();

  @override
  void medium() => HapticFeedback.mediumImpact();
}

final hapticsBackendProvider = Provider<HapticsBackend>(
  (ref) => const PlatformHapticsBackend(),
);

/// Sound and vibration for coloring events. Sound goes through
/// [AudioController], which checks the "Sounds" setting and the lifecycle;
/// vibration checks the "Vibration" setting here.
class ColoringFeedback {
  ColoringFeedback(this._ref);

  final Ref _ref;

  bool get _vibrate => _ref.read(settingsProvider).vibrationEnabled;

  void fill() {
    if (_vibrate) _ref.read(hapticsBackendProvider).light();
    _ref.read(audioControllerProvider).play(Sfx.fill);
  }

  void rejected() {
    if (_vibrate) _ref.read(hapticsBackendProvider).selection();
    _ref.read(audioControllerProvider).play(Sfx.wrong);
  }

  void completed() {
    if (_vibrate) _ref.read(hapticsBackendProvider).medium();
    _ref.read(audioControllerProvider).play(Sfx.win);
  }

  /// A hint highlight: a soft tick, no sound.
  void hint() {
    if (_vibrate) _ref.read(hapticsBackendProvider).selection();
  }
}

final coloringFeedbackProvider = Provider<ColoringFeedback>(
  ColoringFeedback.new,
);
