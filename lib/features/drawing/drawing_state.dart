import 'model/brush_size.dart';
import 'model/drawing_tool.dart';
import 'model/symmetry.dart';

/// How a tool or mirror selection resolved.
enum ToolSelection {
  /// The tool (or mirror mode) is now selected.
  selected,

  /// It needs the full version: the screen opens the paywall through the
  /// parental gate, then selects again.
  locked,

  /// A newer selection came in while this one waited for the access
  /// status; nothing changed and the screen does nothing.
  superseded,
}

/// What the drawing screen shows besides the pixels: a snapshot taken after
/// every controller command. Images are not here; the canvas listens to the
/// controller's `engine` and `liveStroke`.
class DrawingState {
  const DrawingState({
    required this.drawingId,
    required this.tool,
    required this.color,
    required this.size,
    required this.symmetry,
    required this.canUndo,
    required this.canRedo,
    required this.busy,
    required this.isEmpty,
    required this.revision,
  });

  /// The id the drawing is saved under.
  final String drawingId;

  final DrawingTool tool;

  /// ARGB, the selected color (the eraser and rainbow ignore it).
  final int color;
  final BrushSize size;
  final SymmetryMode symmetry;
  final bool canUndo;
  final bool canRedo;

  /// A flood fill is being computed.
  final bool busy;

  /// A new drawing nothing has been drawn on yet (and never saved).
  final bool isEmpty;

  /// Grows by one with every change of the pixels (op, undo, redo, clear).
  final int revision;

  DrawingState copyWith({
    DrawingTool? tool,
    int? color,
    BrushSize? size,
    SymmetryMode? symmetry,
    bool? canUndo,
    bool? canRedo,
    bool? busy,
    bool? isEmpty,
    int? revision,
  }) => DrawingState(
    drawingId: drawingId,
    tool: tool ?? this.tool,
    color: color ?? this.color,
    size: size ?? this.size,
    symmetry: symmetry ?? this.symmetry,
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
    busy: busy ?? this.busy,
    isEmpty: isEmpty ?? this.isEmpty,
    revision: revision ?? this.revision,
  );
}
