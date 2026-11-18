import 'coloring_mode.dart';
import 'fill_state.dart';
import 'picture_meta.dart';

/// "Done" in free mode needs this share of regions filled: 4/5 = 80 %.
const int finishNumerator = 4;
const int finishDenominator = 5;

/// What a tap on a region does in the current mode.
sealed class TapRule {
  const TapRule();
}

/// Set the region to [color] (0 = erase).
class PaintRule extends TapRule {
  const PaintRule(this.color);
  final int color;
}

/// Numbers mode: the region's number differs from the selected one.
class RejectRule extends TapRule {
  const RejectRule();
}

/// Decides what a tap on [regionId] does (spec §2.5).
TapRule tapRule({
  required ColoringMode mode,
  required ColoringTool tool,
  required PictureMeta meta,
  required int regionId,
  required int selectedColor,
  required int? selectedPaletteIndex,
}) {
  switch (mode) {
    case ColoringMode.free:
      return PaintRule(tool == ColoringTool.eraser ? 0 : selectedColor);
    case ColoringMode.numbers:
      if (tool == ColoringTool.eraser) return const PaintRule(0);
      if (meta.region(regionId).paletteIndex != selectedPaletteIndex) {
        return const RejectRule();
      }
      return PaintRule(meta.correctColorOf(regionId));
    case ColoringMode.magic:
      return PaintRule(meta.correctColorOf(regionId));
  }
}

/// The color a magic-brush stroke paints on [regionId].
int strokeColor(PictureMeta meta, int regionId) =>
    meta.correctColorOf(regionId);

/// Numbers mode shows a region's number until it holds its correct palette
/// color; a color left from free mode still counts as to do (decision D1).
bool showsNumber(FillState fill, PictureMeta meta, int regionId) =>
    !fill.isCorrect(regionId, meta);

/// Whether [mode] considers the picture finished automatically. Numbers and
/// magic both need every region in its correct color: a color left from
/// free mode does not count (decision D1).
bool isComplete(ColoringMode mode, FillState fill, PictureMeta meta) {
  switch (mode) {
    case ColoringMode.free:
      return false;
    case ColoringMode.numbers || ColoringMode.magic:
      for (var id = 1; id <= meta.regionCount; id++) {
        if (!fill.isCorrect(id, meta)) return false;
      }
      return true;
  }
}

/// The "Done" button: free mode only, enabled at 80 % filled.
bool canFinish(ColoringMode mode, FillState fill) =>
    mode == ColoringMode.free &&
    fill.filledCount * finishDenominator >= fill.regionCount * finishNumerator;

/// The first palette index that still has a region without its correct
/// color, or 0 when every color is done.
int firstIncompletePaletteIndex(FillState fill, PictureMeta meta) {
  final progress = fill.paletteProgress(meta);
  for (var i = 0; i < progress.length; i++) {
    if (!progress[i].done) return i;
  }
  return 0;
}
