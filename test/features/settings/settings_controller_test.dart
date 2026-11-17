import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> container([
    Map<String, Object> values = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('defaults: everything on, device language', () async {
    final settings = (await container()).read(settingsProvider);
    expect(settings.soundEnabled, isTrue);
    expect(settings.musicEnabled, isTrue);
    expect(settings.vibrationEnabled, isTrue);
    expect(settings.languageCode, isNull);
  });

  test('changes are stored and read back', () async {
    final first = await container();
    first.read(settingsProvider.notifier)
      ..setSoundEnabled(false)
      ..setVibrationEnabled(false)
      ..setLanguage('uk');
    final prefs = await SharedPreferences.getInstance();
    final second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);
    final settings = second.read(settingsProvider);
    expect(settings.soundEnabled, isFalse);
    expect(settings.musicEnabled, isTrue);
    expect(settings.vibrationEnabled, isFalse);
    expect(settings.languageCode, 'uk');
  });

  test('choosing the device language again clears the override', () async {
    final c = await container({'settings.language': 'ru'});
    expect(c.read(settingsProvider).languageCode, 'ru');
    c.read(settingsProvider.notifier).setLanguage(null);
    expect(c.read(settingsProvider).languageCode, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.language'), isNull);
  });

  test('an unknown stored language falls back to the device', () async {
    final c = await container({'settings.language': 'de'});
    expect(c.read(settingsProvider).languageCode, isNull);
  });

  test('vibration defaults to on and persists', () async {
    final first = await container();
    expect(first.read(settingsProvider).vibrationEnabled, isTrue);
    first.read(settingsProvider.notifier).setVibrationEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.vibration'), isFalse);
    final second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);
    expect(second.read(settingsProvider).vibrationEnabled, isFalse);
  });
}
