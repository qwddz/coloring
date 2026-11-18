import 'dart:io';

import 'package:coloring/features/coloring/coloring_screen.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/game/fill_renderer.dart';
import 'package:coloring/features/gallery/data/gallery_backend.dart';
import 'package:coloring/features/gallery/data/share_backend.dart';
import 'package:coloring/features/gallery/data/work_exporter.dart';
import 'package:coloring/features/gallery/data/work_preview_service.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/coloring/fakes.dart';
import '../features/gallery/fake_preview_service.dart';
import '../features/gallery/fakes.dart';

/// App-level tests open the coloring screen for pictures of
/// `testManifest`, which have no files: every picture opens the small
/// fixture picture, works stay in memory, fills are drawn flat and previews
/// are only recorded (in [previews] when given). Exports go to fake
/// gallery and share backends ([gallery], [share] when given); shared files
/// land in a folder of the system temp directory.
List<Override> coloringScreenOverrides({
  FakePreviewService? previews,
  InMemoryWorkRepository? works,
  FakeGalleryBackend? gallery,
  FakeShareBackend? share,
}) => [
  pictureLoaderProvider.overrideWithValue(FakePictureLoader()),
  workRepositoryProvider.overrideWithValue(works ?? InMemoryWorkRepository()),
  workPreviewServiceProvider.overrideWithValue(
    previews ?? FakePreviewService(),
  ),
  fillRendererProvider.overrideWith(
    (ref) async =>
        (meta, regions) => FlatFillRenderer(meta),
  ),
  galleryBackendProvider.overrideWithValue(gallery ?? FakeGalleryBackend()),
  shareBackendProvider.overrideWithValue(share ?? FakeShareBackend()),
  shareDirectoryProvider.overrideWithValue(
    () async => Directory('${Directory.systemTemp.path}/coloring_test_share'),
  ),
];

/// The coloring game draws every frame, so a screen showing it never
/// settles: pump through route transitions instead.
Future<void> pumpColoringFrames(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
