import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/features/audio/audio_controller.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio_backend.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAudioBackend backend;
  late ProviderContainer container;

  Future<void> start(Map<String, Object> preferences) async {
    SharedPreferences.setMockInitialValues(preferences);
    final prefs = await SharedPreferences.getInstance();
    backend = FakeAudioBackend();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioBackendProvider.overrideWithValue(backend),
      ],
    );
    addTearDown(container.dispose);
    container.read(audioControllerProvider);
  }

  void goTo(List<AppLifecycleState> states) {
    for (final state in states) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  const toBackground = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const toForeground = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  setUp(() => goTo(const [AppLifecycleState.resumed]));

  test('preloads effects and starts the music when it is on', () async {
    await start(const {});
    expect(backend.calls, ['playMusic', 'preload']);
  });

  test('effects play only while sounds are on', () async {
    await start(const {});
    final audio = container.read(audioControllerProvider);
    audio.play(Sfx.fill);
    container.read(settingsProvider.notifier).setSoundEnabled(false);
    audio
      ..play(Sfx.wrong)
      ..play(Sfx.win);
    container.read(settingsProvider.notifier).setSoundEnabled(true);
    audio.play(Sfx.wrong);
    expect(backend.effects, [Sfx.fill, Sfx.wrong]);
  });

  test('music follows the toggle live', () async {
    await start(const {'settings.music': false});
    expect(backend.calls, isNot(contains('playMusic')));
    final settings = container.read(settingsProvider.notifier);
    backend.calls.clear();
    settings.setMusicEnabled(true);
    settings.setSoundEnabled(false); // unrelated change: no music call
    settings.setMusicEnabled(false);
    settings.setMusicEnabled(true);
    expect(backend.calls, ['playMusic', 'pauseMusic', 'playMusic']);
  });

  test('music pauses in the background and resumes on return', () async {
    await start(const {});
    backend.calls.clear();
    goTo(toBackground);
    expect(backend.calls, ['pauseMusic']);
    container.read(audioControllerProvider).play(Sfx.fill);
    goTo(toForeground);
    expect(backend.calls, ['pauseMusic', 'playMusic']);
  });

  test('music turned off stays off after returning to the app', () async {
    await start(const {});
    goTo(toBackground);
    container.read(settingsProvider.notifier).setMusicEnabled(false);
    backend.calls.clear();
    goTo(toForeground);
    expect(backend.calls, isEmpty);
  });

  test('a short focus loss (inactive) still plays', () async {
    await start(const {});
    goTo(const [AppLifecycleState.inactive]);
    container.read(audioControllerProvider).play(Sfx.win);
    expect(backend.effects, [Sfx.win]);
  });
}
