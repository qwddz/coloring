import 'dart:convert';
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
/// files do. [saves] records every write in order.
class InMemoryWorkRepository implements WorkRepository {
  final _files = <String, String>{};
  final saves = <Work>[];

  @override
  Future<void> save(Work work) async {
    saves.add(work);
    _files[work.id] = jsonEncode(work.toJson());
  }

  @override
  Future<Work?> latestFor(String pictureId) async {
    Work? latest;
    for (final work in await list()) {
      if (work.pictureId != pictureId) continue;
      if (latest == null || work.modified.isAfter(latest.modified)) {
        latest = work;
      }
    }
    return latest;
  }

  @override
  Future<List<Work>> list() async => [
    for (final text in _files.values) ?Work.fromJson(jsonDecode(text)),
  ];
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
}
