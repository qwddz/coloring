import 'package:flutter/widgets.dart';

/// Used when none of the device languages is supported.
const fallbackLocale = Locale('en');

/// Picks the first device language the app supports, otherwise English.
Locale resolveAppLocale(
  List<Locale>? deviceLocales,
  Iterable<Locale> supportedLocales,
) {
  for (final device in deviceLocales ?? const <Locale>[]) {
    for (final supported in supportedLocales) {
      if (supported.languageCode == device.languageCode) return supported;
    }
  }
  return fallbackLocale;
}
