/// Text in several languages, keyed by language code.
class LocalizedText {
  const LocalizedText(this._values);

  final Map<String, String> _values;

  /// Falls back to English, then to any available language.
  String resolve(String languageCode) =>
      _values[languageCode] ?? _values['en'] ?? _values.values.first;

  static LocalizedText fromJson(Object? json) {
    final map = (json as Map<String, Object?>).cast<String, String>();
    if (map.isEmpty) throw const FormatException('empty title');
    return LocalizedText(Map.unmodifiable(map));
  }
}

/// How much there is to color: «Простая» has 12–40 large regions,
/// «Подробная» 50–150 with a background.
enum PictureLevel {
  simple,
  detailed;

  static PictureLevel fromJson(Object? json) => switch (json) {
    'simple' => simple,
    'detailed' => detailed,
    _ => throw FormatException('bad level', json),
  };
}

class PictureEntry {
  const PictureEntry({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.level,
    required this.free,
    this.characters = const [],
    this.asset,
    this.url,
    this.sha256,
    this.bytes,
    this.thumb,
    this.thumbUrl,
  });

  final String id;
  final String categoryId;
  final LocalizedText title;
  final PictureLevel level;
  final bool free;

  /// Animosaic picture ids of the characters in the scene, like
  /// `canines_fox`; they link a coloring page to its puzzle.
  final List<String> characters;

  /// Folder inside `assets/` with the picture layers, for pictures bundled
  /// with the app, like `coloring/free/home_fox_cocoa/`.
  final String? asset;

  /// CDN address of the zip with the picture layers, relative to the CDN
  /// base URL or absolute. Comes with [sha256] of the zip and optionally
  /// its size in [bytes].
  final String? url;
  final String? sha256;
  final int? bytes;

  /// Small preview inside `assets/`, or on the CDN when only [thumbUrl] is
  /// set. A bundled picture without [thumb] uses `thumb.webp` from its
  /// [asset] folder.
  final String? thumb;
  final String? thumbUrl;

  /// Folder of the bundled layers, ending with `/`.
  String? get assetPath {
    final asset = this.asset;
    if (asset == null) return null;
    return asset.endsWith('/') ? 'assets/$asset' : 'assets/$asset/';
  }

  String? get thumbAssetPath {
    final thumb = this.thumb;
    if (thumb != null) return 'assets/$thumb';
    final folder = assetPath;
    return folder == null ? null : '${folder}thumb.webp';
  }
}

class CategoryEntry {
  const CategoryEntry({
    required this.id,
    required this.title,
    required this.pictures,
  });

  final String id;
  final LocalizedText title;
  final List<PictureEntry> pictures;
}

/// Content catalog described in `PLAN.md` («Манифест»): categories with
/// coloring pictures.
class ContentManifest {
  const ContentManifest({
    required this.version,
    required this.categories,
    this.minAppVersion = '1.0.0',
  });

  final int version;

  /// Oldest app version that understands this manifest.
  final String minAppVersion;
  final List<CategoryEntry> categories;

  /// All pictures in catalog order.
  List<PictureEntry> get pictures => [
    for (final category in categories) ...category.pictures,
  ];

  PictureEntry? pictureById(String id) {
    for (final picture in pictures) {
      if (picture.id == id) return picture;
    }
    return null;
  }

  CategoryEntry? categoryById(String id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  /// Picture after [id] in its category that passes [where], wrapping
  /// around to the first one. Null when no other picture passes.
  PictureEntry? nextPicture(String id, {bool Function(PictureEntry)? where}) {
    final picture = pictureById(id);
    if (picture == null) return null;
    final siblings = categoryById(picture.categoryId)!.pictures;
    final index = siblings.indexWhere((p) => p.id == id);
    for (var step = 1; step < siblings.length; step++) {
      final candidate = siblings[(index + step) % siblings.length];
      if (where == null || where(candidate)) return candidate;
    }
    return null;
  }

  static ContentManifest fromJson(Object? json) {
    final map = json as Map<String, Object?>;
    final categories = <CategoryEntry>[];
    for (final rawCategory in map['categories'] as List) {
      final category = rawCategory as Map<String, Object?>;
      final categoryId = _id(category['id']);
      categories.add(
        CategoryEntry(
          id: categoryId,
          title: LocalizedText.fromJson(category['title']),
          pictures: List.unmodifiable([
            for (final rawPicture in category['pictures'] as List)
              _pictureFromJson(rawPicture as Map<String, Object?>, categoryId),
          ]),
        ),
      );
    }
    return ContentManifest(
      version: map['version'] as int,
      minAppVersion: map['minAppVersion'] as String? ?? '1.0.0',
      categories: List.unmodifiable(categories),
    );
  }

  static final _idPattern = RegExp(r'^[a-z0-9_]+$');

  /// Ids become file names, so only lowercase letters, digits and `_`.
  static String _id(Object? json) {
    final id = json as String;
    if (!_idPattern.hasMatch(id)) throw FormatException('bad id', id);
    return id;
  }

  static PictureEntry _pictureFromJson(
    Map<String, Object?> json,
    String categoryId,
  ) {
    final asset = json['asset'] as String?;
    final url = json['url'] as String?;
    final sha256 = json['sha256'] as String?;
    if (asset == null && (url == null || sha256 == null)) {
      throw FormatException(
        'picture ${json['id']} has no asset or url + sha256',
      );
    }
    return PictureEntry(
      id: _id(json['id']),
      categoryId: categoryId,
      title: LocalizedText.fromJson(json['title']),
      level: PictureLevel.fromJson(json['level']),
      free: json['free'] as bool? ?? false,
      characters: List.unmodifiable([
        for (final character in json['characters'] as List? ?? const [])
          _id(character),
      ]),
      asset: asset,
      url: url,
      sha256: sha256,
      bytes: json['bytes'] as int?,
      thumb: json['thumb'] as String?,
      thumbUrl: json['thumbUrl'] as String?,
    );
  }
}
