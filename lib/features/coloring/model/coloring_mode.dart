/// Coloring mode; persisted by [name].
enum ColoringMode {
  free,
  numbers,
  magic;

  /// The mode with [name], or null.
  static ColoringMode? fromName(Object? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

/// The active tool. The eraser is not available in magic mode.
enum ColoringTool { brush, eraser }
