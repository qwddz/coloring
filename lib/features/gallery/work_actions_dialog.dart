import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/book_button.dart';
import '../../app/widgets/book_dialog.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/mode_picker_dialog.dart';
import '../coloring/coloring_route.dart';
import '../coloring/model/work.dart';
import '../subscription/parental_gate.dart';
import 'data/my_works_controller.dart';
import 'data/works_provider.dart';
import 'work_preview_image.dart';

/// What the player picked in [WorkActionsDialog].
enum WorkAction { continueWork, newWork, saveToGallery, share }

/// Shows the actions of [summary] and carries out the one picked: continue
/// the work, start a new work of its picture (after the mode picker), save
/// it to the gallery, or share it behind the parental gate.
Future<void> openWorkActions(
  BuildContext context,
  WidgetRef ref,
  WorkSummary summary,
) async {
  final action = await showBookDialog<WorkAction>(
    context: context,
    builder: (context) => WorkActionsDialog(summary: summary),
  );
  if (action == null || !context.mounted) return;
  final work = summary.work;
  switch (action) {
    case WorkAction.continueWork:
      await context.push(coloringRoute(work.pictureId, workId: work.id));
    case WorkAction.newWork:
      final mode = await showModePicker(context);
      if (mode == null || !context.mounted) return;
      await context.push(coloringRoute(work.pictureId, newMode: mode));
    case WorkAction.saveToGallery:
      final message = await ref
          .read(myWorksControllerProvider.notifier)
          .saveToGallery(work);
      if (context.mounted) showWorkMessage(context, message);
    case WorkAction.share:
      await shareWorkThroughGate(context, ref, work);
  }
}

/// Asks the parental gate, then shares [work]: sharing leaves the app.
Future<void> shareWorkThroughGate(
  BuildContext context,
  WidgetRef ref,
  Work work,
) async {
  if (!await showParentalGate(context, ref) || !context.mounted) return;
  final message = await ref
      .read(myWorksControllerProvider.notifier)
      .share(work);
  if (context.mounted) showWorkMessage(context, message);
}

/// Shows [message] in a SnackBar; nothing for null.
void showWorkMessage(BuildContext context, WorkMessage? message) {
  if (message == null) return;
  final l10n = AppLocalizations.of(context);
  final text = switch (message) {
    WorkMessage.savedToGallery => l10n.workSavedToGallery,
    WorkMessage.saveDenied => l10n.workSaveDenied,
    WorkMessage.exportFailed => l10n.workExportFailed,
    WorkMessage.pictureUnavailable => l10n.workPictureUnavailable,
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// A large preview of the work next to its four actions. Every action is
/// disabled while the catalog loads (with a spinner), and with a note when
/// the picture is no longer in the catalog.
class WorkActionsDialog extends ConsumerWidget {
  const WorkActionsDialog({super.key, required this.summary});

  final WorkSummary summary;

  /// Width of the preview in the dialog, in logical pixels.
  static const double previewWidth = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final picture = ref.watch(workPictureProvider(summary.work.pictureId));
    final entry = picture.value;
    final available = entry != null;
    final loading = picture.isLoading && !picture.hasValue;
    final preview = summary.preview;
    void pick(WorkAction action) => Navigator.of(context).pop(action);
    Widget action(WorkAction value, String label, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: BookButton(
        label: label,
        icon: icon,
        kind: value == WorkAction.continueWork
            ? BookButtonKind.primary
            : BookButtonKind.secondary,
        onPressed: available ? () => pick(value) : null,
      ),
    );
    return Dialog(
      backgroundColor: BookPalette.card,
      surfaceTintColor: Colors.transparent,
      shadowColor: BookPalette.shadow,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                flex: 3,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: previewWidth),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: ColoredBox(
                        color: BookPalette.paper,
                        child: preview == null
                            ? null
                            : Image(
                                image: workPreviewImage(
                                  preview.file,
                                  logicalWidth: previewWidth,
                                  devicePixelRatio:
                                      MediaQuery.devicePixelRatioOf(context),
                                ),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Flexible(
                flex: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry?.title.resolve(language) ?? '',
                            style: theme.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        RoundIconButton(
                          tooltip: l10n.cancel,
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (!available)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          l10n.workPictureUnavailable,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: BookPalette.textMuted,
                          ),
                        ),
                      ),
                    action(
                      WorkAction.continueWork,
                      l10n.workContinue,
                      Icons.brush_rounded,
                    ),
                    action(
                      WorkAction.newWork,
                      l10n.workNewWork,
                      Icons.add_rounded,
                    ),
                    action(
                      WorkAction.saveToGallery,
                      l10n.workSaveToGallery,
                      Icons.download_rounded,
                    ),
                    action(
                      WorkAction.share,
                      l10n.workShare,
                      Icons.share_rounded,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
