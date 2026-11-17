import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/content/content_config.dart';
import 'package:flutter_test/flutter_test.dart';

ContentManifest parse(List<Map<String, Object?>> pictures, {int version = 2}) =>
    ContentManifest.fromJson({
      'version': version,
      'categories': [
        {
          'id': 'home',
          'title': {'en': 'Home'},
          'pictures': pictures,
        },
      ],
    });

Map<String, Object?> picture({
  String id = 'x',
  Object? level = 'simple',
  String? asset = 'coloring/free/x/',
}) => {
  'id': id,
  'title': {'en': 'X'},
  'level': ?level,
  'asset': ?asset,
};

void main() {
  final hash = 'ab' * 32;

  test('reads the PLAN.md picture schema', () {
    final manifest = ContentManifest.fromJson({
      'version': 7,
      'minAppVersion': '1.3.0',
      'categories': [
        {
          'id': 'home',
          'title': {
            'uk': 'Затишний дім',
            'en': 'Cozy home',
            'ru': 'Уютный дом',
          },
          'pictures': [
            {
              'id': 'home_fox_cocoa',
              'title': {'en': 'Fox with cocoa'},
              'characters': ['canines_fox'],
              'level': 'simple',
              'free': true,
              'asset': 'coloring/free/home_fox_cocoa/',
            },
            {
              'id': 'home_hamster_book',
              'title': {'en': 'Hamster reading'},
              'characters': ['pets_hamster', 'pets_mouse'],
              'level': 'detailed',
              'free': false,
              'url': 'https://cdn.example.com/home/home_hamster_book.zip',
              'thumbUrl': 'home/home_hamster_book_thumb.webp',
              'sha256': hash,
              'bytes': 612345,
            },
          ],
        },
      ],
    });
    expect(manifest.version, 7);
    expect(manifest.minAppVersion, '1.3.0');
    final fox = manifest.pictureById('home_fox_cocoa')!;
    expect(fox.categoryId, 'home');
    expect(fox.level, PictureLevel.simple);
    expect(fox.free, isTrue);
    expect(fox.characters, ['canines_fox']);
    expect(fox.assetPath, 'assets/coloring/free/home_fox_cocoa/');
    expect(
      fox.thumbAssetPath,
      'assets/coloring/free/home_fox_cocoa/thumb.webp',
    );
    expect(fox.url, isNull);
    final hamster = manifest.pictureById('home_hamster_book')!;
    expect(hamster.level, PictureLevel.detailed);
    expect(hamster.free, isFalse);
    expect(hamster.characters, ['pets_hamster', 'pets_mouse']);
    expect(hamster.assetPath, isNull);
    expect(hamster.url, 'https://cdn.example.com/home/home_hamster_book.zip');
    expect(hamster.sha256, hash);
    expect(hamster.bytes, 612345);
    expect(hamster.thumbAssetPath, isNull);
    expect(hamster.thumbUrl, 'home/home_hamster_book_thumb.webp');
  });

  test('an asset folder without a trailing slash still ends with one', () {
    final entry = parse([picture(asset: 'coloring/free/x')]).pictures.single;
    expect(entry.assetPath, 'assets/coloring/free/x/');
    expect(entry.thumbAssetPath, 'assets/coloring/free/x/thumb.webp');
  });

  test('an explicit thumb wins over the asset folder one', () {
    final entry = parse([
      {...picture(), 'thumb': 'thumbs/x.webp'},
    ]).pictures.single;
    expect(entry.thumbAssetPath, 'assets/thumbs/x.webp');
  });

  test('characters default to none, free to false', () {
    final entry = parse([picture()]).pictures.single;
    expect(entry.characters, isEmpty);
    expect(entry.free, isFalse);
  });

  test('a missing or unknown level is rejected', () {
    expect(() => parse([picture(level: null)]), throwsFormatException);
    expect(() => parse([picture(level: 'hard')]), throwsFormatException);
  });

  test('minAppVersion defaults to 1.0.0', () {
    expect(parse(const []).minAppVersion, '1.0.0');
  });

  test('a url without sha256 is rejected', () {
    expect(
      () => parse([
        {...picture(asset: null), 'url': 'home/x.zip'},
      ]),
      throwsFormatException,
    );
    expect(() => parse([picture(asset: null)]), throwsFormatException);
  });

  test('ids that are not safe file names are rejected', () {
    for (final id in ['../x', 'Home', 'a b', '', 'a/b']) {
      expect(() => parse([picture(id: id)]), throwsFormatException, reason: id);
      expect(
        () => parse([
          {
            ...picture(),
            'characters': [id],
          },
        ]),
        throwsFormatException,
        reason: 'character $id',
      );
      expect(
        () => ContentManifest.fromJson({
          'version': 1,
          'categories': [
            {
              'id': id,
              'title': {'en': 'X'},
              'pictures': const [],
            },
          ],
        }),
        throwsFormatException,
        reason: id,
      );
    }
  });

  test('malformed CDN addresses resolve to null', () {
    expect(resolveCdnUrl('https://cdn.test', 'http://[::1'), isNull);
    expect(resolveCdnUrl('http://[::1', 'home/a.zip'), isNull);
  });

  test('relative CDN paths resolve against the base URL', () {
    expect(
      resolveCdnUrl('https://cdn.test/content', 'home/a.zip').toString(),
      'https://cdn.test/content/home/a.zip',
    );
    expect(
      resolveCdnUrl('https://cdn.test/content/', '/manifest.json').toString(),
      'https://cdn.test/content/manifest.json',
    );
    expect(
      resolveCdnUrl('', 'https://other.test/a.zip').toString(),
      'https://other.test/a.zip',
    );
    expect(resolveCdnUrl('', 'home/a.zip'), isNull);
  });
}
