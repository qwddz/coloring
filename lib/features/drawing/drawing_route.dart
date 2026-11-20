import 'model/drawing_record.dart';

/// What the drawing screen opens (spec R2): the latest drawing (plain), a
/// saved drawing by [workId], or a new blank drawing with id [newId]. At
/// most one of the two is set.
class DrawingRequest {
  const DrawingRequest({this.workId, String? newId})
    : newId = workId == null ? newId : null;

  /// The request in a `/draw` URL: `?work=` wins over `?new=`. A `?work=`
  /// that is not a plain id opens a new drawing with an id from [now]; a
  /// `?new=` that is not a plain id is ignored (plain request).
  factory DrawingRequest.fromRoute(
    Map<String, String> query, {
    DateTime Function()? now,
  }) {
    final workId = query['work'];
    if (workId != null) {
      if (DrawingRecord.isPlainId(workId)) {
        return DrawingRequest(workId: workId);
      }
      return DrawingRequest(newId: newDrawingId((now ?? DateTime.now)()));
    }
    final newId = query['new'];
    if (newId != null && DrawingRecord.isPlainId(newId)) {
      return DrawingRequest(newId: newId);
    }
    return const DrawingRequest();
  }

  final String? workId;
  final String? newId;

  @override
  bool operator ==(Object other) =>
      other is DrawingRequest && other.workId == workId && other.newId == newId;

  @override
  int get hashCode => Object.hash(workId, newId);

  @override
  String toString() => 'DrawingRequest(${_route(workId, newId)})';
}

/// `/draw`, `/draw?work=<workId>`, or with [newSheet] `/draw?new=<id>` with
/// a fresh id from [now] (every call a distinct route). [workId] wins.
String drawRoute({
  String? workId,
  bool newSheet = false,
  DateTime Function()? now,
}) {
  if (workId != null) return _route(workId, null);
  if (newSheet) return _route(null, newDrawingId((now ?? DateTime.now)()));
  return _route(null, null);
}

String _route(String? workId, String? newId) {
  final query = <String, String>{
    if (workId != null) 'work': workId else 'new': ?newId,
  };
  return Uri(
    path: '/draw',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}
