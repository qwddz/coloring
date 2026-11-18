import 'package:flutter/material.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/book_button.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import 'clear_confirm_dialog.dart';
import 'model/coloring_mode.dart';

/// Undo, eraser, clear all, done (free mode only) and the mode switch.
/// Clear asks for confirmation here and calls [onClear] only when confirmed.
class ColoringToolbar extends StatelessWidget {
  const ColoringToolbar({
    required this.mode,
    required this.canUndo,
    required this.canFinish,
    required this.eraserSelected,
    required this.onUndo,
    required this.onEraser,
    required this.onClear,
    required this.onDone,
    required this.onModeChanged,
    super.key,
  });

  final ColoringMode mode;
  final bool canUndo;

  /// Enables Done (free mode).
  final bool canFinish;
  final bool eraserSelected;
  final VoidCallback onUndo;
  final VoidCallback onEraser;
  final VoidCallback onClear;
  final VoidCallback onDone;
  final ValueChanged<ColoringMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final eraserAvailable = mode != ColoringMode.magic;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Dimmed(
          enabled: canUndo,
          child: RoundIconButton(
            icon: Icons.undo,
            tooltip: l10n.coloringUndo,
            onPressed: onUndo,
          ),
        ),
        _Dimmed(
          enabled: eraserAvailable,
          child: _ToolButton(
            tooltip: l10n.coloringEraser,
            selected: eraserSelected && eraserAvailable,
            onPressed: onEraser,
            child: const Icon(Icons.cleaning_services, color: BookPalette.text),
          ),
        ),
        RoundIconButton(
          icon: Icons.delete_outline,
          tooltip: l10n.coloringClear,
          onPressed: () async {
            if (await showClearConfirmDialog(context)) onClear();
          },
        ),
        for (final m in ColoringMode.values)
          _ToolButton(
            tooltip: switch (m) {
              ColoringMode.free => l10n.coloringModeFree,
              ColoringMode.numbers => l10n.coloringModeNumbers,
              ColoringMode.magic => l10n.coloringModeMagic,
            },
            selected: m == mode,
            onPressed: () => onModeChanged(m),
            child: switch (m) {
              ColoringMode.free => const Icon(
                Icons.brush,
                color: BookPalette.text,
              ),
              ColoringMode.numbers => const Text(
                '1·2·3',
                maxLines: 1,
                style: TextStyle(
                  color: BookPalette.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              ColoringMode.magic => const Icon(
                Icons.auto_fix_high,
                color: BookPalette.text,
              ),
            },
          ),
        if (mode == ColoringMode.free)
          BookButton(
            label: l10n.coloringDone,
            onPressed: canFinish ? onDone : null,
          ),
      ],
    );
  }
}

/// Dims and blocks taps while [enabled] is false.
class _Dimmed extends StatelessWidget {
  const _Dimmed({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(opacity: enabled ? 1 : 0.4, child: child),
    );
  }
}

/// 48 dp toggle with a highlighted ring while [selected].
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    required this.selected,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? BookPalette.paperDark : BookPalette.card,
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
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
