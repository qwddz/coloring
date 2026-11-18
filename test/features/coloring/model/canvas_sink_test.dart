import 'package:coloring/features/coloring/model/canvas_sink.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// A recording sink, as the controller tests will use.
class _RecordingSink implements ColoringCanvasSink {
  final calls = <String>[];

  @override
  void showFill(
    FillState state,
    List<RegionChange> changes, {
    double? waveX,
    double? waveY,
  }) => calls.add('fill ${changes.length} $waveX $waveY');

  @override
  void setHighlight(int? paletteIndex) => calls.add('highlight $paletteIndex');

  @override
  void setLabelsEnabled(bool enabled) => calls.add('labels $enabled');

  @override
  void flashRejected(int regionId) => calls.add('flash $regionId');

  @override
  void showHint(int regionId, int color) => calls.add('hint $regionId $color');
}

void main() {
  test('RegionChange has value equality and reverses', () {
    const c = RegionChange(3, 0, 0xFFFF0000);
    expect(c, const RegionChange(3, 0, 0xFFFF0000));
    expect(c.hashCode, const RegionChange(3, 0, 0xFFFF0000).hashCode);
    expect(c, isNot(const RegionChange(3, 0, 0xFF00FF00)));
    expect(c.reversed, const RegionChange(3, 0xFFFF0000, 0));
    expect(c.toString(), 'RegionChange(3, 0x0 -> 0xffff0000)');
  });

  test('a pure-Dart sink can implement the interface', () {
    final sink = _RecordingSink();
    final ColoringCanvasSink asSink = sink;
    asSink
      ..showFill(
        FillState(2),
        const [RegionChange(1, 0, 1)],
        waveX: 1.5,
        waveY: 2,
      )
      ..showFill(FillState(2), const [])
      ..setHighlight(null)
      ..setLabelsEnabled(true)
      ..flashRejected(4)
      ..showHint(2, 7);
    expect(sink.calls, [
      'fill 1 1.5 2.0',
      'fill 0 null null',
      'highlight null',
      'labels true',
      'flash 4',
      'hint 2 7',
    ]);
  });
}
