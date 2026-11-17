import 'dart:convert';
import 'dart:io';

import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = ContentManifest.fromJson(
    jsonDecode(File('assets/manifest.json').readAsStringSync()),
  );

  test('bundled manifest parses with unique ids and existing pictures', () {
    expect(manifest.categories, hasLength(10));
    final categoryIds = manifest.categories.map((c) => c.id).toList();
    expect(categoryIds.toSet().length, categoryIds.length);
    final ids = manifest.pictures.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final picture in manifest.pictures) {
      if (picture.free) {
        expect(
          File('${picture.assetPath!}lines.png').existsSync(),
          isTrue,
          reason: picture.id,
        );
      } else {
        expect(picture.url, isNotNull, reason: picture.id);
        expect(picture.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    }
  });

  test('titles resolve per language with an English fallback', () {
    final home = manifest.categoryById('home')!.title;
    expect(home.resolve('uk'), 'Затишний дім');
    expect(home.resolve('ru'), 'Уютный дом');
    expect(home.resolve('de'), 'Cozy home');
    expect(const LocalizedText({'uk': 'Лише'}).resolve('en'), 'Лише');
  });

  Map<String, Object?> picture(String id) => {
    'id': id,
    'title': {'en': id},
    'level': 'simple',
    'asset': 'coloring/free/$id/',
  };

  test('next picture stays in the category and wraps around', () {
    final twoPerCategory = ContentManifest.fromJson({
      'version': 1,
      'categories': [
        for (final category in ['home', 'farm'])
          {
            'id': category,
            'title': {'en': category},
            'pictures': [
              for (final n in [1, 2]) picture('${category}_$n'),
            ],
          },
      ],
    });
    expect(twoPerCategory.nextPicture('home_1')!.id, 'home_2');
    expect(twoPerCategory.nextPicture('home_2')!.id, 'home_1');
    expect(twoPerCategory.nextPicture('missing'), isNull);
    // Filtered: skips pictures that fail, null when none other passes.
    expect(
      twoPerCategory.nextPicture('home_1', where: (p) => p.id != 'home_2'),
      isNull,
    );
    // A category with one picture has no next one.
    final onePicture = ContentManifest.fromJson({
      'version': 1,
      'categories': [
        {
          'id': 'home',
          'title': {'en': 'home'},
          'pictures': [picture('home_1')],
        },
      ],
    });
    expect(onePicture.nextPicture('home_1'), isNull);
  });

  test('a picture without asset or url is rejected', () {
    expect(
      () => ContentManifest.fromJson({
        'version': 1,
        'categories': [
          {
            'id': 'home',
            'title': {'en': 'Home'},
            'pictures': [
              {
                'id': 'x',
                'title': {'en': 'X'},
                'level': 'simple',
              },
            ],
          },
        ],
      }),
      throwsFormatException,
    );
  });
}
