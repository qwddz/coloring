import 'dart:math';

import 'package:coloring/features/drawing/model/drawing_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simulates the render engine with integer image handles. Each image's
/// content is the list of ops drawn into it since state 0, so a wrong plan
/// shows up as wrong content; every handle is checked against disposal.
class Harness {
  Harness({int checkpointEvery = defaultCheckpointEvery})
    : history = DrawingHistory<int, int>(
        initial: 0,
        checkpointEvery: checkpointEvery,
      ) {
    content[0] = const [];
  }

  final DrawingHistory<int, int> history;
  final Map<int, List<int>> content = {};
  final Set<int> disposed = {};
  int _nextImage = 1;
  int _nextOp = 1;

  /// The ops of the current branch, state i = first i of them.
  final List<int> line = [];
  int maxReplay = 0;

  int get k => history.checkpointEvery;

  int get maxCheckpoints => (drawingMaxUndo + k - 1) ~/ k + 1;

  int _newImage(List<int> c) {
    final img = _nextImage++;
    content[img] = c;
    return img;
  }

  void _dispose(List<int> images) {
    for (final img in images) {
      expect(disposed.add(img), isTrue, reason: 'image $img disposed twice');
      expect(content.remove(img), isNotNull);
    }
  }

  void push() {
    final committed = history.committed;
    expect(disposed, isNot(contains(committed)));
    final op = _nextOp++;
    final img = _newImage([...content[committed]!, op]);
    line
      ..removeRange(history.cursor, line.length)
      ..add(op);
    _dispose(history.push(op, img));
    expect(history.canRedo, isFalse, reason: 'redo cleared on push');
    check();
  }

  bool undo() => _run(history.planUndo(), undo: true);

  bool redo() => _run(history.planRedo(), undo: false);

  bool _run(HistoryPlan<int, int>? plan, {required bool undo}) {
    if (plan == null) return false;
    expect(disposed, isNot(contains(plan.base)), reason: 'base reused');
    if (undo) {
      expect(plan.ops.length, lessThanOrEqualTo(k - 1));
    } else {
      expect(plan.ops.length, lessThanOrEqualTo(1));
    }
    maxReplay = max(maxReplay, plan.ops.length);
    final result = plan.ops.isEmpty
        ? plan.base
        : _newImage([...content[plan.base]!, ...plan.ops]);
    _dispose(history.apply(plan, result));
    check();
    return true;
  }

  void check() {
    final h = history;
    expect(disposed, isNot(contains(h.committed)));
    expect(content[h.committed], line.sublist(0, h.cursor));
    expect(h.top, line.length);
    // Multiples of K in a range of 30 + K − 1 states: ceil(30 / K) + 1.
    expect(h.checkpointCount, lessThanOrEqualTo(maxCheckpoints));
    final held = h.images.toSet();
    expect(held.intersection(disposed), isEmpty, reason: 'disposed held');
    expect(
      content.keys.toSet(),
      held,
      reason: 'every live image is held (no leaks)',
    );
    if (h.canUndo) {
      expect(h.cursor - 1, greaterThanOrEqualTo(h.top - drawingMaxUndo));
    }
  }
}

/// Checkpoint states `i % k == 0` in `lo..hi`.
int multiples(int lo, int hi, int k) => [
  for (var i = lo; i <= hi; i++)
    if (i % k == 0) i,
].length;

/// The production K plus the K = 15 the scripted cases were first written
/// for.
final List<int> ks = {defaultCheckpointEvery, 15}.toList();

void main() {
  for (final k in ks) {
    test(
      'K = $k keeps at most ceil(30 / K) + 1 checkpoints besides committed',
      () {
        expect(
          Harness(checkpointEvery: k).maxCheckpoints,
          (drawingMaxUndo / k).ceil() + 1,
        );
      },
    );
  }

  test('K = 15 keeps at most 3, K = 10 at most 4', () {
    expect(Harness(checkpointEvery: 15).maxCheckpoints, 3);
    expect(Harness(checkpointEvery: 10).maxCheckpoints, 4);
  });

  test('starts empty', () {
    final h = Harness();
    expect(h.history.canUndo, isFalse);
    expect(h.history.canRedo, isFalse);
    expect(h.history.planUndo(), isNull);
    expect(h.history.planRedo(), isNull);
    expect(h.history.committed, 0);
    expect(h.history.images, [0]);
  });

  for (final k in ks) {
    test('push K = $k: the committed image is the checkpoint, no copy', () {
      final h = Harness(checkpointEvery: k);
      for (var i = 0; i < k; i++) {
        h.push();
      }
      // State 0 and state K are both checkpoints; K is committed.
      expect(h.history.checkpointCount, 1);
      expect(h.history.images, hasLength(2));
      // Undo to K − 1 replays K − 1 ops from state 0.
      final plan = h.history.planUndo()!;
      expect(plan.base, 0);
      expect(plan.ops, hasLength(k - 1));
    });
  }

  test('push 30, undo all the way and redo all the way', () {
    final h = Harness();
    for (var i = 0; i < 30; i++) {
      h.push();
    }
    var undos = 0;
    while (h.undo()) {
      undos++;
    }
    expect(undos, 30);
    expect(h.history.cursor, 0);
    expect(h.history.committed, 0, reason: 'state 0 is the loaded image');
    var redos = 0;
    while (h.redo()) {
      redos++;
    }
    expect(redos, 30);
  });

  for (final k in ks) {
    test('K = $k: at 45 ops undo stops after 30 steps, at state 15', () {
      final h = Harness(checkpointEvery: k);
      for (var i = 0; i < 45; i++) {
        h.push();
      }
      final lower = (45 - drawingMaxUndo) ~/ k * k;
      expect(
        h.history.checkpointCount,
        multiples(lower, 44, k),
        reason: 'multiples of K from $lower, 45 is committed',
      );
      final undo44 = h.history.planUndo()!;
      expect(undo44.ops, hasLength(44 % k), reason: 'replay from 44 − 44 % K');
      var undos = 0;
      while (h.undo()) {
        undos++;
      }
      expect(undos, 30);
      expect(h.history.cursor, 15);
      expect(h.history.canUndo, isFalse);
      // Redo onto a checkpoint state uses it as is; others replay one op.
      while (h.history.canRedo) {
        final plan = h.history.planRedo()!;
        if (plan.target % k == 0) {
          expect(plan.ops, isEmpty);
          h.redo();
          expect(identical(h.history.committed, plan.base), isTrue);
        } else {
          expect(plan.ops, hasLength(1));
          h.redo();
        }
      }
      expect(h.history.cursor, 45);
    });

    test('K = $k: a push after undo drops redo ops and later checkpoints', () {
      final h = Harness(checkpointEvery: k);
      for (var i = 0; i < 40; i++) {
        h.push();
      }
      for (var i = 0; i < 12; i++) {
        h.undo();
      }
      expect(h.history.cursor, 28);
      h.push();
      expect(h.history.top, 29);
      expect(h.history.canRedo, isFalse);
      // Checkpoints above 28 were dropped and disposed; the ones trimmed at
      // top 40 stay gone.
      final lower = (40 - drawingMaxUndo) ~/ k * k;
      expect(h.history.checkpointCount, multiples(lower, 28, k));
    });
  }

  test('an undo floor raised by trimming is kept after a shorter branch', () {
    final h = Harness();
    for (var i = 0; i < 60; i++) {
      h.push();
    }
    var undos = 0;
    while (h.undo()) {
      undos++;
    }
    expect(undos, 30);
    expect(h.history.cursor, 30);
    h.push();
    // States below 30 are gone for good.
    expect(h.undo(), isTrue);
    expect(h.history.cursor, 30);
    expect(h.undo(), isFalse);
  });

  test('a stale plan is rejected', () {
    final h = Harness();
    h.push();
    h.push();
    final plan = h.history.planUndo()!;
    h.push();
    expect(() => h.history.apply(plan, 99), throwsStateError);
  });

  test('replace swaps a flattened image in everywhere it is held', () {
    const k = defaultCheckpointEvery;
    final h = DrawingHistory<int, int>(initial: 0);
    for (var i = 1; i <= k; i++) {
      h.push(i, 100 + i);
    }
    expect(h.committed, 100 + k);
    expect(h.replace(100 + k, 200 + k), [100 + k]);
    expect(h.committed, 200 + k);
    expect(h.images, containsAll([0, 200 + k]));
    expect(h.images, isNot(contains(100 + k)));
    // After more ops the old checkpoint is replaced alone.
    h.push(k + 1, 101 + k);
    expect(h.replace(200 + k, 300 + k), [200 + k]);
    expect(h.committed, 101 + k);
    expect(h.planUndo()!.base, 300 + k);
    expect(h.replace(999, 1), isEmpty);
  });

  for (final k in {...ks, 10, 7}) {
    test('10 000 seeded random steps keep every bound (K = $k)', () {
      for (final seed in [1, 2, 3]) {
        final random = Random(seed);
        final h = Harness(checkpointEvery: k);
        for (var step = 0; step < 10000; step++) {
          final r = random.nextDouble();
          if (r < 0.5) {
            h.push();
          } else if (r < 0.8) {
            h.undo();
          } else {
            h.redo();
          }
        }
        expect(h.maxReplay, k - 1, reason: 'the bound is reached');
        expect(h.disposed, isNotEmpty);
      }
    });
  }

  test('long undo bursts never exceed 30 steps', () {
    final random = Random(42);
    final h = Harness();
    for (var round = 0; round < 200; round++) {
      final pushes = random.nextInt(50);
      for (var i = 0; i < pushes; i++) {
        h.push();
      }
      var undos = 0;
      final top = h.history.top;
      final start = h.history.cursor;
      while (h.undo()) {
        undos++;
      }
      expect(undos, lessThanOrEqualTo(drawingMaxUndo));
      if (start == top && top >= drawingMaxUndo && pushes >= drawingMaxUndo) {
        expect(undos, drawingMaxUndo);
      }
      final redos = random.nextInt(undos + 1);
      for (var i = 0; i < redos; i++) {
        expect(h.redo(), isTrue);
      }
    }
  });
}
