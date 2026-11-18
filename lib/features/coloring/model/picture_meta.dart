/// The largest region count a picture may have: the state texture is
/// (N + 1) texels wide and must stay within 4096.
const int maxRegionCount = 4095;

/// The largest picture side (px) accepted from `regions.json`.
const int maxPictureSide = 4096;

/// The largest palette accepted from `regions.json`.
const int maxPaletteLength = 256;

/// One region of a picture, as described in `regions.json`.
class RegionInfo {
  const RegionInfo({
    required this.id,
    required this.paletteIndex,
    required this.color,
    required this.area,
    required this.bboxX,
    required this.bboxY,
    required this.bboxWidth,
    required this.bboxHeight,
    required this.labelX,
    required this.labelY,
    required this.labelRadius,
  });

  final int id;

  /// 0-based index into [PictureMeta.palette].
  final int paletteIndex;

  /// The pipeline's original color (ARGB). Unused in Stage 1.
  final int color;

  /// Pixel count.
  final int area;

  final int bboxX;
  final int bboxY;
  final int bboxWidth;
  final int bboxHeight;

  /// Image px of the number label (always inside the region).
  final double labelX;
  final double labelY;
  final double labelRadius;

  /// The number shown to the user.
  int get number => paletteIndex + 1;
}

/// The parsed `regions.json` of a picture.
class PictureMeta {
  PictureMeta({
    required this.width,
    required this.height,
    required this.level,
    required this.backgroundId,
    required List<int> palette,
    required List<RegionInfo> regions,
  }) : palette = List.unmodifiable(palette),
       regions = List.unmodifiable(regions);

  /// Parses and validates `regions.json`. Throws [FormatException] when the
  /// data is malformed: ids are not exactly `1..N`, a palette index is out of
  /// range, a color is not `#rrggbb`, the size is not 1..[maxPictureSide],
  /// the palette is not 1..[maxPaletteLength] long, or a region's numbers
  /// are not finite, its bbox or label leave the image, or its label radius
  /// is not positive.
  factory PictureMeta.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('regions.json: not an object');
    }
    final width = _side(json['width'], 'width');
    final height = _side(json['height'], 'height');
    final level = json['level'];
    if (level is! String) throw const FormatException('regions.json: level');
    final rawPalette = json['palette'];
    if (rawPalette is! List ||
        rawPalette.isEmpty ||
        rawPalette.length > maxPaletteLength) {
      throw const FormatException('regions.json: palette');
    }
    final palette = [for (final c in rawPalette) parseHexColor(c)];
    final rawRegions = json['regions'];
    if (rawRegions is! List || rawRegions.isEmpty) {
      throw const FormatException('regions.json: regions');
    }
    final count = rawRegions.length;
    if (count > maxRegionCount) {
      throw FormatException('regions.json: $count regions > $maxRegionCount');
    }
    final slots = List<RegionInfo?>.filled(count, null);
    for (final raw in rawRegions) {
      final region = _parseRegion(raw, palette.length, width, height);
      if (region.id < 1 || region.id > count || slots[region.id - 1] != null) {
        throw FormatException('regions.json: ids are not 1..$count', region.id);
      }
      slots[region.id - 1] = region;
    }
    final backgroundId = _int(json['background'], 'background');
    if (backgroundId < 1 || backgroundId > count) {
      throw FormatException('regions.json: background', backgroundId);
    }
    return PictureMeta(
      width: width,
      height: height,
      level: level,
      backgroundId: backgroundId,
      palette: palette,
      regions: [for (final r in slots) r!],
    );
  }

  final int width;
  final int height;

  /// `simple` or `medium`.
  final String level;
  final int backgroundId;

  /// ARGB colors with alpha 0xFF.
  final List<int> palette;

  /// Indexed so that `regions[id - 1].id == id`.
  final List<RegionInfo> regions;

  /// N: region ids are `1..N`.
  int get regionCount => regions.length;

  RegionInfo region(int id) => regions[id - 1];

  /// The color that counts as correct for region [id] in every mode.
  int correctColorOf(int id) => palette[regions[id - 1].paletteIndex];

  static RegionInfo _parseRegion(
    Object? raw,
    int paletteLength,
    int width,
    int height,
  ) {
    if (raw is! Map) throw const FormatException('regions.json: region');
    final id = _int(raw['id'], 'id');
    final paletteIndex = _int(raw['palette'], 'palette');
    if (paletteIndex < 0 || paletteIndex >= paletteLength) {
      throw FormatException('regions.json: palette index of $id', paletteIndex);
    }
    final bbox = raw['bbox'];
    final label = raw['label'];
    if (bbox is! List || bbox.length != 4) {
      throw FormatException('regions.json: bbox of $id');
    }
    if (label is! List || label.length != 2) {
      throw FormatException('regions.json: label of $id');
    }
    final region = RegionInfo(
      id: id,
      paletteIndex: paletteIndex,
      color: parseHexColor(raw['color']),
      area: _int(raw['area'], 'area'),
      bboxX: _int(bbox[0], 'bbox'),
      bboxY: _int(bbox[1], 'bbox'),
      bboxWidth: _int(bbox[2], 'bbox'),
      bboxHeight: _int(bbox[3], 'bbox'),
      labelX: _double(label[0], 'label'),
      labelY: _double(label[1], 'label'),
      labelRadius: _double(raw['label_radius'], 'label_radius'),
    );
    if (region.area < 0) {
      throw FormatException('regions.json: area of $id', region.area);
    }
    if (region.bboxX < 0 ||
        region.bboxY < 0 ||
        region.bboxWidth < 0 ||
        region.bboxHeight < 0 ||
        region.bboxX + region.bboxWidth > width ||
        region.bboxY + region.bboxHeight > height) {
      throw FormatException('regions.json: bbox of $id outside the image');
    }
    if (region.labelX < 0 ||
        region.labelX > width ||
        region.labelY < 0 ||
        region.labelY > height) {
      throw FormatException('regions.json: label of $id outside the image');
    }
    if (region.labelRadius <= 0) {
      throw FormatException(
        'regions.json: label_radius of $id must be > 0',
        region.labelRadius,
      );
    }
    return region;
  }
}

final _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Parses `#rrggbb` into an opaque ARGB int. Throws [FormatException].
int parseHexColor(Object? value) {
  if (value is! String || !_hexColor.hasMatch(value)) {
    throw FormatException('Not a #rrggbb color', value);
  }
  return 0xFF000000 | int.parse(value.substring(1), radix: 16);
}

int _int(Object? value, String name) {
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('regions.json: $name is not an int', value);
}

int _side(Object? value, String name) {
  final v = _int(value, name);
  if (v <= 0 || v > maxPictureSide) {
    throw FormatException('regions.json: $name must be 1..$maxPictureSide', v);
  }
  return v;
}

/// A finite number (NaN and infinity are refused).
double _double(Object? value, String name) {
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('regions.json: $name is not a finite number', value);
}
