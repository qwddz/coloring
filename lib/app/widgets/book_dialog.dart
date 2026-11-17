import 'package:flutter/material.dart';

import '../book_palette.dart';

Future<T?> showBookDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: BookPalette.scrim.withValues(alpha: .4),
    builder: builder,
  );
}

/// Paper-card dialog: optional heading, content and a row of actions.
///
/// The actions stay pinned under scrolling content; when the dialog is very
/// short (a phone with the keyboard open) the padding shrinks and the actions
/// scroll together with the content, so nothing overflows.
class BookDialog extends StatelessWidget {
  const BookDialog({
    required this.content,
    this.title,
    this.actions = const [],
    super.key,
  });

  /// Below this height the actions scroll with the content.
  static const double compactHeight = 220;

  final String? title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Dialog(
      backgroundColor: BookPalette.card,
      surfaceTintColor: Colors.transparent,
      shadowColor: BookPalette.shadow,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: keyboardOpen ? 8 : 16,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < compactHeight;
            final body = <Widget>[
              if (title != null) ...[
                Text(title!, style: theme.textTheme.titleLarge),
                SizedBox(height: compact ? 8 : 12),
              ],
              DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium,
                child: content,
              ),
            ];
            final actionRow = Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            );
            if (compact) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...body,
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      actionRow,
                    ],
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: body,
                      ),
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    actionRow,
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
