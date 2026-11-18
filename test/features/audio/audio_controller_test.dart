import 'package:coloring/features/audio/audio_controller.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAudioBackend implements AudioBackend {
  final effects = <Sfx>[];
  var preloaded = false;

  @override
  Future<void> preload() async => preloaded = true;

  @override
  void playEffect(Sfx sfx) => effects.add(sfx);

  @override
  void dispose() {}
}

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

  setUp(() => goTo(const [AppLifecycleState.resumed]));

  test('preloads the effects', () async {
    await start(const {});
    expect(backend.preloaded, isTrue);
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

  test('nothing plays in the background, sound returns on resume', () async {
    await start(const {});
    final audio = container.read(audioControllerProvider);
    goTo(const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    audio.play(Sfx.fill);
    expect(backend.effects, isEmpty);
    goTo(const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    audio.play(Sfx.fill);
    expect(backend.effects, [Sfx.fill]);
  });

  test('a short focus loss (inactive) still plays', () async {
    await start(const {});
    goTo(const [AppLifecycleState.inactive]);
    container.read(audioControllerProvider).play(Sfx.win);
    expect(backend.effects, [Sfx.win]);
  });
}
