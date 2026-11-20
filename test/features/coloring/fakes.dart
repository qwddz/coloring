import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/feedback.dart';
import 'package:coloring/features/coloring/model/canvas_sink.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/progress/data/work_repository.dart';

import 'model/fixtures.dart';

const freePictureId = 'fix_free';
const paidPictureId = 'fix_paid';

/// A manifest with one free and one paid picture; both open the synthetic
/// 16×12 fixture picture through [FakePictureLoader].
final fixtureManifest = ContentManifest.fromJson({
  'version': 1,
  'categories': [
    {
      'id': 'fix',
      'title': {'uk': 'Тест', 'en': 'Test', 'ru': 'Тест'},
      'pictures': [
        {
          'id': freePictureId,
          'title': {'uk': 'Безкоштовна', 'en': 'Free', 'ru': 'Бесплатная'},
          'level': 'simple',
          'free': true,
          'asset': 'coloring/free/$freePictureId/',
        },
        {
          'id': paidPictureId,
          'title': {'uk': 'Платна', 'en': 'Paid', 'ru': 'Платная'},
          'level': 'simple',
          'free': false,
          'url': 'fix/$paidPictureId.zip',
          'sha256': '${'0' * 63}1',
        },
      ],
    },
  ],
});

ui.Image _tinyImage() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(1, 1);
  } finally {
    picture.dispose();
  }
}

/// Returns the fixture picture (with 1×1 images) for any entry.
class FakePictureLoader implements PictureLoader {
  final loadedIds = <String>[];
  final pictures = <LoadedPicture>[];

  @override
  Future<LoadedPicture> load(
    PictureEntry entry, {
    void Function(double progress)? onProgress,
  }) async {
    loadedIds.add(entry.id);
    final picture = LoadedPicture(
      regionsImage: _tinyImage(),
      linesImage: _tinyImage(),
      map: fixtureMap(),
      meta: fixtureMeta(),
    );
    pictures.add(picture);
    return picture;
  }
}

/// Works kept as JSON in memory, so a save and a later read round-trip like
/// files do. [saves] records every write in order; [listCalls],
/// [previewsCalls] and [previewOfCalls] count listings and preview lookups. Previews are kept as bytes in [previewBytes]; their files
/// are written only when [previewDirectory] is given, else the paths are
/// never created.
class InMemoryWorkRepository implements WorkRepository {
  InMemoryWorkRepository({this.previewDirectory});

  final Directory? previewDirectory;
  final _files = <String, String>{};
  final _previews = <String, WorkPreview>{};
  final _changes = StreamController<WorkChange>.broadcast();
  final saves = <Work>[];
  final previewBytes = <String, Uint8List>{};
  int listCalls = 0;
  int previewsCalls = 0;
  int previewOfCalls = 0;

  @override
  Stream<WorkChange> get changes => _changes.stream;

  @override
  Future<void> save(Work work) async {
    saves.add(work);
    _files[work.id] = jsonEncode(work.toJson());
    _changes.add(WorkSaved(work));
  }

  @override
  Future<Work?> byId(String workId) async {
    final text = _files[workId];
    if (text == null) return null;
    final work = Work.fromJson(jsonDecode(text));
    return work != null && work.id == workId ? work : null;
  }

  @override
  Future<List<Work>> worksFor(String pictureId) async => [
    for (final text in _files.values)
      if (Work.fromJson(jsonDecode(text)) case final work?
          when work.pictureId == pictureId)
        work,
  ];

  @override
  Future<Work?> latestFor(String pictureId) async {
    Work? latest;
    for (final work in await worksFor(pictureId)) {
      if (latest == null || work.modified.isAfter(latest.modified)) {
        latest = work;
      }
    }
    return latest;
  }

  @override
  Future<List<Work>> list() async {
    listCalls++;
    return [for (final text in _files.values) ?Work.fromJson(jsonDecode(text))];
  }

  @override
  Future<WorkPreview?> previewOf(String workId) async {
    previewOfCalls++;
    return _previews[workId];
  }

  @override
  Future<Map<String, WorkPreview>> previews() async {
    previewsCalls++;
    return Map.of(_previews);
  }

  @override
  Future<void> savePreview(
    String workId,
    DateTime sourceModified,
    Uint8List png,
  ) async {
    final millis = sourceModified.millisecondsSinceEpoch;
    final dir = previewDirectory;
    final file = File('${dir?.path ?? 'memory'}/$workId.p$millis.png');
    if (dir != null) {
      final old = _previews[workId]?.file;
      await file.writeAsBytes(png, flush: true);
      if (old != null && old.path != file.path && await old.exists()) {
        await old.delete();
      }
    }
    final preview = (
      file: file,
      sourceModified: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
    );
    previewBytes[workId] = Uint8List.fromList(png);
    _previews[workId] = preview;
    _changes.add(PreviewSaved(workId, preview));
  }

  @override
  void dispose() => _changes.close();
}

class RecordingFeedback implements ColoringFeedback {
  final calls = <String>[];

  int count(String call) => calls.where((c) => c == call).length;

  @override
  void fill() => calls.add('fill');

  @override
  void rejected() => calls.add('rejected');

  @override
  void completed() => calls.add('completed');

  @override
  void hint() => calls.add('hint');
}

/// Records what the controller pushes to the canvas.
class RecordingSink implements ColoringCanvasSink {
  final fills = <(List<RegionChange>, double?, double?)>[];
  final highlights = <int?>[];
  final labels = <bool>[];
  final rejected = <int>[];
  final hints = <(int, int)>[];
  final focuses = <List<int>>[];
  FillState? lastState;

  @override
  void showFill(
    FillState state,
    List<RegionChange> changes, {
    double? waveX,
    double? waveY,
  }) {
    lastState = state;
    fills.add((List.of(changes), waveX, waveY));
  }

  @override
  void setHighlight(int? paletteIndex) => highlights.add(paletteIndex);

  @override
  void setLabelsEnabled(bool enabled) => labels.add(enabled);

  @override
  void flashRejected(int regionId) => rejected.add(regionId);

  @override
  void showHint(int regionId, int color) => hints.add((regionId, color));

  @override
  void focusOn(List<int> regionIds) => focuses.add(List.of(regionIds));
}
