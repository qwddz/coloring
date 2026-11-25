import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/book_button.dart';
import '../../app/widgets/book_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../palette/color_swatch.dart';
import 'model/drawing_palette.dart';
import 'data/tool_access.dart';
import 'drawing_state.dart';
import 'model/brush_size.dart';
import 'model/drawing_tool.dart';
import 'model/symmetry.dart';

/// Panel button size and the gap between buttons.
const double _button = 48;
const double _gap = 4;

/// Width of the pinned tools column: two buttons and a gap.
const double drawingToolsColumnWidth = _button * 2 + _gap;

/// The drawing screen's side panel (spec §13): the tools pinned in two
/// columns on the left; on the right the actions (undo, redo, mirror,
/// size, clear, new sheet) pinned above the scrolling colors. Renders
/// [state] and forwards taps; clear asks for confirmation first.
class DrawingPanel extends ConsumerStatefulWidget {
  const DrawingPanel({
    required this.state,
    required this.recent,
    required this.onTool,
    required this.onColor,
    required this.onSize,
    required this.onUndo,
    required this.onRedo,
    required this.onMirror,
    required this.onClear,
    required this.onNewSheet,
    super.key,
  });

  final DrawingState state;

  /// Recently used colors, most recent first.
  final List<int> recent;
  final ValueChanged<DrawingTool> onTool;
  final ValueChanged<int> onColor;
  final ValueChanged<BrushSize> onSize;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onMirror;

  /// Called only once the clear dialog is confirmed.
  final VoidCallback onClear;
  final VoidCallback onNewSheet;

  @override
  ConsumerState<DrawingPanel> createState() => _DrawingPanelState();
}

class _DrawingPanelState extends ConsumerState<DrawingPanel> {
  final _toolKeys = {for (final tool in DrawingTool.values) tool: GlobalKey()};
  DrawingTool? _shownTool;
  double? _shownHeight;

  /// Scrolls the tools column so the selected tool is in view, after a new
  /// selection or a new height.
  void _keepSelectedVisible(double height) {
    final tool = widget.state.tool;
    if (tool == _shownTool && height == _shownHeight) return;
    _shownTool = tool;
    _shownHeight = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _toolKeys[tool]?.currentContext;
      if (context == null || !context.mounted) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: drawingToolsColumnWidth,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _keepSelectedVisible(constraints.maxHeight);
              return Semantics(
                container: true,
                label: l10n.drawingTools,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: _gap,
                    runSpacing: _gap,
                    children: [
                      for (final tool in DrawingTool.values)
                        _ToolButton(
                          key: _toolKeys[tool],
                          tool: tool,
                          selected: tool == state.tool,
                          onPressed: () => widget.onTool(tool),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [
                  _PanelButton(
                    tooltip: l10n.drawingUndo,
                    enabled: state.canUndo,
                    onPressed: widget.onUndo,
                    child: const Icon(Icons.undo_rounded),
                  ),
                  _PanelButton(
                    tooltip: l10n.drawingRedo,
                    enabled: state.canRedo,
                    onPressed: widget.onRedo,
                    child: const Icon(Icons.redo_rounded),
                  ),
                  _MirrorButton(
                    on: state.symmetry != SymmetryMode.off,
                    onPressed: widget.onMirror,
                  ),
                  _SizeButton(
                    size: state.size,
                    color: state.color,
                    onSelected: widget.onSize,
                  ),
                  _PanelButton(
                    tooltip: l10n.drawingClear,
                    onPressed: () async {
                      if (await _confirmClear(context)) widget.onClear();
                    },
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  _PanelButton(
                    tooltip: l10n.drawingNewSheet,
                    onPressed: widget.onNewSheet,
                    child: const Icon(Icons.note_add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Semantics(
                  container: true,
                  label: l10n.drawingColors,
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: _gap,
                      runSpacing: _gap,
                      children: [
                        for (final color in [
                          ...widget.recent.take(4),
                          ...drawingPalette,
                        ])
                          PaletteSwatch(
                            color: color,
                            selected:
                                state.tool != DrawingTool.eraser &&
                                color == state.color,
                            onTap: () => widget.onColor(color),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Asks before wiping the sheet; true only when confirmed.
Future<bool> _confirmClear(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showBookDialog<bool>(
    context: context,
    builder: (context) => BookDialog(
      title: l10n.drawingClearTitle,
      content: Text(l10n.drawingClearMessage),
      actions: [
        BookButton(
          label: l10n.coloringClearCancel,
          kind: BookButtonKind.text,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BookButton(
          label: l10n.coloringClearConfirm,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The name of [tool] in the current language.
String drawingToolName(AppLocalizations l10n, DrawingTool tool) =>
    switch (tool) {
      DrawingTool.pencil => l10n.drawingToolPencil,
      DrawingTool.felt => l10n.drawingToolFelt,
      DrawingTool.marker => l10n.drawingToolMarker,
      DrawingTool.eraser => l10n.drawingToolEraser,
      DrawingTool.rainbow => l10n.drawingToolRainbow,
      DrawingTool.pastel => l10n.drawingToolPastel,
      DrawingTool.watercolor => l10n.drawingToolWatercolor,
      DrawingTool.airbrush => l10n.drawingToolAirbrush,
      DrawingTool.neon => l10n.drawingToolNeon,
      DrawingTool.stampStar => l10n.drawingToolStars,
      DrawingTool.stampHeart => l10n.drawingToolHearts,
      DrawingTool.fill => l10n.drawingToolFill,
      DrawingTool.crayon => l10n.drawingToolCrayon,
      DrawingTool.chalk => l10n.drawingToolChalk,
      DrawingTool.dotted => l10n.drawingToolDotted,
      DrawingTool.glitter => l10n.drawingToolGlitter,
      DrawingTool.calligraphy => l10n.drawingToolCalligraphy,
    };

IconData _iconOf(DrawingTool tool) => switch (tool) {
  DrawingTool.pencil => Icons.edit_rounded,
  DrawingTool.felt => Icons.brush_rounded,
  DrawingTool.marker => Icons.border_color_rounded,
  DrawingTool.eraser => Icons.cleaning_services_rounded,
  DrawingTool.rainbow => Icons.looks_rounded,
  DrawingTool.pastel => Icons.gesture_rounded,
  DrawingTool.watercolor => Icons.water_drop_rounded,
  DrawingTool.airbrush => Icons.blur_on_rounded,
  DrawingTool.neon => Icons.flare_rounded,
  DrawingTool.stampStar => Icons.star_rounded,
  DrawingTool.stampHeart => Icons.favorite_rounded,
  DrawingTool.fill => Icons.format_color_fill_rounded,
  DrawingTool.crayon => Icons.create_rounded,
  DrawingTool.chalk => Icons.draw_rounded,
  DrawingTool.dotted => Icons.more_horiz_rounded,
  DrawingTool.glitter => Icons.auto_awesome_rounded,
  DrawingTool.calligraphy => Icons.history_edu_rounded,
};

class _ToolButton extends ConsumerWidget {
  const _ToolButton({
    required this.tool,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final DrawingTool tool;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locked = !ref.watch(canUseToolProvider(tool));
    final name = drawingToolName(l10n, tool);
    return _PanelButton(
      tooltip: locked ? l10n.drawingToolLocked(name) : name,
      selected: selected,
      locked: locked,
      onPressed: onPressed,
      child: Icon(_iconOf(tool)),
    );
  }
}

class _MirrorButton extends ConsumerWidget {
  const _MirrorButton({required this.on, required this.onPressed});

  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _PanelButton(
      tooltip: on ? l10n.drawingMirrorOn : l10n.drawingMirrorOff,
      selected: on,
      locked: !ref.watch(canUseSymmetryProvider),
      onPressed: onPressed,
      child: const Icon(Icons.flip_rounded),
    );
  }
}

/// Shows a dot of the current color at the current size; opens the four
/// sizes in a menu under it.
class _SizeButton extends StatelessWidget {
  const _SizeButton({
    required this.size,
    required this.color,
    required this.onSelected,
  });

  final BrushSize size;
  final int color;
  final ValueChanged<BrushSize> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(BookPalette.card),
        padding: WidgetStatePropertyAll(EdgeInsets.all(8)),
      ),
      menuChildren: [
        Builder(
          builder: (context) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in BrushSize.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
                  child: _PanelButton(
                    tooltip: _sizeName(l10n, s),
                    selected: s == size,
                    onPressed: () {
                      MenuController.maybeOf(context)?.close();
                      onSelected(s);
                    },
                    child: _SizeDot(size: s, color: color),
                  ),
                ),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) => _PanelButton(
        tooltip: l10n.drawingBrushSize,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: _SizeDot(size: size, color: color),
      ),
    );
  }
}

String _sizeName(AppLocalizations l10n, BrushSize size) => switch (size) {
  BrushSize.small => l10n.drawingSizeSmall,
  BrushSize.medium => l10n.drawingSizeMedium,
  BrushSize.large => l10n.drawingSizeLarge,
  BrushSize.huge => l10n.drawingSizeHuge,
};

class _SizeDot extends StatelessWidget {
  const _SizeDot({required this.size, required this.color});

  final BrushSize size;
  final int color;

  @override
  Widget build(BuildContext context) {
    final diameter = switch (size) {
      BrushSize.small => 8.0,
      BrushSize.medium => 14.0,
      BrushSize.large => 22.0,
      BrushSize.huge => 32.0,
    };
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: Color(color),
        shape: BoxShape.circle,
        border: Border.all(color: BookPalette.outline, width: 1.5),
      ),
    );
  }
}

/// 48 dp round button: highlighted ring while [selected], dimmed and
/// inert unless [enabled], a small lock in the corner while [locked]
/// (still tappable: a locked tool opens the paywall).
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.selected = false,
    this.enabled = true,
    this.locked = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;
  final bool selected;
  final bool enabled;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: tooltip,
        excludeSemantics: true,
        onTap: enabled ? onPressed : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: SizedBox(
              width: _button,
              height: _button,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected
                            ? BookPalette.paperDark
                            : BookPalette.card,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: BookPalette.primary, width: 3)
                            : null,
                        boxShadow: const [
                          BoxShadow(
                            color: BookPalette.secondaryStep,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: IconTheme.merge(
                          data: const IconThemeData(color: BookPalette.text),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                  if (locked)
                    const Positioned(top: 0, right: 0, child: _LockBadge()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockBadge extends StatelessWidget {
  const _LockBadge();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: BookPalette.primary,
        shape: BoxShape.circle,
      ),
      child: SizedBox(
        width: 16,
        height: 16,
        child: Icon(Icons.lock_rounded, size: 11, color: BookPalette.card),
      ),
    );
  }
}
