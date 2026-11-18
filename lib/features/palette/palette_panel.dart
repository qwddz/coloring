import 'package:flutter/material.dart';

import '../../app/book_palette.dart';
import '../../l10n/app_localizations.dart';
import '../coloring/model/coloring_mode.dart';
import '../coloring/model/fill_state.dart';
import 'color_swatch.dart';
import 'domain/base_palette.dart';

/// The side panel of the coloring screen. Free: picture colors, recent and
/// all colors. Numbers: picture colors with numbers and progress. Magic: a
/// hint. Scrolls vertically when it does not fit.
class PalettePanel extends StatelessWidget {
  const PalettePanel({
    required this.mode,
    required this.picturePalette,
    required this.selectedColor,
    required this.onColorSelected,
    this.recent = const [],
    this.base = basePalette,
    this.progress = const [],
    this.eraserSelected = false,
    super.key,
  });

  final ColoringMode mode;

  /// Opaque ARGB colors of the picture; the number of color i is i + 1.
  final List<int> picturePalette;

  /// Most recent first; the section is hidden when empty.
  final List<int> recent;
  final List<int> base;

  /// ARGB of the selected brush color; no ring while [eraserSelected].
  final int? selectedColor;
  final bool eraserSelected;

  /// One entry per picture color, used in the numbers mode.
  final List<PaletteProgress> progress;
  final ValueChanged<int> onColorSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final children = switch (mode) {
      ColoringMode.magic => [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            l10n.paletteMagicHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
      ColoringMode.numbers => [
        _Section(
          title: l10n.palettePictureColors,
          colors: picturePalette,
          selectedColor: selectedColor,
          eraserSelected: eraserSelected,
          onSelected: onColorSelected,
          numbered: true,
          progress: progress,
        ),
      ],
      ColoringMode.free => [
        _Section(
          title: l10n.palettePictureColors,
          colors: picturePalette,
          selectedColor: selectedColor,
          eraserSelected: eraserSelected,
          onSelected: onColorSelected,
        ),
        if (recent.isNotEmpty)
          _Section(
            title: l10n.paletteRecent,
            colors: recent,
            selectedColor: selectedColor,
            eraserSelected: eraserSelected,
            onSelected: onColorSelected,
          ),
        _Section(
          title: l10n.paletteAllColors,
          colors: base,
          selectedColor: selectedColor,
          eraserSelected: eraserSelected,
          onSelected: onColorSelected,
        ),
      ],
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.colors,
    required this.selectedColor,
    required this.eraserSelected,
    required this.onSelected,
    this.numbered = false,
    this.progress = const [],
  });

  final String title;
  final List<int> colors;
  final int? selectedColor;
  final bool eraserSelected;
  final ValueChanged<int> onSelected;
  final bool numbered;
  final List<PaletteProgress> progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: BookPalette.textMuted),
            ),
          ),
          Wrap(
            children: [
              for (var i = 0; i < colors.length; i++)
                PaletteSwatch(
                  color: colors[i],
                  selected: !eraserSelected && colors[i] == selectedColor,
                  onTap: () => onSelected(colors[i]),
                  number: numbered ? i + 1 : null,
                  progress: numbered && i < progress.length
                      ? progress[i]
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
