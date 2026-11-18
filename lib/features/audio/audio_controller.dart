import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/data/settings_controller.dart';
import '../settings/domain/app_settings.dart';

/// Sound effects in `assets/audio/`, synthesized by `tools/audio/synth.py`.
enum Sfx {
  fill,
  wrong,
  win;

  String get file => '$name.ogg';
}

/// Plays sounds on the device. Tests override [audioBackendProvider] with a
/// fake, so nothing here reaches platform channels.
abstract interface class AudioBackend {
  Future<void> preload();
  void playEffect(Sfx sfx);
  void dispose();
}

class FlameAudioBackend implements AudioBackend {
  final _pools = <Sfx, AudioPool>{};
  bool _disposed = false;

  @override
  Future<void> preload() async {
    try {
      // Effects mix with other apps without taking audio focus.
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build(),
      );
    } catch (error) {
      debugPrint('Audio: cannot set the effects context: $error');
    }
    for (final sfx in Sfx.values) {
      try {
        final pool = await FlameAudio.createPool(sfx.file, maxPlayers: 3);
        if (_disposed) {
          unawaited(pool.dispose());
        } else {
          _pools[sfx] = pool;
        }
      } catch (error) {
        debugPrint('Audio: cannot load ${sfx.file}: $error');
      }
    }
  }

  @override
  void playEffect(Sfx sfx) {
    final pool = _pools[sfx];
    if (pool == null) return;
    unawaited(
      pool.start().then<void>((_) {}).catchError((Object error) {
        debugPrint('Audio: $error');
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final pool in _pools.values) {
      unawaited(pool.dispose());
    }
    _pools.clear();
  }
}

final audioBackendProvider = Provider<AudioBackend>((ref) {
  final backend = FlameAudioBackend();
  ref.onDispose(backend.dispose);
  return backend;
});

/// Decides what may sound: effects follow the "Sounds" setting and are
/// silent while the app is in the background. Music is not played yet.
class AudioController {
  AudioController(this._backend);

  final AudioBackend _backend;
  bool _soundEnabled = false;
  bool _foreground = true;

  void applySettings(AppSettings settings) {
    _soundEnabled = settings.soundEnabled;
  }

  void lifecycleChanged(AppLifecycleState state) {
    // `inactive` is a dialog or split-screen focus change, not leaving.
    _foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  void play(Sfx sfx) {
    if (_soundEnabled && _foreground) _backend.playEffect(sfx);
  }
}

final audioControllerProvider = Provider<AudioController>((ref) {
  final backend = ref.watch(audioBackendProvider);
  final controller = AudioController(backend);
  final lifecycle = WidgetsBinding.instance.lifecycleState;
  if (lifecycle != null) controller.lifecycleChanged(lifecycle);
  ref.listen(
    settingsProvider,
    (_, settings) => controller.applySettings(settings),
    fireImmediately: true,
  );
  final listener = AppLifecycleListener(
    onStateChange: controller.lifecycleChanged,
  );
  ref.onDispose(listener.dispose);
  unawaited(backend.preload());
  return controller;
});
