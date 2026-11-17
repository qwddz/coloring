import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/content/content_config.dart';
import 'package:coloring/features/content/thumb_image.dart';

void main() {
  const entry = PictureEntry(
    id: 'home_fox_cocoa',
    categoryId: 'home',
    title: LocalizedText({'en': 'Fox'}),
    level: PictureLevel.simple,
    free: true,
    asset: 'coloring/free/home_fox_cocoa/',
    thumbUrl: 'thumbs/home_fox_cocoa.webp',
  );
  const base = 'https://cdn.test';

  test('the bundled thumb is used when this build ships it', () {
    expect(
      thumbImage(entry, base, {
        'assets/coloring/free/home_fox_cocoa/thumb.webp',
      }),
      isA<AssetImage>(),
    );
  });

  test('a thumb missing from this build falls back to the CDN', () {
    final image = thumbImage(entry, base, {});
    expect(
      (image! as NetworkImage).url,
      'https://cdn.test/thumbs/home_fox_cocoa.webp',
    );
    expect(thumbImage(entry, '', {}), isNull);
    expect(thumbImage(entry, base, null), isNull);
  });

  test('release builds need a CDN address', () {
    expect(
      () => checkCdnConfigured(release: true, baseUrl: ''),
      throwsStateError,
    );
    checkCdnConfigured(release: false, baseUrl: '');
    checkCdnConfigured(release: true, baseUrl: base);
  });
}
