import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';

/// Loaded in `main()` before the first frame, so the app starts in the
/// chosen language.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main() and in tests'),
);

class SettingsController extends Notifier<AppSettings> {
  static const _sound = 'settings.sound';
  static const _music = 'settings.music';
  static const _vibration = 'settings.vibration';
  static const _language = 'settings.language';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = _prefs;
    final language = prefs.getString(_language);
    return AppSettings(
      soundEnabled: prefs.getBool(_sound) ?? true,
      musicEnabled: prefs.getBool(_music) ?? true,
      vibrationEnabled: prefs.getBool(_vibration) ?? true,
      languageCode: AppSettings.supportedLanguages.contains(language)
          ? language
          : null,
    );
  }

  void setSoundEnabled(bool value) {
    state = state.copyWith(soundEnabled: value);
    _prefs.setBool(_sound, value);
  }

  void setMusicEnabled(bool value) {
    state = state.copyWith(musicEnabled: value);
    _prefs.setBool(_music, value);
  }

  void setVibrationEnabled(bool value) {
    state = state.copyWith(vibrationEnabled: value);
    _prefs.setBool(_vibration, value);
  }

  /// Null returns to the device language.
  void setLanguage(String? code) {
    state = state.copyWith(languageCode: () => code);
    if (code == null) {
      _prefs.remove(_language);
    } else {
      _prefs.setString(_language, code);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
