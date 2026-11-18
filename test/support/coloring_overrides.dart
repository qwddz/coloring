import 'package:coloring/features/coloring/coloring_screen.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/game/fill_renderer.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/coloring/fakes.dart';

/// App-level tests open the coloring screen for pictures of
/// `testManifest`, which have no files: every picture opens the small
/// fixture picture, works stay in memory and fills are drawn flat.
List<Override> coloringScreenOverrides() => [
  pictureLoaderProvider.overrideWithValue(FakePictureLoader()),
  workRepositoryProvider.overrideWithValue(InMemoryWorkRepository()),
  fillRendererProvider.overrideWith(
    (ref) async =>
        (meta, regions) => FlatFillRenderer(meta),
  ),
];

/// The coloring game draws every frame, so a screen showing it never
/// settles: pump through route transitions instead.
Future<void> pumpColoringFrames(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
