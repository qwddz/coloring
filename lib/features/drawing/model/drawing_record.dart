/// One saved drawing, stored as JSON (v1) in the drawings folder next to its
/// raster PNG [raster] (`<id>.r<modifiedMillis>.png`, spec §12.1).
class DrawingRecord {
  DrawingRecord({
    required this.id,
    required this.created,
    required this.modified,
    required this.width,
    required this.height,
    required this.raster,
  });

  static const int version = 1;

  static final _plainId = RegExp(r'^[A-Za-z0-9_.-]+$');

  /// Drawing ids and raster names are file names: letters, digits, `_`, `.`
  /// and `-` only, and never `.` or `..`.
  static bool isPlainId(String id) =>
      _plainId.hasMatch(id) && id != '.' && id != '..';

  /// The raster file name of drawing [id] saved at [modified].
  static String rasterName(String id, DateTime modified) =>
      '$id.r${modified.toUtc().millisecondsSinceEpoch}.png';

  final String id;
  final DateTime created;
  final DateTime modified;

  /// Raster size in pixels.
  final int width;
  final int height;

  /// Raster file name in the drawings folder.
  final String raster;

  Map<String, Object?> toJson() => {
    'v': version,
    'id': id,
    'created': created.toUtc().toIso8601String(),
    'modified': modified.toUtc().toIso8601String(),
    'width': width,
    'height': height,
    'raster': raster,
  };

  /// Parses a v1 record; null for another version or malformed data, so the
  /// caller never overwrites a file it cannot read.
  static DrawingRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['v'] != version) return null;
    final id = json['id'];
    final created = _date(json['created']);
    final modified = _date(json['modified']);
    final width = json['width'];
    final height = json['height'];
    final raster = json['raster'];
    if (id is! String || !isPlainId(id)) return null;
    if (created == null || modified == null) return null;
    if (width is! int || width <= 0 || height is! int || height <= 0) {
      return null;
    }
    if (raster is! String || !isPlainId(raster)) return null;
    if (!raster.startsWith('$id.r') || !raster.endsWith('.png')) return null;
    return DrawingRecord(
      id: id,
      created: created,
      modified: modified,
      width: width,
      height: height,
      raster: raster,
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}

int _lastIdMillis = -1;
int _sameMillisCount = 0;

/// A new drawing id, `drawing-<millis>`. A second id in the same
/// millisecond (or with the clock behind the previous call) gets a counter
/// suffix, `drawing-<millis>-1`, `-2`…, so ids never repeat in one run.
String newDrawingId(DateTime now) {
  final millis = now.toUtc().millisecondsSinceEpoch;
  if (millis > _lastIdMillis) {
    _lastIdMillis = millis;
    _sameMillisCount = 0;
    return 'drawing-$millis';
  }
  _sameMillisCount++;
  return 'drawing-$_lastIdMillis-$_sameMillisCount';
}
