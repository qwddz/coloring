import 'package:coloring/features/drawing/drawing_route.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controller_harness.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late DrawingHarness h;

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({});
    h = DrawingHarness(await SharedPreferences.getInstance());
  });

  DrawingRequest requestOf(String route) =>
      DrawingRequest.fromRoute(Uri.parse(route).queryParameters);

  test('a drawing reopens after a restart with the same pixels', () async {
    final first = h.container(fullAccess: () => Stream.value(true));
    final controller = await openDrawing(first);
    drawStroke(controller, [(100, 100), (900, 700), (1500, 300)]);
    await controller.selectTool(DrawingTool.watercolor);
    controller.selectColor(0xFF5FA05A);
    drawStroke(controller, [(300, 1200), (1700, 1000)]);
    final before = await pixelsOf(controller);
    expect(h.drawings.records, isEmpty, reason: 'nothing saved before leaving');
    first.dispose();
    await h.drawings.list();

    final second = h.container();
    final reopened = await openDrawing(second);
    expect(await pixelsOf(reopened), before);
    expect(stateOf(second).isEmpty, isFalse);
    expect(h.drawings.records, hasLength(1));
  });

  test('reopening right after leaving, while the save runs, keeps the '
      'strokes', () async {
    final first = h.container();
    final controller = await openDrawing(first);
    drawStroke(controller, [(100, 100), (900, 700)]);
    drawStroke(controller, [(1200, 200), (1800, 1300)]);
    final before = await pixelsOf(controller);
    // The last stroke is still queued when the screen goes.
    drawStroke(controller, [(200, 1400), (1900, 1450)]);
    final id = stateOf(first).drawingId;
    first.dispose();
    expect(h.drawings.hasPendingSave(id), isTrue);

    final second = h.container();
    final reopened = await openDrawing(second);
    expect(stateOf(second).drawingId, id);
    final after = await pixelsOf(reopened);
    expect(after, isNot(before), reason: 'the last stroke is there too');
    expect(argbAt(after, drawingCanvasWidth, 1000, 1425), isNot(drawingWhite));
    expect(argbAt(after, drawingCanvasWidth, 500, 400), isNot(drawingWhite));
  });

  test('two new sheets in a row give two drawings, the first saved', () async {
    final c = h.container();
    final firstRequest = requestOf(drawRoute(newSheet: true));
    final secondRequest = requestOf(drawRoute(newSheet: true));
    expect(firstRequest, isNot(secondRequest));

    final first = await openDrawing(c, firstRequest);
    drawStroke(first, [(100, 100), (900, 700)]);
    // «Новый лист»: flush, then the screen replaces itself.
    final saved = first.flushNow();
    final second = await openDrawing(c, secondRequest);
    expect(stateOf(c, secondRequest).isEmpty, isTrue);
    expect(await saved, isTrue);
    drawStroke(second, [(500, 500), (700, 900)]);
    await second.flushNow();

    expect(h.drawings.records.keys, {firstRequest.newId, secondRequest.newId});
  });
}
