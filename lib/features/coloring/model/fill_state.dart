import 'dart:typed_data';

import 'picture_meta.dart';

/// Progress of one palette color: [correct] of [total] regions hold it.
class PaletteProgress {
  const PaletteProgress(this.correct, this.total);

  final int correct;
  final int total;

  bool get done => correct == total;

  @override
  bool operator ==(Object other) =>
      other is PaletteProgress &&
      other.correct == correct &&
      other.total == total;

  @override
  int get hashCode => Object.hash(correct, total);

  @override
  String toString() => 'PaletteProgress($correct/$total)';
}

/// One color per region. Index 0 is unused; 0 = unfilled (shown white),
/// anything else is ARGB with alpha 0xFF.
class FillState {
  FillState(int regionCount)
    : colors = Uint32List(regionCount + 1),
      wasReset = false;

  FillState._(this.colors, this.wasReset);

  /// Restores saved colors. A length other than `regionCount + 1` or an
  /// invalid value gives an empty state with [wasReset] set; never throws.
  factory FillState.fromList(List<int> list, int regionCount) {
    if (list.length != regionCount + 1 || !list.every(isValidColor)) {
      return FillState._(Uint32List(regionCount + 1), true);
    }
    final colors = Uint32List.fromList(list);
    colors[0] = 0;
    return FillState._(colors, false);
  }

  /// Length N + 1.
  final Uint32List colors;

  /// True when [FillState.fromList] had to drop the saved colors.
  final bool wasReset;

  /// Whether [color] can be stored: 0, or opaque 32-bit ARGB.
  static bool isValidColor(int color) =>
      color == 0 || (color >= 0xFF000000 && color <= 0xFFFFFFFF);

  int get regionCount => colors.length - 1;

  int colorOf(int id) => colors[id];

  bool isFilled(int id) => colors[id] != 0;

  /// Whether region [id] holds its correct palette color.
  bool isCorrect(int id, PictureMeta meta) =>
      colors[id] == meta.correctColorOf(id);

  int get filledCount {
    var n = 0;
    for (var id = 1; id < colors.length; id++) {
      if (colors[id] != 0) n++;
    }
    return n;
  }

  /// Filled regions / N (by region count, not area).
  double get filledFraction => regionCount == 0 ? 0 : filledCount / regionCount;

  /// For each palette index: regions of that index holding `palette[index]`.
  List<PaletteProgress> paletteProgress(PictureMeta meta) {
    final correct = List<int>.filled(meta.palette.length, 0);
    final total = List<int>.filled(meta.palette.length, 0);
    for (final r in meta.regions) {
      total[r.paletteIndex]++;
      if (colors[r.id] == meta.palette[r.paletteIndex]) {
        correct[r.paletteIndex]++;
      }
    }
    return [
      for (var i = 0; i < total.length; i++)
        PaletteProgress(correct[i], total[i]),
    ];
  }

  /// Sets region [id]. Only `ColoringSession` calls this, so undo stays
  /// consistent.
  void setColor(int id, int color) {
    assert(id > 0 && isValidColor(color));
    colors[id] = color;
  }

  List<int> toList() => List<int>.of(colors);

  FillState copy() => FillState._(Uint32List.fromList(colors), false);
}
