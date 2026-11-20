import 'dart:async';

import 'package:coloring/features/drawing/data/tool_access.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<bool> access;
  late ProviderContainer container;

  setUp(() {
    access = StreamController<bool>();
    container = ProviderContainer(
      overrides: [fullAccessProvider.overrideWith((ref) => access.stream)],
    );
  });
  tearDown(() {
    container.dispose();
    access.close();
  });

  Map<DrawingTool, bool> tools() => {
    for (final tool in DrawingTool.values)
      tool: container.read(canUseToolProvider(tool)),
  };

  Future<void> send(bool value) async {
    access.add(value);
    await container.read(fullAccessProvider.future);
    await Future<void>.delayed(Duration.zero);
  }

  test('free tools are usable and paid ones locked while loading', () {
    final subs = [
      for (final tool in DrawingTool.values)
        container.listen(canUseToolProvider(tool), (_, _) {}),
      container.listen(canUseSymmetryProvider, (_, _) {}),
    ];
    addTearDown(() {
      for (final s in subs) {
        s.close();
      }
    });

    expect(tools(), {for (final t in DrawingTool.values) t: t.isFree});
    expect(container.read(canUseSymmetryProvider), isFalse);
  });

  test('follows the access: everything with it, free tools without', () async {
    final subs = [
      for (final tool in DrawingTool.values)
        container.listen(canUseToolProvider(tool), (_, _) {}),
      container.listen(canUseSymmetryProvider, (_, _) {}),
    ];
    addTearDown(() {
      for (final s in subs) {
        s.close();
      }
    });

    await send(true);
    expect(tools().values, everyElement(isTrue));
    expect(container.read(canUseSymmetryProvider), isTrue);

    await send(false);
    expect(tools(), {for (final t in DrawingTool.values) t: t.isFree});
    expect(container.read(canUseSymmetryProvider), isFalse);
  });

  test('the free set is exactly pencil, felt, marker, eraser, rainbow', () {
    expect(
      {
        for (final t in DrawingTool.values)
          if (container.read(canUseToolProvider(t))) t,
      },
      {
        DrawingTool.pencil,
        DrawingTool.felt,
        DrawingTool.marker,
        DrawingTool.eraser,
        DrawingTool.rainbow,
      },
    );
  });
}
