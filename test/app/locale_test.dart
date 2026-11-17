import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/app/locale.dart';

void main() {
  const supported = [Locale('en'), Locale('ru'), Locale('uk')];

  test('picks the supported device language', () {
    expect(
      resolveAppLocale(const [Locale('uk', 'UA')], supported),
      const Locale('uk'),
    );
  });

  test('uses the first supported language in device preference order', () {
    expect(
      resolveAppLocale(const [
        Locale('de'),
        Locale('ru'),
        Locale('uk'),
      ], supported),
      const Locale('ru'),
    );
  });

  test('falls back to English for unsupported languages', () {
    expect(resolveAppLocale(const [Locale('de')], supported), fallbackLocale);
  });

  test('falls back to English when the device reports no languages', () {
    expect(resolveAppLocale(null, supported), fallbackLocale);
    expect(resolveAppLocale(const [], supported), fallbackLocale);
  });
}
