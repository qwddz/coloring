import 'package:flutter/material.dart';

import '../../app/book_palette.dart';
import '../../l10n/app_localizations.dart';
import 'domain/content_manifest.dart';

/// Small chip with the picture's level («Простая» / «Средняя»).
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level});

  final PictureLevel level;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = switch (level) {
      PictureLevel.simple => l10n.levelSimple,
      PictureLevel.medium => l10n.levelMedium,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BookPalette.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: BookPalette.textMuted),
        ),
      ),
    );
  }
}
