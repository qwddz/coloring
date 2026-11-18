import 'package:coloring/features/coloring/model/undo_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts empty; undo returns null', () {
    final h = UndoHistory();
    expect(h.canUndo, isFalse);
    expect(h.undo(), isNull);
    expect(h.capacity, 50);
  });

  test('empty steps are ignored', () {
    final h = UndoHistory()..push([]);
    expect(h.canUndo, isFalse);
  });

  test('undo pops the latest step first, reversed and swapped', () {
    final h = UndoHistory()
      ..push([const RegionChange(1, 0, 10)])
      ..push([const RegionChange(2, 0, 20), const RegionChange(3, 5, 30)]);
    expect(h.undo(), [
      const RegionChange(3, 30, 5),
      const RegionChange(2, 20, 0),
    ]);
    expect(h.undo(), [const RegionChange(1, 10, 0)]);
    expect(h.canUndo, isFalse);
  });

  test('the cap of 50 drops the oldest step', () {
    final h = UndoHistory();
    for (var i = 1; i <= 51; i++) {
      h.push([RegionChange(i, 0, i)]);
    }
    expect(h.length, 50);
    final undone = <int>[];
    while (h.canUndo) {
      undone.add(h.undo()!.single.id);
    }
    expect(undone, [for (var i = 51; i >= 2; i--) i]);
  });

  test('a pushed step is not affected by later changes to the list', () {
    final step = [const RegionChange(1, 0, 1)];
    final h = UndoHistory()..push(step);
    step.add(const RegionChange(2, 0, 2));
    expect(h.undo(), hasLength(1));
  });

  test('clear empties the history', () {
    final h = UndoHistory()..push([const RegionChange(1, 0, 1)]);
    h.clear();
    expect(h.canUndo, isFalse);
  });
}
