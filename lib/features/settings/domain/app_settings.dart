/// User preferences from the settings screen.
class AppSettings {
  const AppSettings({
    this.soundEnabled = true,
    this.musicEnabled = true,
    this.vibrationEnabled = true,
    this.languageCode,
  });

  final bool soundEnabled;
  final bool musicEnabled;

  /// A short buzz on a fill and when a picture is done.
  final bool vibrationEnabled;

  /// App language; null follows the device.
  final String? languageCode;

  static const supportedLanguages = ['uk', 'en', 'ru'];

  AppSettings copyWith({
    bool? soundEnabled,
    bool? musicEnabled,
    bool? vibrationEnabled,
    String? Function()? languageCode,
  }) => AppSettings(
    soundEnabled: soundEnabled ?? this.soundEnabled,
    musicEnabled: musicEnabled ?? this.musicEnabled,
    vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    languageCode: languageCode != null ? languageCode() : this.languageCode,
  );
}
