/// Undo steps in the drawing (coloring keeps 50).
const int drawingMaxUndo = 30;

/// Default checkpoint interval K (spec §6.4); the render engine passes the
/// value the device spike settled on.
const int defaultCheckpointEvery = 10;

/// How to rebuild state [target]: start from [base] and replay [ops] in
/// order. Empty [ops] means [base] itself is the result (a checkpoint, used
/// as is, no copy).
class HistoryPlan<Op, Img> {
  HistoryPlan._(this.target, this.base, List<Op> ops, this._version)
    : ops = List.unmodifiable(ops);

  final int target;
  final Img base;
  final List<Op> ops;
  final int _version;
}

/// Undo/redo over raster images with a bounded replay (spec §6.4). Pure and
/// generic: [Op] is a drawing operation, [Img] an image handle; the history
/// never creates or draws images, it only says which ones to replay from
/// and which ones the caller must dispose.
///
/// State `i` is the canvas after the first `i` ops of the session (state 0
/// is the loaded image); [cursor] is the current state and [top] the newest
/// state reachable by redo. Checkpoints are kept at states `i % K == 0`
/// with `floor((top − 30) / K) · K ≤ i ≤ top`; when the current state is a
/// multiple of K, [committed] is that checkpoint (the same image). So any
/// undo replays at most K − 1 ops onto a checkpoint, a redo replays one op
/// on [committed], and at most `ceil(30 / K) + 1` checkpoints live besides
/// [committed] (4 for K = 10).
///
/// Every mutating call returns the images that are no longer referenced;
/// the caller disposes them and never uses them again.
class DrawingHistory<Op, Img> {
  DrawingHistory({
    required Img initial,
    this.checkpointEvery = defaultCheckpointEvery,
  }) : assert(checkpointEvery > 0),
       _committed = initial {
    _checkpoints[0] = initial;
  }

  /// K, the distance between checkpoints.
  final int checkpointEvery;

  Img _committed;
  int _cursor = 0;
  int _top = 0;
  int _version = 0;

  /// State index → checkpoint image.
  final Map<int, Img> _checkpoints = {};

  /// Op index `i` (1-based) → the op that leads from state `i − 1` to `i`.
  final Map<int, Op> _ops = {};

  /// The image of the current state.
  Img get committed => _committed;

  int get cursor => _cursor;
  int get top => _top;

  /// Oldest state still reachable (its checkpoint is retained).
  int get _oldest => _checkpoints.keys.reduce((a, b) => a < b ? a : b);

  /// The lowest state undo can reach: at most [drawingMaxUndo] steps below
  /// [top], and never below the oldest retained checkpoint.
  int get _floor {
    final byLimit = _top - drawingMaxUndo;
    final oldest = _oldest;
    return byLimit > oldest ? byLimit : oldest;
  }

  bool get canUndo => _cursor > _floor;
  bool get canRedo => _cursor < _top;

  /// Every image the history holds (committed and checkpoints), each once.
  List<Img> get images {
    final out = <Img>[_committed];
    for (final img in _checkpoints.values) {
      if (!out.any((o) => identical(o, img))) out.add(img);
    }
    return out;
  }

  /// Number of checkpoint images other than [committed].
  int get checkpointCount =>
      _checkpoints.values.where((img) => !identical(img, _committed)).length;

  /// Records [op], whose result is [result] (drawn by the caller on top of
  /// [committed]). Drops the redo steps. Returns the images to dispose.
  List<Img> push(Op op, Img result) {
    final before = images;
    _ops.removeWhere((i, _) => i > _cursor);
    _checkpoints.removeWhere((i, _) => i > _cursor);
    _cursor++;
    _top = _cursor;
    _ops[_cursor] = op;
    _committed = result;
    if (_cursor % checkpointEvery == 0) _checkpoints[_cursor] = result;
    _trim();
    _version++;
    return _released(before);
  }

  /// The plan for one undo step, or null when [canUndo] is false.
  HistoryPlan<Op, Img>? planUndo() {
    if (!canUndo) return null;
    final target = _cursor - 1;
    // Every multiple of K from the oldest checkpoint to [top] has one, and
    // target ≥ oldest, so this checkpoint exists.
    final c = target - target % checkpointEvery;
    final base = _checkpoints[c] as Img;
    return HistoryPlan._(target, base, [
      for (var i = c + 1; i <= target; i++) _ops[i] as Op,
    ], _version);
  }

  /// The plan for one redo step, or null when [canRedo] is false.
  HistoryPlan<Op, Img>? planRedo() {
    if (!canRedo) return null;
    final target = _cursor + 1;
    final checkpoint = _checkpoints[target];
    if (checkpoint != null) {
      return HistoryPlan._(target, checkpoint, const [], _version);
    }
    return HistoryPlan._(target, _committed, [_ops[target] as Op], _version);
  }

  /// Moves to [plan]'s state with [result] as its image ([plan]'s base when
  /// it has no ops). Returns the images to dispose. Throws a [StateError]
  /// when the history changed after the plan was made.
  List<Img> apply(HistoryPlan<Op, Img> plan, Img result) {
    if (plan._version != _version) {
      throw StateError('History changed since the plan was made');
    }
    final before = images;
    _cursor = plan.target;
    _committed = result;
    _version++;
    return _released(before);
  }

  /// Puts [replacement] wherever [old] is held (committed and checkpoints),
  /// e.g. a fully rasterized copy of a lazily rasterized image. Returns
  /// `[old]` when it was held, else empty (and [replacement] is not kept).
  List<Img> replace(Img old, Img replacement) {
    var held = false;
    if (identical(_committed, old)) {
      _committed = replacement;
      held = true;
    }
    for (final i in _checkpoints.keys.toList()) {
      if (identical(_checkpoints[i], old)) {
        _checkpoints[i] = replacement;
        held = true;
      }
    }
    return held ? [old] : const [];
  }

  /// Keeps checkpoints in `[max(lower, oldest) .. top]` (lower from the
  /// rule above, but never dropping the last one at or below it) and the ops
  /// after the oldest kept checkpoint.
  void _trim() {
    final lower = _top < drawingMaxUndo
        ? 0
        : (_top - drawingMaxUndo) ~/ checkpointEvery * checkpointEvery;
    // The newest checkpoint at or below `lower` must stay, since states from
    // `lower` up replay from it. It is `lower` itself unless that one is gone.
    final keepFrom = _checkpoints.keys
        .where((i) => i <= lower)
        .fold<int>(_oldest, (a, b) => b > a ? b : a);
    _checkpoints.removeWhere((i, _) => i < keepFrom);
    _ops.removeWhere((i, _) => i <= keepFrom);
  }

  List<Img> _released(List<Img> before) {
    final after = images;
    return [
      for (final img in before)
        if (!after.any((a) => identical(a, img))) img,
    ];
  }
}
