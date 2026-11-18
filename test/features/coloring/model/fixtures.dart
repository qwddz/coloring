import 'dart:typed_data';

import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/coloring_session.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:coloring/features/coloring/model/picture_meta.dart';
import 'package:coloring/features/coloring/model/region_map.dart';

/// A synthetic 16×12 picture: 5 regions separated by 1 px lines (0).
/// Column 6 is a line in rows 0–7, rows 4 and 8 are full lines.
const fixtureRows = [
  '1111110222222222',
  '1111110222222222',
  '1111110222222222',
  '1111110222222222',
  '0000000000000000',
  '3333330444444444',
  '3333330444444444',
  '3333330444444444',
  '0000000000000000',
  '5555555555555555',
  '5555555555555555',
  '5555555555555555',
];

const fixtureWidth = 16;
const fixtureHeight = 12;

const red = 0xFFFF0000;
const green = 0xFF00FF00;
const blue = 0xFF0000FF;

/// A color outside the picture palette (a "base" color).
const base = 0xFF123456;

/// Palette index per region id 1..5.
const fixturePaletteIndex = {1: 0, 2: 1, 3: 2, 4: 0, 5: 1};

/// Label (image px) inside each region.
const fixtureLabels = {
  1: (2.5, 1.5),
  2: (10.5, 1.5),
  3: (2.5, 6.5),
  4: (10.5, 6.5),
  5: (8.5, 10.5),
};

Map<String, Object?> fixtureJson() => {
  'width': fixtureWidth,
  'height': fixtureHeight,
  'level': 'simple',
  'background': 5,
  'palette': ['#ff0000', '#00ff00', '#0000ff'],
  'regions': [
    for (final e in fixturePaletteIndex.entries)
      {
        'id': e.key,
        'palette': e.value,
        'color': '#808080',
        'area': 10,
        'bbox': [0, 0, 1, 1],
        'label': [fixtureLabels[e.key]!.$1, fixtureLabels[e.key]!.$2],
        'label_radius': 1.5,
      },
  ],
};

PictureMeta fixtureMeta() => PictureMeta.fromJson(fixtureJson());

Uint16List idsFromRows(List<String> rows) => Uint16List.fromList([
  for (final row in rows)
    for (final c in row.split('')) int.parse(c),
]);

/// RGBA bytes of [ids] as regions.png would decode (R = high, G = low byte).
Uint8List rgbaFromIds(Uint16List ids) {
  final out = Uint8List(ids.length * 4);
  for (var i = 0; i < ids.length; i++) {
    out[i * 4] = ids[i] >> 8;
    out[i * 4 + 1] = ids[i] & 0xFF;
    out[i * 4 + 2] = 0;
    out[i * 4 + 3] = 255;
  }
  return out;
}

RegionMap fixtureMap() =>
    RegionMap(fixtureWidth, fixtureHeight, idsFromRows(fixtureRows));

ColoringSession fixtureSession({
  ColoringMode mode = ColoringMode.free,
  FillState? fill,
}) => ColoringSession(
  meta: fixtureMeta(),
  map: fixtureMap(),
  fill: fill,
  mode: mode,
);

/// Taps the label of region [id] with the default test tolerance.
FillResult tapRegion(ColoringSession s, int id) {
  final (x, y) = fixtureLabels[id]!;
  return s.tap(x, y, tolerance: 4);
}
