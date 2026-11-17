import 'package:coloring/features/catalog/domain/content_manifest.dart';

/// The bundled manifest has no pictures yet, so screen tests use this one:
/// an empty "Cozy home" and "On the farm" with a free "Piglet" and a paid
/// "Goat".
final testManifest = ContentManifest.fromJson({
  'version': 1,
  'categories': [
    {
      'id': 'home',
      'title': {'uk': 'Затишний дім', 'en': 'Cozy home', 'ru': 'Уютный дом'},
      'pictures': <Object>[],
    },
    {
      'id': 'farm',
      'title': {'uk': 'На фермі', 'en': 'On the farm', 'ru': 'На ферме'},
      'pictures': [
        {
          'id': 'farm_piglet_picnic',
          'title': {'uk': 'Порося', 'en': 'Piglet', 'ru': 'Поросёнок'},
          'characters': ['farm_piglet'],
          'level': 'simple',
          'free': true,
          'asset': 'coloring/free/farm_piglet_picnic/',
        },
        {
          'id': 'farm_goat_swing',
          'title': {'uk': 'Козеня', 'en': 'Goat', 'ru': 'Козлёнок'},
          'characters': ['farm_goat'],
          'level': 'detailed',
          'free': false,
          'url': 'farm/farm_goat_swing.zip',
          'thumbUrl': 'farm/farm_goat_swing_thumb.webp',
          'sha256': '${'0' * 63}1',
        },
      ],
    },
  ],
});
