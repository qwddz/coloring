import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/book_button.dart';
import '../../app/widgets/passe_partout.dart';

/// Card columns: 3 on phones, 4–5 on tablets (shortest side ≥ 600 dp).
int catalogColumns({required double width, required double shortestSide}) {
  if (shortestSide < 600) return 3;
  return width < 1400 ? 4 : 5;
}

/// Height reserved under the picture at normal text size: caption padding
/// plus one caption line.
const double _captionExtent = 48;

/// Adaptive grid of passe-partout cards (4:3 picture plus a caption line).
class CatalogGrid extends StatelessWidget {
  const CatalogGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    const padding = 16.0;
    const spacing = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = catalogColumns(
          width: constraints.maxWidth,
          shortestSide: MediaQuery.sizeOf(context).shortestSide,
        );
        final cellWidth =
            (constraints.maxWidth - 2 * padding - spacing * (columns - 1)) /
            columns;
        // 6 dp frame on each side of the 4:3 picture, then the caption.
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final cellHeight =
            (cellWidth - 12) * 3 / 4 +
            _captionExtent +
            (textScale > 1 ? 20 * (textScale - 1) : 0);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(padding, 8, padding, padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: cellHeight,
            mainAxisSpacing: 16,
            crossAxisSpacing: spacing,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

/// Picture in a passe-partout with a caption line and an optional badge.
class PictureCard extends StatelessWidget {
  const PictureCard({
    super.key,
    required this.image,
    required this.caption,
    required this.onTap,
    this.index = 0,
    this.badge,
    this.lockedLabel,
  });

  /// Small preview; the card stays plain without one.
  final ImageProvider? image;
  final Widget caption;
  final Widget? badge;
  final VoidCallback onTap;

  /// Position in the grid; even and odd cards tilt in opposite directions.
  final int index;

  /// Set for a picture of the full version: the preview is blurred under a
  /// lock with this tooltip.
  final String? lockedLabel;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    final lockedLabel = this.lockedLabel;
    return PassePartout(
      tiltDegrees: index.isEven ? -1.2 : 1.0,
      onTap: onTap,
      caption: caption,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: BookPalette.paper),
            if (image != null)
              ImageFiltered(
                enabled: lockedLabel != null,
                imageFilter: ImageFilter.blur(
                  sigmaX: 8,
                  sigmaY: 8,
                  tileMode: TileMode.decal,
                ),
                child: Image(
                  image: image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            if (lockedLabel != null)
              Center(
                child: Tooltip(
                  message: lockedLabel,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: BookPalette.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: BookPalette.primaryStep,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.lock_rounded,
                        size: 28,
                        color: BookPalette.card,
                      ),
                    ),
                  ),
                ),
              ),
            if (badge != null) Positioned(top: 6, right: 6, child: badge!),
          ],
        ),
      ),
    );
  }
}

/// Header row of catalog screens.
class CatalogHeader extends StatelessWidget {
  const CatalogHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          leading ?? const SizedBox(width: 8),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: BookPalette.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Centered message with one action, for load errors and missing content.
class CatalogMessage extends StatelessWidget {
  const CatalogMessage({
    super.key,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: BookPalette.text),
          ),
          const SizedBox(height: 16),
          BookButton(label: actionLabel, onPressed: onAction),
        ],
      ),
    );
  }
}
