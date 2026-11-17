import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/widgets/book_button.dart';
import '../../app/widgets/book_dialog.dart';
import '../../l10n/app_localizations.dart';
import 'data/review_access.dart';

/// Asks for the reviewer access code and redeems it; a wrong code is
/// reported with a short message. The paywall leaves by itself once the
/// full version is unlocked.
Future<void> showReviewCodeDialog(BuildContext context, WidgetRef ref) async {
  final code = await showBookDialog<String>(
    context: context,
    builder: (context) => const _ReviewCodeDialog(),
  );
  if (code == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final invalid = AppLocalizations.of(context).accessCodeInvalid;
  if (await ref.read(reviewAccessProvider.notifier).redeem(code)) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(invalid)));
}

class _ReviewCodeDialog extends StatefulWidget {
  const _ReviewCodeDialog();

  @override
  State<_ReviewCodeDialog> createState() => _ReviewCodeDialogState();
}

class _ReviewCodeDialogState extends State<_ReviewCodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_code.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BookDialog(
      title: l10n.accessCodeTitle,
      content: TextField(
        controller: _code,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(labelText: l10n.accessCodeField),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        BookButton(
          kind: BookButtonKind.text,
          label: l10n.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        BookButton(label: l10n.ok, onPressed: _submit),
      ],
    );
  }
}
