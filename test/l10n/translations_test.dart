import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const locales = ['en', 'uk', 'ru'];

Map<String, dynamic> readArb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

/// Names used as `{name}` or `{name, plural, …}` in an ARB message.
Set<String> placeholdersIn(String message) => {
  for (final match in RegExp(r'\{(\w+)\s*[,}]').allMatches(message))
    match.group(1)!,
};

void main() {
  final en = readArb('en');
  final keys = en.keys.where((key) => !key.startsWith('@')).toList();

  for (final locale in ['uk', 'ru']) {
    test('$locale translates every English message', () {
      final arb = readArb(locale);
      for (final key in keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$locale is missing "$key"');
        expect(
          (value as String).trim(),
          isNotEmpty,
          reason: '$locale "$key" is empty',
        );
        expect(
          placeholdersIn(value),
          placeholdersIn(en[key] as String),
          reason: '$locale "$key" has different placeholders',
        );
      }
      final extra = arb.keys.where(
        (key) => !key.startsWith('@') && !en.containsKey(key),
      );
      expect(extra, isEmpty, reason: '$locale has keys unknown to English');
    });
  }

  test('English placeholders are declared', () {
    for (final key in keys) {
      final used = placeholdersIn(en[key] as String);
      if (used.isEmpty) continue;
      final declared =
          ((en['@$key'] as Map?)?['placeholders'] as Map?)?.keys.toSet() ??
          <Object>{};
      expect(declared, used, reason: '"$key" placeholders');
    }
  });

  group('manifest', () {
    final manifest = jsonDecode(
      File('assets/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final categories = (manifest['categories'] as List)
        .cast<Map<String, dynamic>>();

    void expectTitles(Map<String, dynamic> item, String kind) {
      final id = item['id'] as String;
      final title = item['title'] as Map<String, dynamic>;
      for (final locale in locales) {
        final value = title[locale];
        expect(value, isA<String>(), reason: '$kind $id has no $locale title');
        expect(
          (value as String).trim(),
          isNotEmpty,
          reason: '$kind $id has an empty $locale title',
        );
        expect(
          value,
          isNot(id),
          reason: '$kind $id: $locale title is just the id',
        );
      }
    }

    test('every category has uk, en and ru titles', () {
      expect(categories, isNotEmpty);
      for (final category in categories) {
        expectTitles(category, 'category');
      }
    });

    test('categories are the ten from PLAN.md, in order, with its names', () {
      const approved = {
        'home': ['Уютный дом', 'Затишний дім', 'Cozy home'],
        'food': ['Вкусняшки', 'Смаколики', 'Treats'],
        'autumn': ['Осень', 'Осінь', 'Autumn'],
        'winter': ['Зима и праздники', 'Зима і свята', 'Winter & holidays'],
        'spring': ['Весна и сад', 'Весна і сад', 'Spring & garden'],
        'summer': ['Лето и пляж', 'Літо і пляж', 'Summer & beach'],
        'underwater': ['Под водой', 'Під водою', 'Under the sea'],
        'farm': ['На ферме', 'На фермі', 'On the farm'],
        'hobbies': ['Хобби', 'Хобі', 'Hobbies'],
        'travel': ['Путешествия', 'Подорожі', 'Travel'],
      };
      expect(categories.map((c) => c['id']), orderedEquals(approved.keys));
      for (final category in categories) {
        final id = category['id'] as String;
        final title = category['title'] as Map<String, dynamic>;
        final [ru, uk, en] = approved[id]!;
        expect(title['ru'], ru, reason: '$id ru');
        expect(title['uk'], uk, reason: '$id uk');
        expect(title['en'], en, reason: '$id en');
      }
    });

    test('every picture has uk, en and ru titles', () {
      final pictures = [
        for (final category in categories)
          ...(category['pictures'] as List).cast<Map<String, dynamic>>(),
      ];
      for (final picture in pictures) {
        expectTitles(picture, 'picture');
      }
    });
  });
}
