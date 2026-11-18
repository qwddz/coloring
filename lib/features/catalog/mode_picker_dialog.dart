import 'package:flutter/material.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/book_button.dart';
import '../../app/widgets/book_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../coloring/model/coloring_mode.dart';

/// Asks how to color a new work; null when cancelled.
Future<ColoringMode?> showModePicker(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showBookDialog<ColoringMode>(
    context: context,
    builder: (context) => BookDialog(
      title: l10n.modePickerTitle,
      content: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, mode) in ColoringMode.values.indexed) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(
                child: _ModeOption(
                  icon: switch (mode) {
                    ColoringMode.free => Icons.brush_rounded,
                    ColoringMode.numbers => Icons.pin_rounded,
                    ColoringMode.magic => Icons.auto_fix_high_rounded,
                  },
                  name: switch (mode) {
                    ColoringMode.free => l10n.coloringModeFree,
                    ColoringMode.numbers => l10n.coloringModeNumbers,
                    ColoringMode.magic => l10n.coloringModeMagic,
                  },
                  description: switch (mode) {
                    ColoringMode.free => l10n.modeFreeDescription,
                    ColoringMode.numbers => l10n.modeNumbersDescription,
                    ColoringMode.magic => l10n.modeMagicDescription,
                  },
                  onTap: () => Navigator.of(context).pop(mode),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        BookButton(
          label: l10n.cancel,
          kind: BookButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.icon,
    required this.name,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: BookPalette.paperLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: BookPalette.outline, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32, color: BookPalette.primary),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: theme.textTheme.titleSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
