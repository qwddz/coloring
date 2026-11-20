import 'dart:async';
import 'dart:ui' as ui;

import 'package:coloring/features/drawing/drawing_controller.dart';
import 'package:coloring/features/drawing/drawing_route.dart';
import 'package:coloring/features/drawing/drawing_state.dart';
import 'package:coloring/features/drawing/model/brush_size.dart';
import 'package:coloring/features/drawing/model/dab_generator.dart';
import 'package:coloring/features/drawing/model/drawing_record.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/drawing/model/stroke.dart';
import 'package:coloring/features/drawing/model/symmetry.dart';
import 'package:coloring/features/drawing/render/brush_sprites.dart';
import 'package:coloring/features/palette/data/recent_colors.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controller_harness.dart';
import 'fakes.dart';

const _red = 0xFFD2483F;
const _w = drawingCanvasWidth;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late DrawingHarness h;

  void goTo(List<AppLifecycleState> states) {
    for (final state in states) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  setUp(() async {
    goTo(const [AppLifecycleState.resumed]);
    SharedPreferences.setMockInitialValues({});
    h = DrawingHarness(await SharedPreferences.getInstance());
  });

  /// Saves a drawing with one stroke through a container of its own and
  /// returns its id.
  Future<String> savedDrawing(DrawingRequest request) async {
    final c = h.container();
    final controller = await openDrawing(c, request);
    drawStroke(controller, [(100, 100), (400, 300)]);
    await controller.flushNow();
    final id = stateOf(c, request).drawingId;
    c.dispose();
    return id;
  }

  group('opening', () {
    test('a new sheet is blank, keeps its id and is never written', () async {
      final c = h.container();
      const request = DrawingRequest(newId: 'drawing-1');
      final controller = await openDrawing(c, request);
      final state = stateOf(c, request);
      expect(state.drawingId, 'drawing-1');
      expect(state.isEmpty, isTrue);
      expect(state.tool, DrawingTool.pencil);
      expect(state.symmetry, SymmetryMode.off);
      expect(state.canUndo, isFalse);

      expect(await controller.flushNow(), isFalse);
      goTo(const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.drawings.saves, isEmpty);
      expect(h.previews.calls, isEmpty);
      expect(h.timers.started, isEmpty);
    });

    test('an unknown ?work= opens a new blank drawing', () async {
      final c = h.container();
      const request = DrawingRequest(workId: 'missing');
      await openDrawing(c, request);
      final state = stateOf(c, request);
      expect(state.isEmpty, isTrue);
      expect(state.drawingId, isNot('missing'));
      expect(state.drawingId, startsWith('drawing-'));
    });

    test('?work= opens that drawing with its pixels', () async {
      final first = await savedDrawing(const DrawingRequest(newId: 'a'));
      await savedDrawing(const DrawingRequest(newId: 'b'));

      final c = h.container();
      final request = DrawingRequest(workId: first);
      final controller = await openDrawing(c, request);
      expect(stateOf(c, request).drawingId, 'a');
      expect(stateOf(c, request).isEmpty, isFalse);
      final pixels = await pixelsOf(controller);
      expect(argbAt(pixels, _w, 250, 200), isNot(drawingWhite));
      expect(argbAt(pixels, _w, 1800, 1400), drawingWhite);
    });

    test('a plain request opens the latest drawing', () async {
      await savedDrawing(const DrawingRequest(newId: 'a'));
      await savedDrawing(const DrawingRequest(newId: 'b'));

      final c = h.container();
      await openDrawing(c);
      expect(stateOf(c).drawingId, 'b');
      expect(stateOf(c).isEmpty, isFalse);
    });

    test('an error while picking the id releases the engine', () async {
      h = DrawingHarness(h.prefs, drawings: _FailingSecondById());
      final c = h.container();
      await c.read(brushSpritesProvider.future);
      final previousCreate = ui.Image.onCreate;
      final previousDispose = ui.Image.onDispose;
      final live = <ui.Image>{};
      ui.Image.onCreate = live.add;
      ui.Image.onDispose = live.remove;
      addTearDown(() {
        ui.Image.onCreate = previousCreate;
        ui.Image.onDispose = previousDispose;
      });
      const request = DrawingRequest(newId: 'drawing-x');
      c.listen(drawingControllerProvider(request), (_, _) {});

      await expectLater(
        c.read(drawingControllerProvider(request).future),
        throwsA(isA<StateError>()),
      );
      expect(live, isEmpty, reason: 'the engine and the atlas clone leaked');
    });

    test('a plain request with no drawings opens a blank one', () async {
      final c = h.container();
      await openDrawing(c);
      expect(stateOf(c).isEmpty, isTrue);
      expect(stateOf(c).drawingId, startsWith('drawing-'));
    });
  });

  group('saving', () {
    test('autosave writes only when the debounce timer fires', () async {
      final c = h.container();
      final controller = await openDrawing(c);
      drawStroke(controller, [(100, 100), (300, 300)]);
      drawStroke(controller, [(500, 100), (700, 300)]);
      await controller.idle;
      expect(h.drawings.saves, isEmpty);
      final active = h.timers.active;
      expect(active, hasLength(1));
      expect(active.single.delay, const Duration(seconds: 2));

      active.single.fire();
      final id = stateOf(c).drawingId;
      final record = await h.drawings.byId(id);
      expect(record, isNotNull);
      expect(h.drawings.saves, hasLength(1));
      expect(record!.width, drawingCanvasWidth);
      expect(record.height, drawingCanvasHeight);
      expect(h.drawings.rasters[id]!.sublist(1, 4), 'PNG'.codeUnits);
      expect(stateOf(c).isEmpty, isFalse);
      expect(h.drawings.saves.single.id, id);
      expect(await controller.flushNow(), isFalse, reason: 'nothing new');
    });

    test('pause saves and queues a preview of the saved state', () async {
      final c = h.container();
      final controller = await openDrawing(c);
      drawStroke(controller, [(100, 100), (300, 300)]);
      goTo(const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      await until(() => h.previews.calls.isNotEmpty, reason: 'preview');
      final record = h.drawings.saves.single;
      final call = h.previews.calls.single;
      expect(call.drawingId, record.id);
      expect(call.sourceModified, record.modified);
      expect(call.cloneValid, isTrue);
      expect(
        (call.width, call.height),
        (drawingCanvasWidth, drawingCanvasHeight),
      );
      expect(await controller.flushNow(), isFalse);
    });

    test('dispose saves and queues a preview', () async {
      final c = h.container();
      final controller = await openDrawing(c);
      drawStroke(controller, [(100, 100), (300, 300)]);
      final id = stateOf(c).drawingId;
      c.dispose();
      expect(await h.drawings.byId(id), isNotNull);
      await until(() => h.previews.calls.isNotEmpty, reason: 'preview');
      expect(h.previews.calls.single.drawingId, id);
      expect(h.previews.calls.single.cloneValid, isTrue);
    });

    test('a fill that changes nothing on a new sheet writes nothing', () async {
      final c = h.container(fullAccess: () => Stream.value(true));
      final controller = await openDrawing(c);
      expect(
        await controller.selectTool(DrawingTool.fill),
        ToolSelection.selected,
      );
      controller.selectColor(drawingWhite);
      controller.fillAt(20, 20);
      await controller.idle;
      expect(stateOf(c).isEmpty, isTrue);
      expect(stateOf(c).canUndo, isFalse);
      await controller.flushNow();
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.drawings.records, isEmpty);
      expect(h.previews.calls, isEmpty);
    });
  });

  group('history', () {
    test('undo and redo flags follow the history; clear is undoable', () async {
      final c = h.container();
      final controller = await openDrawing(c);
      drawStroke(controller, [(100, 100), (300, 300)]);
      drawStroke(controller, [(500, 100), (700, 300)]);
      await controller.idle;
      expect(stateOf(c).canUndo, isTrue);
      expect(stateOf(c).canRedo, isFalse);
      final drawn = await pixelsOf(controller);

      controller.undo();
      await controller.idle;
      expect(stateOf(c).canUndo, isTrue);
      expect(stateOf(c).canRedo, isTrue);
      controller.undo();
      await controller.idle;
      expect(stateOf(c).canUndo, isFalse);
      expect(argbAt(await pixelsOf(controller), _w, 200, 200), drawingWhite);

      controller.redo();
      controller.redo();
      await controller.idle;
      expect(stateOf(c).canRedo, isFalse);
      expect(await pixelsOf(controller), drawn);

      controller.clear();
      await controller.idle;
      expect(argbAt(await pixelsOf(controller), _w, 200, 200), drawingWhite);
      controller.undo();
      await controller.idle;
      expect(await pixelsOf(controller), drawn);

      drawStroke(controller, [(900, 900), (1000, 1000)]);
      await controller.idle;
      expect(stateOf(c).canRedo, isFalse, reason: 'a new op drops redo');
      expect(stateOf(c).revision, 9);
    });

    test('clear on a sheet with nothing on it does nothing', () async {
      final c = h.container();
      const request = DrawingRequest(newId: 'drawing-1');
      final controller = await openDrawing(c, request);
      controller.clear();
      await controller.idle;
      expect(stateOf(c, request).canUndo, isFalse);
      expect(stateOf(c, request).revision, 0);
      expect(h.timers.started, isEmpty);
      expect(await controller.flushNow(), isFalse);
      expect(h.drawings.saves, isEmpty);
    });

    test('a committed stroke keeps the live dabs, in replay order', () async {
      final c = h.container(fullAccess: () => Stream.value(true));
      final controller = await openDrawing(c);
      expect(await controller.toggleSymmetry(), ToolSelection.selected);
      for (final tool in [
        DrawingTool.pencil,
        DrawingTool.rainbow,
        DrawingTool.airbrush,
        DrawingTool.watercolor,
      ]) {
        expect(await controller.selectTool(tool), ToolSelection.selected);
        drawStroke(controller, [
          (100, 100),
          (180, 140),
          (300, 120),
          (420, 300),
        ]);
        final op = controller.debugLastStroke!;
        expect(op.input.symmetry, SymmetryMode.vertical);
        expect(op.dabs, DabGenerator.generate(op.input), reason: tool.name);
      }
      await controller.idle;
    });

    test('a discarded stroke records nothing', () async {
      final c = h.container();
      final controller = await openDrawing(c);
      controller.strokeBegin(const StrokePoint(100, 100));
      controller.strokeAdd(const StrokePoint(120, 100));
      expect(controller.liveStroke!.isEmpty, isFalse);
      controller.strokeDiscard();
      await controller.idle;
      expect(controller.liveStroke!.isEmpty, isTrue);
      expect(stateOf(c).canUndo, isFalse);
      expect(stateOf(c).isEmpty, isTrue);
      expect(h.timers.started, isEmpty);
    });

    test('the live stroke stays until its commit lands', () async {
      final c = h.container();
      final controller = await openDrawing(c);
      drawStroke(controller, [(100, 100), (300, 300)]);
      expect(controller.liveStroke!.isEmpty, isFalse);
      await controller.idle;
      expect(controller.liveStroke!.isEmpty, isTrue);
      expect(h.prefs.getStringList(RecentColorsController.key), isNotEmpty);
    });

    test('an inverted stylus erases with any tool selected', () async {
      final c = h.container();
      final controller = await openDrawing(c);
      drawStroke(controller, [(100, 200), (600, 200)]);
      await controller.idle;
      expect(
        argbAt(await pixelsOf(controller), _w, 350, 200),
        isNot(drawingWhite),
      );
      controller.selectSize(BrushSize.huge);
      controller.strokeBegin(const StrokePoint(100, 200), erases: true);
      controller.strokeAdd(const StrokePoint(600, 200));
      controller.strokeEnd();
      expect(argbAt(await pixelsOf(controller), _w, 350, 200), drawingWhite);
      expect(stateOf(c).tool, DrawingTool.pencil);
    });
  });

  group('access', () {
    test('free tools select at once without the full version', () async {
      final c = h.container();
      final controller = await openDrawing(c);
      for (final tool in DrawingTool.values.where((t) => t.isFree)) {
        expect(await controller.selectTool(tool), ToolSelection.selected);
        expect(stateOf(c).tool, tool);
      }
      expect(
        await controller.selectTool(DrawingTool.pastel),
        ToolSelection.locked,
      );
      expect(await controller.toggleSymmetry(), ToolSelection.locked);
      expect(stateOf(c).tool, DrawingTool.rainbow);
      expect(stateOf(c).symmetry, SymmetryMode.off);
    });

    test('a buyer whose access loads slowly gets the paid tool', () async {
      final access = StreamController<bool>();
      addTearDown(access.close);
      final c = h.container(fullAccess: () => access.stream);
      final controller = await openDrawing(c);

      var resolved = false;
      final tool = controller.selectTool(DrawingTool.pastel)
        ..then((_) => resolved = true);
      final mirror = controller.toggleSymmetry();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resolved, isFalse, reason: 'waits for the access status');
      expect(stateOf(c).tool, DrawingTool.pencil);

      access.add(true);
      expect(await tool, ToolSelection.selected);
      expect(await mirror, ToolSelection.selected);
      expect(stateOf(c).tool, DrawingTool.pastel);
      expect(stateOf(c).symmetry, SymmetryMode.vertical);

      expect(await controller.toggleSymmetry(), ToolSelection.selected);
      expect(stateOf(c).symmetry, SymmetryMode.off);
    });

    test('without the full version a slow status resolves locked', () async {
      final access = StreamController<bool>();
      addTearDown(access.close);
      final c = h.container(fullAccess: () => access.stream);
      final controller = await openDrawing(c);
      final tool = controller.selectTool(DrawingTool.fill);
      access.add(false);
      expect(await tool, ToolSelection.locked);
      expect(stateOf(c).tool, DrawingTool.pencil);
    });

    test('a newer selection supersedes one waiting for access', () async {
      final access = StreamController<bool>();
      addTearDown(access.close);
      final c = h.container(fullAccess: () => access.stream);
      final controller = await openDrawing(c);
      final paid = controller.selectTool(DrawingTool.neon);
      expect(
        await controller.selectTool(DrawingTool.marker),
        ToolSelection.selected,
      );
      access.add(true);
      expect(await paid, ToolSelection.superseded);
      expect(stateOf(c).tool, DrawingTool.marker);
    });

    test('losing access falls back to the pencil and mirror off', () async {
      final access = StreamController<bool>();
      addTearDown(access.close);
      final c = h.container(fullAccess: () => access.stream);
      final controller = await openDrawing(c);
      access.add(true);
      expect(
        await controller.selectTool(DrawingTool.watercolor),
        ToolSelection.selected,
      );
      expect(await controller.toggleSymmetry(), ToolSelection.selected);
      drawStroke(controller, [(100, 100), (300, 300)]);
      final before = await pixelsOf(controller);

      access.add(false);
      await until(() => stateOf(c).tool == DrawingTool.pencil);
      expect(stateOf(c).symmetry, SymmetryMode.off);
      expect(await pixelsOf(controller), before, reason: 'pixels stay');
    });
  });

  group('fill', () {
    test('fills the area with the color, mirrored, with feedback', () async {
      final c = h.container(fullAccess: () => Stream.value(true));
      final controller = await openDrawing(c);
      // A vertical wall in the middle splits the sheet in two.
      controller.selectColor(0xFF2D4F8A);
      drawStroke(controller, [(_w / 2, 0), (_w / 2, drawingCanvasHeight - 1)]);
      expect(
        await controller.selectTool(DrawingTool.fill),
        ToolSelection.selected,
      );
      controller.selectColor(_red);
      controller.fillAt(100, 100);
      expect(stateOf(c).busy, isTrue);
      await controller.idle;
      expect(stateOf(c).busy, isFalse);
      var pixels = await pixelsOf(controller);
      expect(argbAt(pixels, _w, 100, 100), _red);
      expect(argbAt(pixels, _w, _w - 100, 100), drawingWhite);
      expect(h.feedback.count('fill'), 1);

      controller.undo();
      expect(await controller.toggleSymmetry(), ToolSelection.selected);
      controller.fillAt(100, 100);
      await controller.idle;
      pixels = await pixelsOf(controller);
      expect(argbAt(pixels, _w, 100, 100), _red);
      expect(argbAt(pixels, _w, _w - 100, 100), _red);
    });

    test('taps are ignored unless the fill tool is selected', () async {
      final c = h.container(fullAccess: () => Stream.value(true));
      final controller = await openDrawing(c);
      controller.fillAt(100, 100);
      await controller.idle;
      expect(stateOf(c).canUndo, isFalse);
      expect(
        await controller.selectTool(DrawingTool.fill),
        ToolSelection.selected,
      );
      controller.strokeBegin(const StrokePoint(100, 100));
      controller.strokeEnd();
      await controller.idle;
      expect(stateOf(c).canUndo, isFalse);
    });
  });

  test('every image is released after the provider is disposed', () async {
    final c = h.container(fullAccess: () => Stream.value(true));
    final controller = await openDrawing(c);
    for (var i = 0; i < 12; i++) {
      drawStroke(controller, [(100.0 + i * 50, 100), (300.0 + i * 50, 600)]);
    }
    await controller.selectTool(DrawingTool.fill);
    controller.fillAt(1900, 1400);
    controller.undo();
    await controller.selectTool(DrawingTool.marker);
    // A finger still down when the screen leaves.
    controller.strokeBegin(const StrokePoint(1000, 1000));
    controller.strokeAdd(const StrokePoint(1200, 1100));
    final engine = controller.engine!;
    final id = stateOf(c).drawingId;
    expect(engine.liveImageCount, greaterThan(0));

    c.dispose();
    await until(() => engine.liveImageCount == 0, reason: 'images released');
    expect(await h.drawings.byId(id), isNotNull);
    await until(() => h.previews.calls.isNotEmpty, reason: 'preview');
    expect(h.previews.calls.every((call) => call.cloneValid), isTrue);
  });
}

/// Opens like the in-memory repository, then fails the id check of a new
/// sheet (the second `byId`).
class _FailingSecondById extends InMemoryDrawingRepository {
  int _byIdCalls = 0;

  @override
  Future<DrawingRecord?> byId(String drawingId) {
    if (++_byIdCalls == 2) return Future.error(StateError('disk gone'));
    return super.byId(drawingId);
  }
}
