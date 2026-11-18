import 'dart:io';

import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/coloring/coloring_controller.dart';
import 'package:coloring/features/coloring/coloring_route.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/feedback.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/gallery/data/work_preview_service.dart';
import 'package:coloring/features/gallery/data/works_provider.dart';
import 'package:coloring/features/progress/data/progress_store.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../coloring/fakes.dart';
import '../coloring/model/fixtures.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('works_restart'));
  tearDown(() => root.deleteSync(recursive: true));

  /// A fresh app process: new providers over the same folders on disk.
  Future<ProviderContainer> launch(WorkRepository repository) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var ticks = 0;
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        manifestProvider.overrideWith((ref) async => fixtureManifest),
        fullAccessProvider.overrideWith((ref) => Stream.value(false)),
        pictureLoaderProvider.overrideWithValue(FakePictureLoader()),
        workRepositoryProvider.overrideWithValue(repository),
        progressDirectoryProvider.overrideWithValue(() async => root),
        coloringFeedbackProvider.overrideWithValue(RecordingFeedback()),
        coloringClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 11, 18).add(Duration(seconds: ticks++)),
        ),
      ],
    );
  }

  testWidgets('works and previews survive a restart', (tester) async {
    await tester.runAsync(() async {
      final worksDir = Directory('${root.path}/works')..createSync();
      final repoA = WorkRepository(() async => worksDir);
      addTearDown(repoA.dispose);
      final saved = <WorkChange>[];
      final changes = repoA.changes.listen(saved.add);
      addTearDown(changes.cancel);

      // Process A: a new work in numbers mode, one fill, leave the screen.
      final a = await launch(repoA);
      addTearDown(a.dispose);
      const newWork = ColoringRequest(
        freePictureId,
        newMode: ColoringMode.numbers,
      );
      final subscription = a.listen(
        coloringControllerProvider(newWork),
        (_, _) {},
      );
      await a.read(coloringControllerProvider(newWork).future);
      final (x, y) = fixtureLabels[1]!;
      a
          .read(coloringControllerProvider(newWork).notifier)
          .tap(x, y, tolerance: 4);
      subscription.close();
      // Let the auto-dispose controller go, then the save and the preview.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await a.read(workPreviewServiceProvider).idle;
      for (var i = 0; i < 100 && saved.whereType<PreviewSaved>().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final work = saved.whereType<WorkSaved>().last.work;
      expect(work.colors[1], red);
      expect(saved.whereType<PreviewSaved>().single.workId, work.id);
      a.dispose();

      // Process B: fresh providers and a fresh repository on the same folder.
      final repoB = WorkRepository(() async => worksDir);
      addTearDown(repoB.dispose);
      final b = await launch(repoB);
      addTearDown(b.dispose);
      b.listen(worksProvider, (_, _) {});
      final listed = await b.read(worksProvider.future);
      expect(listed, hasLength(1));
      final summary = listed.single;
      expect(summary.work.id, work.id);
      expect(summary.work.mode, ColoringMode.numbers);
      expect(summary.preview, isNotNull);
      expect(summary.previewStale, isFalse);
      expect(await summary.preview!.file.exists(), isTrue);
      final png = await summary.preview!.file.readAsBytes();
      expect(png.sublist(1, 4), 'PNG'.codeUnits);

      final continued = ColoringRequest(freePictureId, workId: work.id);
      b.listen(coloringControllerProvider(continued), (_, _) {});
      final state = await b.read(coloringControllerProvider(continued).future);
      expect(state.mode, ColoringMode.numbers);
      final sink = RecordingSink();
      b.read(coloringControllerProvider(continued).notifier).attachCanvas(sink);
      expect(sink.lastState!.colors, work.colors);
      expect(sink.lastState!.colors[1], red);
    });
  });
}
