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

  /// Starts the music loop, or resumes it where it was paused.
  void playMusic();
  void pauseMusic();
  void dispose();
}

class FlameAudioBackend implements AudioBackend {
  /// The platform calls for music are parameters so tests can fake them.
  FlameAudioBackend({
    Future<void> Function()? startMusic,
    Future<void> Function()? resumeMusic,
  }) : _startMusic = startMusic ?? _flameStartMusic,
       _resumeMusic = resumeMusic ?? (() => FlameAudio.bgm.resume());

  static const _musicFile = 'music.ogg';
  static const _musicVolume = 0.6;

  static Future<void> _flameStartMusic() async {
    // Takes audio focus: other apps' music pauses while ours plays, and ours
    // pauses for calls or when another app takes the focus.
    await FlameAudio.bgm.audioPlayer.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.gain).build(),
    );
    await FlameAudio.bgm.play(_musicFile, volume: _musicVolume);
  }

  final Future<void> Function() _startMusic;
  final Future<void> Function() _resumeMusic;
  final _pools = <Sfx, AudioPool>{};
  bool _musicStarted = false;
  bool _disposed = false;

  /// Platform calls run one after another, so a quick off-on toggle cannot
  /// interleave a pause with a half-started play.
  Future<void> _queue = Future.value();

  void _enqueue(Future<void> Function() action) {
    _queue = _queue.then((_) => action()).catchError((Object error) {
      debugPrint('Audio: $error');
    });
  }

  @override
  Future<void> preload() async {
    try {
      // Effects mix with other apps without taking audio focus. The music
      // player sets its own context, which wins over this global one.
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
  void playMusic() => _enqueue(() async {
    if (_musicStarted) return _resumeMusic();
    // Set only after a full start, so a failed start is retried next time.
    await _startMusic();
    _musicStarted = true;
  });

  @override
  void pauseMusic() => _enqueue(() async {
    if (_musicStarted) await FlameAudio.bgm.pause();
  });

  @override
  void dispose() {
    _disposed = true;
    for (final pool in _pools.values) {
      unawaited(pool.dispose());
    }
    _pools.clear();
    _enqueue(FlameAudio.bgm.stop);
  }
}

final audioBackendProvider = Provider<AudioBackend>((ref) {
  final backend = FlameAudioBackend();
  ref.onDispose(backend.dispose);
  return backend;
});

/// Decides what may sound: effects follow the "Sounds" setting, music
/// follows "Music" and stops while the app is in the background.
class AudioController {
  AudioController(this._backend);

  final AudioBackend _backend;
  bool _soundEnabled = false;
  bool _musicEnabled = false;
  bool _foreground = true;
  bool _musicPlaying = false;

  void applySettings(AppSettings settings) {
    _soundEnabled = settings.soundEnabled;
    _musicEnabled = settings.musicEnabled;
    _syncMusic();
  }

  void lifecycleChanged(AppLifecycleState state) {
    // `inactive` is a dialog or split-screen focus change, not leaving.
    _foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _syncMusic();
  }

  void play(Sfx sfx) {
    if (_soundEnabled && _foreground) _backend.playEffect(sfx);
  }

  void _syncMusic() {
    final shouldPlay = _musicEnabled && _foreground;
    if (shouldPlay == _musicPlaying) return;
    _musicPlaying = shouldPlay;
    if (shouldPlay) {
      _backend.playMusic();
    } else {
      _backend.pauseMusic();
    }
  }
}

/// Watched by the app, so music starts with it and lives as long as it.
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
