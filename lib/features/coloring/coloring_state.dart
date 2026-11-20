import 'data/picture_loader.dart';
import 'model/coloring_mode.dart';
import 'model/fill_state.dart';

/// What the coloring screen shows: an immutable snapshot taken after every
/// command of the coloring controller.
class ColoringState {
  const ColoringState({
    required this.picture,
    required this.mode,
    required this.tool,
    required this.selectedColor,
    required this.selectedPaletteIndex,
    required this.canUndo,
    required this.canFinish,
    required this.filledFraction,
    required this.paletteProgress,
    required this.completed,
    this.completionSeq = 0,
    this.rejectSeq = 0,
  });

  /// The opened picture. The controller owns its images; a widget or game
  /// that keeps an image takes its own `clone()`.
  final LoadedPicture picture;

  final ColoringMode mode;
  final ColoringTool tool;

  /// ARGB brush color.
  final int selectedColor;

  /// Always set in numbers mode; elsewhere the picture palette index of
  /// [selectedColor], or null for a color outside the picture palette.
  final int? selectedPaletteIndex;

  final bool canUndo;

  /// Free mode, at least 80 % filled: the "Done" button is enabled.
  final bool canFinish;

  /// Filled regions / all regions.
  final double filledFraction;

  /// Per picture color: regions holding it / regions that need it.
  final List<PaletteProgress> paletteProgress;

  /// The work has been completed (the star); stays true after later edits.
  final bool completed;

  /// Grows by one on every completion, for one-shot UI (the overlay).
  final int completionSeq;

  /// Grows by one on every rejected numbers-mode tap.
  final int rejectSeq;

  /// The picture's own colors, in palette order.
  List<int> get picturePalette => picture.meta.palette;

  /// Numbers mode: the selected number still has regions to color, so
  /// "find" has somewhere to go.
  bool get canFind {
    final index = selectedPaletteIndex;
    return mode == ColoringMode.numbers &&
        index != null &&
        index < paletteProgress.length &&
        !paletteProgress[index].done;
  }
}
