import 'dart:collection';

import 'canvas_sink.dart';

export 'canvas_sink.dart' show RegionChange;

/// Undo steps (no redo). Each step is the list of changes one command made.
class UndoHistory {
  UndoHistory({this.capacity = defaultCapacity});

  static const int defaultCapacity = 50;

  final int capacity;
  final _steps = ListQueue<List<RegionChange>>();

  bool get canUndo => _steps.isNotEmpty;

  int get length => _steps.length;

  /// Records a step; an empty step is ignored. Past [capacity] the oldest
  /// step is dropped.
  void push(List<RegionChange> step) {
    if (step.isEmpty) return;
    _steps.addLast(List.unmodifiable(step));
    while (_steps.length > capacity) {
      _steps.removeFirst();
    }
  }

  /// Pops the latest step and returns the changes that undo it (reversed
  /// order, before/after swapped), or null when there is nothing to undo.
  List<RegionChange>? undo() {
    if (_steps.isEmpty) return null;
    final step = _steps.removeLast();
    return [for (final c in step.reversed) c.reversed];
  }

  void clear() => _steps.clear();
}
