import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/book_button.dart';
import '../../app/widgets/book_dialog.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../drawing/data/drawings_provider.dart';
import '../drawing/drawing_route.dart';
import '../drawing/model/drawing_record.dart';
import '../subscription/parental_gate.dart';
import 'data/my_works_controller.dart';
import 'work_actions_dialog.dart';
import 'work_preview_image.dart';

/// What the player picked in [DrawingActionsDialog].
enum DrawingAction { continueDrawing, newDrawing, saveToGallery, share }

/// `drawingWorkTitle` with the date: the caption of [drawing] in «Мои работы».
String drawingTitle(BuildContext context, DrawingRecord drawing) {
  final l10n = AppLocalizations.of(context);
  final date = DateFormat.yMMMd(l10n.localeName)
      .format(drawing.modified.toLocal());
  return l10n.drawingWorkTitle(date);
}

/// Shows the actions of [summary] and carries out the one picked: continue
/// the drawing, start a new one, save it to the gallery, or share it behind
/// the parental gate.
Future<void> openDrawingActions(
  BuildContext context,
  WidgetRef ref,
  DrawingSummary summary,
) async {
  final action = await showBookDialog<DrawingAction>(
    context: context,
    builder: (context) => DrawingActionsDialog(summary: summary),
  );
  if (action == null || !context.mounted) return;
  final drawing = summary.record;
  switch (action) {
    case DrawingAction.continueDrawing:
      await context.push(drawRoute(workId: drawing.id));
    case DrawingAction.newDrawing:
      await context.push(drawRoute(newSheet: true));
    case DrawingAction.saveToGallery:
      final message = await ref
          .read(myWorksControllerProvider.notifier)
          .saveDrawingToGallery(drawing);
      if (context.mounted) showWorkMessage(context, message);
    case DrawingAction.share:
      await shareDrawingThroughGate(context, ref, drawing);
  }
}

/// Asks the parental gate, then shares [drawing]: sharing leaves the app.
Future<void> shareDrawingThroughGate(
  BuildContext context,
  WidgetRef ref,
  DrawingRecord drawing,
) async {
  if (!await showParentalGate(context, ref) || !context.mounted) return;
  final message = await ref
      .read(myWorksControllerProvider.notifier)
      .shareDrawing(drawing);
  if (context.mounted) showWorkMessage(context, message);
}

/// A large preview of the drawing next to its four actions.
class DrawingActionsDialog extends StatelessWidget {
  const DrawingActionsDialog({super.key, required this.summary});

  final DrawingSummary summary;

  /// Width of the preview in the dialog, in logical pixels.
  static const double previewWidth = WorkActionsDialog.previewWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preview = summary.preview;
    void pick(DrawingAction action) => Navigator.of(context).pop(action);
    Widget action(DrawingAction value, String label, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: BookButton(
        label: label,
        icon: icon,
        kind: value == DrawingAction.continueDrawing
            ? BookButtonKind.primary
            : BookButtonKind.secondary,
        onPressed: () => pick(value),
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
                            drawingTitle(context, summary.record),
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
                    action(
                      DrawingAction.continueDrawing,
                      l10n.workContinue,
                      Icons.brush_rounded,
                    ),
                    action(
                      DrawingAction.newDrawing,
                      l10n.workNewDrawing,
                      Icons.add_rounded,
                    ),
                    action(
                      DrawingAction.saveToGallery,
                      l10n.workSaveToGallery,
                      Icons.download_rounded,
                    ),
                    action(
                      DrawingAction.share,
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
