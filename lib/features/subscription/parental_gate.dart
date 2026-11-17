import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/widgets/book_button.dart';
import '../../app/widgets/book_dialog.dart';
import '../../l10n/app_localizations.dart';
import 'data/purchase_providers.dart';
import 'domain/parental_challenge.dart';

/// Asks a grown-up to solve a fresh challenge. True only for the right
/// answer. Ignored while a gate is already open; refused with a short
/// message during the cooldown after a wrong answer.
Future<bool> showParentalGate(BuildContext context, WidgetRef ref) async {
  final gate = ref.read(parentalGateProvider.notifier);
  if (ref.read(parentalGateProvider) == ParentalGateStatus.coolingDown) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).parentalGateCooldown),
        ),
      );
    return false;
  }
  if (!gate.open()) return false;
  final challenge = ref.read(parentalChallengeProvider)();
  // Null is a cancel, false a wrong answer.
  bool? passed;
  try {
    passed = await showBookDialog<bool>(
      context: context,
      builder: (context) => _ParentalGateDialog(challenge: challenge),
    );
  } finally {
    gate.close(wrongAnswer: passed == false);
  }
  return passed ?? false;
}

class _ParentalGateDialog extends StatefulWidget {
  const _ParentalGateDialog({required this.challenge});

  final ParentalChallenge challenge;

  @override
  State<_ParentalGateDialog> createState() => _ParentalGateDialogState();
}

class _ParentalGateDialogState extends State<_ParentalGateDialog> {
  final _answer = TextEditingController();

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop(widget.challenge.check(_answer.text));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BookDialog(
      title: l10n.parentalGateTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.parentalGateQuestion(widget.challenge.a, widget.challenge.b),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _answer,
            autofocus: true,
            // When the keyboard squeezes the dialog, scroll far enough to
            // keep the question above the field in view as well.
            scrollPadding: const EdgeInsets.fromLTRB(20, 72, 20, 20),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: InputDecoration(labelText: l10n.parentalGateAnswer),
            onSubmitted: (_) => _submit(),
          ),
        ],
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
