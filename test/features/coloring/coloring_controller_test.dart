import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/coloring/coloring_controller.dart';
import 'package:coloring/features/coloring/coloring_state.dart';
import 'package:coloring/features/coloring/data/picture_loader.dart';
import 'package:coloring/features/coloring/feedback.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/fill_state.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/palette/data/recent_colors.dart';
import 'package:coloring/features/progress/data/progress_store.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'model/fixtures.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FakePictureLoader loader;
  late InMemoryWorkRepository repo;
  late RecordingFeedback feedback;
  late int ticks;
  late Directory progressDir;

  void goTo(List<AppLifecycleState> states) {
    for (final state in states) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  setUp(() async {
    goTo(const [AppLifecycleState.resumed]);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    loader = FakePictureLoader();
    repo = InMemoryWorkRepository();
    feedback = RecordingFeedback();
    ticks = 0;
    progressDir = Directory.systemTemp.createTempSync('progress_ctrl');
    addTearDown(() => progressDir.deleteSync(recursive: true));
  });

  ProviderContainer makeContainer({
    Stream<bool> Function()? fullAccess,
    DateTime Function()? clock,
    WorkRepository? repository,
  }) {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        manifestProvider.overrideWith((ref) async => fixtureManifest),
        fullAccessProvider.overrideWith(
          (ref) => fullAccess?.call() ?? Stream.value(false),
        ),
        pictureLoaderProvider.overrideWithValue(loader),
        workRepositoryProvider.overrideWithValue(repository ?? repo),
        progressDirectoryProvider.overrideWithValue(() async => progressDir),
        coloringFeedbackProvider.overrideWithValue(feedback),
        coloringClockProvider.overrideWithValue(
          clock ??
              () => DateTime.utc(2026, 11, 18).add(Duration(seconds: ticks++)),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Opens [id] and keeps the auto-dispose controller alive.
  Future<ColoringState> open(ProviderContainer c, String id) {
    c.listen(coloringControllerProvider(id), (_, _) {});
    return c.read(coloringControllerProvider(id).future);
  }

  ColoringController controllerOf(ProviderContainer c, String id) =>
      c.read(coloringControllerProvider(id).notifier);

  ColoringState stateOf(ProviderContainer c, String id) =>
      c.read(coloringControllerProvider(id)).requireValue;

  void tapRegionOf(ColoringController controller, int id) {
    final (x, y) = fixtureLabels[id]!;
    controller.tap(x, y, tolerance: 4);
  }

  group('access', () {
    test('a free picture opens without the full version', () async {
      final c = makeContainer();
      final state = await open(c, freePictureId);
      expect(state.mode, ColoringMode.free);
      expect(loader.loadedIds, [freePictureId]);
    });

    test('a locked paid picture fails and is never loaded', () async {
      final c = makeContainer(fullAccess: () => Stream.value(false));
      await expectLater(
        open(c, paidPictureId),
        throwsA(isA<ColoringLockedException>()),
      );
      expect(loader.loadedIds, isEmpty);
    });

    test('a paid picture opens with the full version', () async {
      final c = makeContainer(fullAccess: () => Stream.value(true));
      await open(c, paidPictureId);
      expect(loader.loadedIds, [paidPictureId]);
    });

    test('full access arriving late still opens, not locked', () async {
      final c = makeContainer(
        fullAccess: () => Stream.fromFuture(
          Future.delayed(const Duration(milliseconds: 50), () => true),
        ),
      );
      final state = await open(c, paidPictureId);
      expect(state.picture.meta.regionCount, 5);
      expect(loader.loadedIds, [paidPictureId]);
    });

    test('an unknown id is not found and is never loaded', () async {
      final c = makeContainer();
      await expectLater(
        open(c, 'nope'),
        throwsA(isA<ColoringNotFoundException>()),
      );
      expect(loader.loadedIds, isEmpty);
    });
  });

  group('restore', () {
    test('a new picture starts empty in free mode and is not saved', () async {
      final c = makeContainer();
      final state = await open(c, freePictureId);
      expect(state.mode, ColoringMode.free);
      expect(state.tool, ColoringTool.brush);
      expect(state.selectedColor, red);
      expect(state.selectedPaletteIndex, 0);
      expect(state.picturePalette, [red, green, blue]);
      expect(state.filledFraction, 0);
      expect(state.completed, isFalse);
      expect(state.canUndo, isFalse);
      expect(state.completionSeq, 0);
      expect(repo.saves, isEmpty);
    });

    test('an existing work restores colors, mode and completion', () async {
      await repo.save(
        Work(
          id: '$freePictureId-1000',
          pictureId: freePictureId,
          mode: ColoringMode.numbers,
          colors: Uint32List.fromList([0, red, green, 0, 0, 0]),
          modified: DateTime.utc(2026, 11, 1),
          completed: true,
          completedAt: DateTime.utc(2026, 11, 1),
        ),
      );
      repo.saves.clear();
      final c = makeContainer();
      final state = await open(c, freePictureId);
      expect(state.mode, ColoringMode.numbers);
      expect(state.completed, isTrue);
      expect(state.filledFraction, closeTo(0.4, 1e-9));
      // Numbers mode starts on the first incomplete color: red has region 4.
      expect(state.selectedPaletteIndex, 0);

      final sink = RecordingSink();
      controllerOf(c, freePictureId).attachCanvas(sink);
      expect(sink.lastState!.colors, [0, red, green, 0, 0, 0]);
      expect(sink.fills.single.$1, isEmpty);
      expect(sink.labels, [true]);
      expect(sink.highlights, [0]);

      // Edits keep the same work file.
      tapRegionOf(controllerOf(c, freePictureId), 4);
      expect(repo.saves.single.id, '$freePictureId-1000');
      expect(repo.saves.single.completed, isTrue);
    });

    test('kill and restore across two containers', () async {
      final c1 = makeContainer();
      await open(c1, freePictureId);
      final controller = controllerOf(c1, freePictureId);
      tapRegionOf(controller, 1);
      controller.selectColor(base);
      tapRegionOf(controller, 2);
      controller.setMode(ColoringMode.magic);
      c1.dispose();

      final c2 = makeContainer();
      final state = await open(c2, freePictureId);
      expect(state.mode, ColoringMode.magic);
      final sink = RecordingSink();
      controllerOf(c2, freePictureId).attachCanvas(sink);
      expect(sink.lastState!.colors, [0, red, base, 0, 0, 0]);
      expect(loader.pictures, hasLength(2));
    });
  });

  group('saving', () {
    test('every changing tap writes once; no-ops do not write', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      final sink = RecordingSink();
      controller.attachCanvas(sink);
      sink.fills.clear();

      tapRegionOf(controller, 1);
      controller.selectColor(green);
      tapRegionOf(controller, 2);
      tapRegionOf(controller, 3);
      expect(repo.saves, hasLength(3));

      tapRegionOf(controller, 3); // same color again
      controller.tap(6, 0, tolerance: 0); // on a line: miss
      controller.selectColor(blue); // selection only
      expect(repo.saves, hasLength(3));

      controller.selectEraser();
      tapRegionOf(controller, 3);
      controller.undo();
      controller.clearAll();
      expect(repo.saves, hasLength(6));
      expect(repo.saves.last.colors, everyElement(0));

      final (x, y) = fixtureLabels[1]!;
      expect(sink.fills.first.$2, x);
      expect(sink.fills.first.$3, y);
      // Undo and clear redraw without a wave.
      expect(sink.fills.last.$2, isNull);
      expect(feedback.count('fill'), 6);
    });

    test('a magic stroke over 5 regions writes once', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      final sink = RecordingSink();
      controller.attachCanvas(sink);
      controller.setMode(ColoringMode.magic);
      repo.saves.clear();

      controller.beginStroke();
      for (final id in [1, 2, 4, 3, 5]) {
        final (x, y) = fixtureLabels[id]!;
        controller.strokeTo(x, y, tolerance: 4);
      }
      expect(repo.saves, isEmpty);
      expect(stateOf(c, freePictureId).filledFraction, 1);
      controller.endStroke();

      expect(repo.saves, hasLength(1));
      expect(repo.saves.single.completed, isTrue);
      expect(sink.fills.every((f) => f.$2 == null), isTrue);
      expect(stateOf(c, freePictureId).canUndo, isTrue);
    });

    test('a switch of mode writes; a repeated one does not', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      final sink = RecordingSink();
      controller.attachCanvas(sink);
      controller.setMode(ColoringMode.numbers);
      controller.setMode(ColoringMode.numbers);
      expect(repo.saves.single.mode, ColoringMode.numbers);
      expect(sink.labels.last, isTrue);
      expect(sink.highlights.last, 0);
      controller.selectPaletteIndex(2);
      expect(sink.highlights.last, 2);
      controller.setMode(ColoringMode.free);
      expect(sink.labels.last, isFalse);
      expect(sink.highlights.last, isNull);
      expect(repo.saves, hasLength(2));
    });

    test('going to the background writes a touched work', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      goTo(const [AppLifecycleState.inactive, AppLifecycleState.hidden]);
      goTo(const [AppLifecycleState.paused]);
      expect(repo.saves, isEmpty, reason: 'an untouched new work');
      goTo(const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);

      tapRegionOf(controllerOf(c, freePictureId), 1);
      expect(repo.saves, hasLength(1));
      expect(repo.saves.last.colors[1], red);
      // The tap already wrote everything: nothing to write again.
      goTo(const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      expect(repo.saves, hasLength(1));
    });

    test('inactive, hidden and paused mid-stroke write once', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      controller.setMode(ColoringMode.magic);
      repo.saves.clear();
      controller.beginStroke();
      final (x, y) = fixtureLabels[2]!;
      controller.strokeTo(x, y, tolerance: 4);
      goTo(const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      expect(repo.saves, hasLength(1));
      expect(repo.saves.single.colors[2], green);
    });

    test('a pause mid-stroke saves the regions painted so far', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      controller.setMode(ColoringMode.magic);
      repo.saves.clear();
      controller.beginStroke();
      final (x, y) = fixtureLabels[2]!;
      controller.strokeTo(x, y, tolerance: 4);
      goTo(const [AppLifecycleState.inactive]);
      expect(repo.saves.single.colors[2], green);
    });

    test('dispose saves unsaved changes and disposes the picture', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      tapRegionOf(controller, 1);
      expect(repo.saves, hasLength(1));
      controller.setMode(ColoringMode.magic);
      controller.beginStroke();
      final (x, y) = fixtureLabels[2]!;
      controller.strokeTo(x, y, tolerance: 4);
      final picture = loader.pictures.single;
      expect(picture.regionsImage.debugDisposed, isFalse);
      c.dispose();
      expect(repo.saves, hasLength(3));
      expect(repo.saves.last.colors[2], green);
      expect(picture.regionsImage.debugDisposed, isTrue);
      expect(picture.linesImage.debugDisposed, isTrue);
    });
  });

  test('a work that does not fit the picture disposes it and fails', () async {
    final c = makeContainer(repository: _MismatchedWorkRepository());
    c.listen(coloringControllerProvider(freePictureId), (_, _) {});
    await expectLater(
      c.read(coloringControllerProvider(freePictureId).future),
      throwsArgumentError,
    );
    final picture = loader.pictures.single;
    expect(picture.regionsImage.debugDisposed, isTrue);
    expect(picture.linesImage.debugDisposed, isTrue);
  });

  group('effects', () {
    test('free-mode brush fills go to recent colors', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      controller.selectColor(base);
      tapRegionOf(controller, 1);
      controller.selectColor(green);
      tapRegionOf(controller, 2);
      controller.selectEraser();
      tapRegionOf(controller, 2);
      expect(c.read(recentColorsProvider), [green, base]);

      controller.setMode(ColoringMode.numbers);
      controller.selectPaletteIndex(2);
      tapRegionOf(controller, 3);
      expect(c.read(recentColorsProvider), [green, base]);
    });

    test('a wrong number is rejected without a write', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      final sink = RecordingSink();
      controller.attachCanvas(sink);
      controller.setMode(ColoringMode.numbers);
      repo.saves.clear();

      tapRegionOf(controller, 2); // red selected, region 2 wants green
      expect(sink.rejected, [2]);
      expect(feedback.calls, ['rejected']);
      expect(stateOf(c, freePictureId).rejectSeq, 1);
      expect(repo.saves, isEmpty);

      controller.selectColor(base); // not a picture color: ignored
      expect(stateOf(c, freePictureId).selectedPaletteIndex, 0);
      controller.selectColor(green);
      expect(stateOf(c, freePictureId).selectedPaletteIndex, 1);
      tapRegionOf(controller, 2);
      expect(feedback.calls, ['rejected', 'fill']);
      expect(repo.saves, hasLength(1));
    });

    test('completion counts once and plays the fanfare once', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      controller.setMode(ColoringMode.magic);
      for (final id in [1, 2, 3, 4]) {
        tapRegionOf(controller, id);
      }
      expect(stateOf(c, freePictureId).completionSeq, 0);
      tapRegionOf(controller, 5);
      expect(stateOf(c, freePictureId).completionSeq, 1);
      expect(stateOf(c, freePictureId).completed, isTrue);

      controller.undo();
      tapRegionOf(controller, 5);
      expect(stateOf(c, freePictureId).completionSeq, 1);
      expect(stateOf(c, freePictureId).completed, isTrue);
      expect(feedback.count('completed'), 1);
      expect(feedback.count('fill'), 6);
    });

    test(
      'completion stars the picture once; clearing keeps the star',
      () async {
        final c = makeContainer();
        await open(c, freePictureId);
        final controller = controllerOf(c, freePictureId);
        expect(await c.read(progressProvider.future), isEmpty);
        controller.setMode(ColoringMode.magic);
        for (final id in [1, 2, 3, 4]) {
          tapRegionOf(controller, id);
        }
        expect(await c.read(progressProvider.future), isEmpty);
        tapRegionOf(controller, 5);
        await c.read(progressProvider.future);
        await Future<void>.delayed(Duration.zero);
        expect(c.read(progressProvider).requireValue, {freePictureId});

        controller.undo();
        controller.clearAll();
        tapRegionOf(controller, 1);
        await c.read(progressProvider.future);
        expect(c.read(progressProvider).requireValue, {freePictureId});
        await c.read(progressStoreProvider).read();
        final file = File('${progressDir.path}/progress.json');
        expect(file.existsSync(), isTrue);
        expect(file.readAsStringSync(), contains(freePictureId));
      },
    );

    test('"Done" completes a free work at 80 %, once', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      controller.finish();
      expect(stateOf(c, freePictureId).completionSeq, 0);
      for (final id in [1, 2, 3, 4]) {
        tapRegionOf(controller, id);
      }
      expect(stateOf(c, freePictureId).canFinish, isTrue);
      repo.saves.clear();
      controller.finish();
      controller.finish();
      expect(stateOf(c, freePictureId).completionSeq, 1);
      expect(feedback.count('completed'), 1);
      expect(repo.saves.single.completed, isTrue);
      expect(stateOf(c, freePictureId).canFinish, isFalse);
    });

    test('a stroke plays the fill feedback at most once per 80 ms', () async {
      var t = DateTime.utc(2026, 11, 18);
      final c = makeContainer(clock: () => t);
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      controller.setMode(ColoringMode.magic);
      controller.beginStroke();
      void strokeOver(int id) {
        final (x, y) = fixtureLabels[id]!;
        controller.strokeTo(x, y, tolerance: 4);
      }

      strokeOver(1); // t = 0: plays
      t = t.add(const Duration(milliseconds: 40));
      strokeOver(2); // 40 ms: throttled
      t = t.add(const Duration(milliseconds: 39));
      strokeOver(4); // 79 ms: throttled
      expect(feedback.count('fill'), 1);
      t = t.add(const Duration(milliseconds: 1));
      strokeOver(3); // 80 ms: plays
      expect(feedback.count('fill'), 2);
      controller.endStroke();

      // A new stroke plays at once.
      controller.undo();
      expect(feedback.count('fill'), 3);
      controller.beginStroke();
      strokeOver(1);
      expect(feedback.count('fill'), 4);
    });

    test(
      'a tap that commits a completing stroke completes and saves',
      () async {
        final c = makeContainer();
        await open(c, freePictureId);
        final controller = controllerOf(c, freePictureId);
        controller.setMode(ColoringMode.magic);
        for (final id in [1, 2, 3, 4]) {
          tapRegionOf(controller, id);
        }
        repo.saves.clear();
        controller.beginStroke();
        final (x, y) = fixtureLabels[5]!;
        controller.strokeTo(x, y, tolerance: 4);
        controller.tap(-5, -5, tolerance: 1); // a miss commits the stroke
        expect(stateOf(c, freePictureId).completionSeq, 1);
        expect(stateOf(c, freePictureId).completed, isTrue);
        expect(feedback.count('completed'), 1);
        expect(repo.saves.single.completed, isTrue);
      },
    );

    test('setMode that commits a completing stroke completes', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      controller.setMode(ColoringMode.magic);
      for (final id in [1, 2, 3, 4]) {
        tapRegionOf(controller, id);
      }
      controller.beginStroke();
      final (x, y) = fixtureLabels[5]!;
      controller.strokeTo(x, y, tolerance: 4);
      controller.setMode(ColoringMode.free);
      expect(stateOf(c, freePictureId).completionSeq, 1);
      expect(repo.saves.last.completed, isTrue);
    });

    test('a long press in free mode shows a hint', () async {
      final c = makeContainer();
      await open(c, freePictureId);
      final controller = controllerOf(c, freePictureId);
      final sink = RecordingSink();
      controller.attachCanvas(sink);
      final (x, y) = fixtureLabels[3]!;
      controller.hint(x, y, tolerance: 4);
      expect(sink.hints, [(3, blue)]);
      expect(feedback.calls, ['hint']);
      expect(repo.saves, isEmpty);

      controller.detachCanvas(sink);
      controller.hint(x, y, tolerance: 4);
      expect(sink.hints, hasLength(1));
    });
  });
}

/// Restores a work whose fill does not fit the picture, so building the
/// session throws after the picture is loaded.
class _MismatchedWorkRepository extends InMemoryWorkRepository {
  @override
  Future<Work?> latestFor(String pictureId) async => _MismatchedWork(
    id: '$pictureId-1',
    pictureId: pictureId,
    mode: ColoringMode.free,
    colors: Uint32List(fixturePaletteIndex.length + 1),
    modified: DateTime.utc(2026),
  );
}

class _MismatchedWork extends Work {
  _MismatchedWork({
    required super.id,
    required super.pictureId,
    required super.mode,
    required super.colors,
    required super.modified,
  });

  @override
  FillState toFillState(int regionCount) => FillState(regionCount - 1);
}
