import 'package:coloring/features/audio/audio_controller.dart';
import 'package:coloring/features/coloring/feedback.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAudioBackend implements AudioBackend {
  final effects = <Sfx>[];

  @override
  Future<void> preload() async {}

  @override
  void playEffect(Sfx sfx) => effects.add(sfx);

  @override
  void dispose() {}
}

class FakeHaptics implements HapticsBackend {
  final calls = <String>[];

  @override
  void light() => calls.add('light');

  @override
  void selection() => calls.add('selection');

  @override
  void medium() => calls.add('medium');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAudioBackend audio;
  late FakeHaptics haptics;
  late ProviderContainer container;

  Future<ColoringFeedback> start(Map<String, Object> preferences) async {
    SharedPreferences.setMockInitialValues(preferences);
    final prefs = await SharedPreferences.getInstance();
    audio = FakeAudioBackend();
    haptics = FakeHaptics();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioBackendProvider.overrideWithValue(audio),
        hapticsBackendProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(container.dispose);
    return container.read(coloringFeedbackProvider);
  }

  setUp(
    () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  test('maps events to haptics and sounds', () async {
    final feedback = await start(const {});
    feedback
      ..fill()
      ..rejected()
      ..completed()
      ..hint();
    expect(haptics.calls, ['light', 'selection', 'medium', 'selection']);
    expect(audio.effects, [Sfx.fill, Sfx.wrong, Sfx.win]);
  });

  test('vibration off: no haptics, sound still plays', () async {
    final feedback = await start(const {'settings.vibration': false});
    feedback
      ..fill()
      ..rejected()
      ..completed()
      ..hint();
    expect(haptics.calls, isEmpty);
    expect(audio.effects, [Sfx.fill, Sfx.wrong, Sfx.win]);
  });

  test('sound off: no effects, haptics still run', () async {
    final feedback = await start(const {'settings.sound': false});
    feedback
      ..fill()
      ..completed();
    expect(audio.effects, isEmpty);
    expect(haptics.calls, ['light', 'medium']);
  });

  test('settings changes apply live', () async {
    final feedback = await start(const {});
    container.read(settingsProvider.notifier).setVibrationEnabled(false);
    feedback.fill();
    container.read(settingsProvider.notifier).setVibrationEnabled(true);
    feedback.fill();
    expect(haptics.calls, ['light']);
  });

  test('nothing plays in the background', () async {
    final feedback = await start(const {});
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
    feedback.fill();
    expect(audio.effects, isEmpty);
  });
}
