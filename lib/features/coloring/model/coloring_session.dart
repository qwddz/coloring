import 'dart:math' as math;

import 'coloring_mode.dart';
import 'fill_state.dart';
import 'mode_rules.dart' as rules;
import 'picture_meta.dart';
import 'region_map.dart';
import 'undo_history.dart';

/// How a command ended.
enum FillOutcome {
  /// At least one region changed.
  changed,

  /// A region was hit but nothing changed (same color, empty stack, ...).
  unchanged,

  /// Numbers mode: wrong number; nothing changed.
  rejected,

  /// No region under the point (line or outside the image).
  miss,
}

/// The result of one session command.
class FillResult {
  const FillResult({
    required this.outcome,
    this.changes = const [],
    this.regionId = 0,
    this.justCompleted = false,
  });

  final FillOutcome outcome;

  /// The regions that changed, in the order they were applied.
  final List<RegionChange> changes;

  /// The region hit by a tap (0 for other commands or a miss).
  final int regionId;

  /// True once, on the command that made the picture complete.
  final bool justCompleted;

  bool get changed => changes.isNotEmpty;
}

/// A region and its correct color, for the free-mode long-press hint.
class RegionHint {
  const RegionHint(this.regionId, this.color);
  final int regionId;
  final int color;
}

/// The coloring aggregate: fill state, undo, mode, tool and selection.
/// Pure Dart; every fill goes through here so undo stays consistent.
class ColoringSession {
  ColoringSession({
    required this.meta,
    required this.map,
    FillState? fill,
    ColoringMode mode = ColoringMode.free,
    this._completed = false,
  }) : fill = fill ?? FillState(meta.regionCount),
       _mode = mode,
       _selectedColor = meta.palette[0],
       _selectedPaletteIndex = 0 {
    if (this.fill.regionCount != meta.regionCount) {
      throw ArgumentError(
        'fill has ${this.fill.regionCount} regions, '
        'picture has ${meta.regionCount}',
      );
    }
    // Initial selection (spec §2.6): free starts on palette[0], numbers on
    // the first incomplete palette index.
    if (mode == ColoringMode.numbers) {
      selectPaletteIndex(rules.firstIncompletePaletteIndex(this.fill, meta));
    }
  }

  /// Segments between stroke points are sampled at least this often (image
  /// px), so a fast swipe does not skip thin regions.
  static const double strokeStep = 1.0;

  final PictureMeta meta;
  final RegionMap map;
  final FillState fill;
  final UndoHistory _history = UndoHistory();

  ColoringMode _mode;
  ColoringTool _tool = ColoringTool.brush;
  int _selectedColor;
  int? _selectedPaletteIndex;
  bool _completed;

  List<RegionChange>? _stroke;
  final Set<int> _strokeTouched = {};
  double? _lastX;
  double? _lastY;

  ColoringMode get mode => _mode;
  ColoringTool get tool => _tool;

  /// ARGB color used by the brush in free mode.
  int get selectedColor => _selectedColor;

  /// Always set in numbers mode; elsewhere the palette index of
  /// [selectedColor], or null for a color outside the picture palette.
  int? get selectedPaletteIndex => _selectedPaletteIndex;

  /// Set once the picture is completed; later edits keep it.
  bool get completed => _completed;

  bool get canUndo => _history.canUndo;

  /// "Done": free mode, enough filled, and not completed yet.
  bool get canFinish => !_completed && rules.canFinish(_mode, fill);
  bool get isComplete => rules.isComplete(_mode, fill, meta);
  bool get isStroking => _stroke != null;
  double get filledFraction => fill.filledFraction;
  List<PaletteProgress> get paletteProgress => fill.paletteProgress(meta);

  /// Whether region [id] shows its number in numbers mode.
  bool showsNumberOf(int id) => rules.showsNumber(fill, meta, id);

  /// A tap at image point ([x], [y]).
  FillResult tap(double x, double y, {required double tolerance}) {
    final strokeCompleted = _commitStroke();
    final id = map.lookup(x, y, tolerance: tolerance);
    if (id == 0) {
      return FillResult(
        outcome: FillOutcome.miss,
        justCompleted: strokeCompleted,
      );
    }
    final rule = rules.tapRule(
      mode: _mode,
      tool: _tool,
      meta: meta,
      regionId: id,
      selectedColor: _selectedColor,
      selectedPaletteIndex: _selectedPaletteIndex,
    );
    switch (rule) {
      case rules.RejectRule():
        return FillResult(
          outcome: FillOutcome.rejected,
          regionId: id,
          justCompleted: strokeCompleted,
        );
      case rules.PaintRule(:final color):
        final change = _set(id, color);
        if (change == null) {
          return FillResult(
            outcome: FillOutcome.unchanged,
            regionId: id,
            justCompleted: strokeCompleted,
          );
        }
        _history.push([change]);
        return FillResult(
          outcome: FillOutcome.changed,
          changes: [change],
          regionId: id,
          justCompleted: _checkCompletion() || strokeCompleted,
        );
    }
  }

  /// Starts a magic-brush stroke (any active stroke is committed first).
  void beginStroke() {
    _commitStroke();
    if (_mode != ColoringMode.magic) return;
    _stroke = [];
    _strokeTouched.clear();
    _lastX = null;
    _lastY = null;
  }

  /// Extends the stroke to ([x], [y]); fills each region touched for the
  /// first time in this stroke. Returns this call's changes. Outside magic
  /// mode, or without [beginStroke], nothing happens.
  FillResult strokeTo(double x, double y, {required double tolerance}) {
    final stroke = _stroke;
    if (stroke == null) return const FillResult(outcome: FillOutcome.miss);
    final changes = <RegionChange>[];
    final lx = _lastX;
    final ly = _lastY;
    if (lx == null || ly == null) {
      _strokePoint(x, y, tolerance, changes);
    } else {
      final dist = math.sqrt((x - lx) * (x - lx) + (y - ly) * (y - ly));
      final steps = math.max(1, (dist / strokeStep).ceil());
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        _strokePoint(lx + (x - lx) * t, ly + (y - ly) * t, tolerance, changes);
      }
    }
    _lastX = x;
    _lastY = y;
    stroke.addAll(changes);
    return FillResult(
      outcome: changes.isEmpty ? FillOutcome.unchanged : FillOutcome.changed,
      changes: changes,
    );
  }

  /// Ends the stroke: all its changes become one undo step, and completion
  /// is checked. [FillResult.changes] lists the whole stroke.
  FillResult endStroke() {
    final stroke = _stroke;
    if (stroke == null) return const FillResult(outcome: FillOutcome.miss);
    final completed = _commitStroke();
    if (stroke.isEmpty) return const FillResult(outcome: FillOutcome.unchanged);
    return FillResult(
      outcome: FillOutcome.changed,
      changes: stroke,
      justCompleted: completed,
    );
  }

  /// Undoes the latest step.
  FillResult undo() {
    final strokeCompleted = _commitStroke();
    final changes = _history.undo();
    if (changes == null) {
      return FillResult(
        outcome: FillOutcome.unchanged,
        justCompleted: strokeCompleted,
      );
    }
    for (final c in changes) {
      fill.setColor(c.id, c.after);
    }
    return FillResult(
      outcome: FillOutcome.changed,
      changes: changes,
      justCompleted: _checkCompletion() || strokeCompleted,
    );
  }

  /// Empties every region as one undoable step.
  FillResult clearAll() {
    _commitStroke();
    final changes = <RegionChange>[];
    for (var id = 1; id <= meta.regionCount; id++) {
      final change = _set(id, 0);
      if (change != null) changes.add(change);
    }
    if (changes.isEmpty) {
      return const FillResult(outcome: FillOutcome.unchanged);
    }
    _history.push(changes);
    return FillResult(outcome: FillOutcome.changed, changes: changes);
  }

  /// The "Done" button (free mode, at least 80 % filled).
  FillResult finish() {
    _commitStroke();
    if (!canFinish || _completed) {
      return const FillResult(outcome: FillOutcome.unchanged);
    }
    _completed = true;
    return const FillResult(
      outcome: FillOutcome.unchanged,
      justCompleted: true,
    );
  }

  /// Switches mode, keeping colors, undo history and the selection where it
  /// still makes sense. The switch itself never completes the picture; only
  /// committing an open stroke can, and then this returns true.
  bool setMode(ColoringMode mode) {
    final strokeCompleted = _commitStroke();
    if (mode == _mode) return strokeCompleted;
    _mode = mode;
    if (mode == ColoringMode.magic) _tool = ColoringTool.brush;
    if (mode == ColoringMode.numbers) {
      final index = meta.palette.indexOf(_selectedColor);
      _selectedPaletteIndex = index >= 0
          ? index
          : rules.firstIncompletePaletteIndex(fill, meta);
      _selectedColor = meta.palette[_selectedPaletteIndex!];
    }
    return strokeCompleted;
  }

  /// Selects a brush color (ARGB, opaque) and the brush tool.
  void selectColor(int color) {
    if (color < 0xFF000000 || color > 0xFFFFFFFF) {
      throw ArgumentError.value(color, 'color', 'must be opaque ARGB');
    }
    final index = meta.palette.indexOf(color);
    if (_mode == ColoringMode.numbers && index < 0) {
      throw ArgumentError.value(color, 'color', 'not a picture color');
    }
    _tool = ColoringTool.brush;
    _selectedColor = color;
    _selectedPaletteIndex = index >= 0 ? index : null;
  }

  /// Selects picture color [index] and the brush tool.
  void selectPaletteIndex(int index) {
    RangeError.checkValidIndex(index, meta.palette, 'index');
    _tool = ColoringTool.brush;
    _selectedPaletteIndex = index;
    _selectedColor = meta.palette[index];
  }

  /// Selects the eraser (ignored in magic mode).
  void selectEraser() {
    if (_mode == ColoringMode.magic) return;
    _tool = ColoringTool.eraser;
  }

  /// Free-mode long press: the region under the point and its correct
  /// color, without filling or selecting it. Null elsewhere or on a miss.
  RegionHint? hintColorAt(double x, double y, {required double tolerance}) {
    if (_mode != ColoringMode.free) return null;
    final id = map.lookup(x, y, tolerance: tolerance);
    if (id == 0) return null;
    return RegionHint(id, meta.correctColorOf(id));
  }

  void _strokePoint(
    double x,
    double y,
    double tolerance,
    List<RegionChange> out,
  ) {
    final id = map.lookup(x, y, tolerance: tolerance);
    if (id == 0 || !_strokeTouched.add(id)) return;
    final change = _set(id, rules.strokeColor(meta, id));
    if (change != null) out.add(change);
  }

  /// Commits an open stroke as one undo step and checks completion for it.
  /// Returns true when that commit completed the picture.
  bool _commitStroke() {
    final stroke = _stroke;
    if (stroke == null) return false;
    _history.push(stroke);
    _stroke = null;
    _strokeTouched.clear();
    _lastX = null;
    _lastY = null;
    return stroke.isNotEmpty && _checkCompletion();
  }

  RegionChange? _set(int id, int color) {
    final before = fill.colorOf(id);
    if (before == color) return null;
    fill.setColor(id, color);
    return RegionChange(id, before, color);
  }

  bool _checkCompletion() {
    if (_completed || !isComplete) return false;
    _completed = true;
    return true;
  }
}
