/// The four brush size presets; persisted by [name]. [width] is the nominal
/// stroke width in canvas pixels (see `drawingCanvasWidth`); each tool scales
/// it by its `radiusFactor`.
enum BrushSize {
  small(12),
  medium(28),
  large(56),
  huge(112);

  const BrushSize(this.width);

  final double width;

  /// The size with [name], or null.
  static BrushSize? fromName(Object? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}
