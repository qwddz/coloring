import 'model/coloring_mode.dart';
import 'model/work.dart';

/// What the coloring screen opens: a picture's latest work (plain), a saved
/// work by [workId], or a new work in [newMode]. At most one of [workId] and
/// [newMode] is set.
class ColoringRequest {
  const ColoringRequest(this.pictureId, {this.workId, ColoringMode? newMode})
    : newMode = workId == null ? newMode : null;

  /// The request in a `/coloring/<pictureId>` URL: `?work=` wins over
  /// `?mode=`, and an unknown mode is ignored. A `?work=` that is not a
  /// plain file name ([Work.isPlainId]) is ignored as if absent.
  factory ColoringRequest.fromRoute(
    String pictureId,
    Map<String, String> query,
  ) {
    final workId = query['work'];
    if (workId != null && Work.isPlainId(workId)) {
      return ColoringRequest(pictureId, workId: workId);
    }
    return ColoringRequest(
      pictureId,
      newMode: ColoringMode.fromName(query['mode']),
    );
  }

  final String pictureId;
  final String? workId;
  final ColoringMode? newMode;

  @override
  bool operator ==(Object other) =>
      other is ColoringRequest &&
      other.pictureId == pictureId &&
      other.workId == workId &&
      other.newMode == newMode;

  @override
  int get hashCode => Object.hash(pictureId, workId, newMode);

  @override
  String toString() =>
      'ColoringRequest(${coloringRoute(pictureId, workId: workId, newMode: newMode)})';
}

/// `/coloring/<pictureId>`, with `?work=<workId>` or `?mode=<mode>`.
/// [workId] wins when both are given.
String coloringRoute(
  String pictureId, {
  String? workId,
  ColoringMode? newMode,
}) {
  final query = <String, String>{
    if (workId != null)
      'work': workId
    else if (newMode != null)
      'mode': newMode.name,
  };
  return Uri(
    path: '/coloring/$pictureId',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}
