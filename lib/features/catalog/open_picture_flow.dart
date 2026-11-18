import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../coloring/coloring_route.dart';
import '../progress/data/picture_opener.dart';
import '../progress/domain/open_picture.dart';
import 'mode_picker_dialog.dart';

/// What opening [pictureId] shows: the latest unfinished work, else a new
/// work in the mode the child picks. Null when the picker is cancelled (or
/// the context is gone). The decision is read fresh on every call; when it
/// cannot be read, the mode picker is shown.
Future<String?> openPictureFlow(
  BuildContext context,
  WidgetRef ref,
  String pictureId,
) async {
  OpenPicture decision;
  try {
    decision = await ref.read(pictureOpenerProvider).decide(pictureId);
  } on Object catch (e) {
    debugPrint('Reading the works of $pictureId failed: $e');
    decision = const PickMode();
  }
  switch (decision) {
    case ContinueWork(:final workId):
      return coloringRoute(pictureId, workId: workId);
    case PickMode():
      if (!context.mounted) return null;
      final mode = await showModePicker(context);
      return mode == null ? null : coloringRoute(pictureId, newMode: mode);
  }
}
