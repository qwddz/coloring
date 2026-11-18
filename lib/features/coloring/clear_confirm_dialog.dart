import 'package:flutter/material.dart';

import '../../app/widgets/book_button.dart';
import '../../app/widgets/book_dialog.dart';
import '../../l10n/app_localizations.dart';

/// Asks to remove all colors; true only when confirmed.
Future<bool> showClearConfirmDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showBookDialog<bool>(
    context: context,
    builder: (context) => BookDialog(
      title: l10n.coloringClearTitle,
      content: Text(l10n.coloringClearMessage),
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
