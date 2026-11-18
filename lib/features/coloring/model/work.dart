import 'dart:typed_data';

import 'coloring_mode.dart';
import 'coloring_session.dart';
import 'fill_state.dart';

/// One coloring work of a picture, saved as JSON (v1) in the works folder.
/// [completed] marks this work only; the star of a picture lives in
/// `progress.json` and survives new works (decision D2). Each work is its
/// own file `<pictureId>-<millis>.json` (decision D3).
class Work {
  Work({
    required this.id,
    required this.pictureId,
    required this.mode,
    required this.colors,
    required this.modified,
    this.completed = false,
    this.completedAt,
  });

  /// A new empty work. [now] is injected so tests control ids and times.
  factory Work.create({
    required String pictureId,
    required int regionCount,
    required DateTime Function() now,
    ColoringMode mode = ColoringMode.free,
  }) {
    final t = now().toUtc();
    return Work(
      id: '$pictureId-${t.millisecondsSinceEpoch}',
      pictureId: pictureId,
      mode: mode,
      colors: Uint32List(regionCount + 1),
      modified: t,
    );
  }

  static const int version = 1;

  static final _plainId = RegExp(r'^[A-Za-z0-9_.-]+$');

  /// Work ids are file names: letters, digits, `_`, `.` and `-` only, and
  /// never `.` or `..`.
  static bool isPlainId(String id) =>
      _plainId.hasMatch(id) && id != '.' && id != '..';

  final String id;
  final String pictureId;
  final ColoringMode mode;

  /// Length N + 1, index 0 unused, ARGB (0 = unfilled).
  final Uint32List colors;
  final DateTime modified;
  final bool completed;
  final DateTime? completedAt;

  /// This work with the session's colors, mode and completion, stamped with
  /// [now]. [completedAt] is set the first time the work becomes completed.
  Work withSession(
    ColoringSession session, {
    required DateTime Function() now,
  }) {
    final t = now().toUtc();
    final done = completed || session.completed;
    return Work(
      id: id,
      pictureId: pictureId,
      mode: session.mode,
      colors: Uint32List.fromList(session.fill.colors),
      modified: t,
      completed: done,
      completedAt: completedAt ?? (done ? t : null),
    );
  }

  /// This work for a picture with [regionCount] regions. When the saved
  /// colors don't fit (the picture changed on the CDN), the colors are reset
  /// and the work is no longer completed; the mode is kept.
  Work fitTo(int regionCount) {
    if (colors.length == regionCount + 1) return this;
    return Work(
      id: id,
      pictureId: pictureId,
      mode: mode,
      colors: Uint32List(regionCount + 1),
      modified: modified,
    );
  }

  /// The fill state stored in this work.
  FillState toFillState(int regionCount) =>
      FillState.fromList(colors, regionCount);

  Map<String, Object?> toJson() => {
    'v': version,
    'id': id,
    'pictureId': pictureId,
    'mode': mode.name,
    'colors': List<int>.of(colors),
    'modified': modified.toUtc().toIso8601String(),
    'completed': completed,
    'completedAt': completedAt?.toUtc().toIso8601String(),
  };

  /// Parses a v1 work; null for another version or malformed data, so the
  /// caller starts fresh and never overwrites a file it cannot read.
  static Work? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['v'] != version) return null;
    final id = json['id'];
    final pictureId = json['pictureId'];
    final mode = ColoringMode.fromName(json['mode']);
    final rawColors = json['colors'];
    final modified = _date(json['modified']);
    final completed = json['completed'];
    final rawCompletedAt = json['completedAt'];
    final completedAt = _date(rawCompletedAt);
    if (id is! String || id.isEmpty) return null;
    if (pictureId is! String || pictureId.isEmpty) return null;
    if (mode == null || modified == null || completed is! bool) return null;
    if (rawCompletedAt != null && completedAt == null) return null;
    if (rawColors is! List || rawColors.isEmpty) return null;
    final colors = Uint32List(rawColors.length);
    for (var i = 0; i < rawColors.length; i++) {
      final c = rawColors[i];
      if (c is! int || !FillState.isValidColor(c)) return null;
      colors[i] = c;
    }
    colors[0] = 0;
    return Work(
      id: id,
      pictureId: pictureId,
      mode: mode,
      colors: colors,
      modified: modified,
      completed: completed,
      completedAt: completedAt,
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
