import 'fill_state.dart';

/// One region's color change: [before] → [after] (ARGB, 0 = unfilled).
class RegionChange {
  const RegionChange(this.id, this.before, this.after);

  final int id;
  final int before;
  final int after;

  /// The change that undoes this one.
  RegionChange get reversed => RegionChange(id, after, before);

  @override
  bool operator ==(Object other) =>
      other is RegionChange &&
      other.id == id &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode => Object.hash(id, before, after);

  @override
  String toString() =>
      'RegionChange($id, '
      '0x${before.toRadixString(16)} -> 0x${after.toRadixString(16)})';
}

/// Pure-Dart bridge from the coloring controller to the canvas (the Flame
/// game implements it). Image points are in image px.
abstract interface class ColoringCanvasSink {
  /// Fill state changed; [changes] are the regions that changed in this step.
  /// [waveX]/[waveY] (image px) start a wave on the single changed region;
  /// null = no wave (undo, clear, stroke, restore).
  void showFill(
    FillState state,
    List<RegionChange> changes, {
    double? waveX,
    double? waveY,
  });

  /// Numbers mode selected palette index, null = off.
  void setHighlight(int? paletteIndex);

  /// Number labels; numbers mode only.
  void setLabelsEnabled(bool enabled);

  /// Numbers-mode wrong tap.
  void flashRejected(int regionId);

  /// Free-mode long press: show [color] on [regionId] for 600 ms.
  void showHint(int regionId, int color);
}
