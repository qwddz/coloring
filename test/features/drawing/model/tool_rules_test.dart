import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/drawing/model/symmetry.dart';
import 'package:coloring/features/drawing/model/tool_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the free set is exactly pencil, felt, marker, eraser, rainbow', () {
    expect(DrawingTool.values.where((t) => t.isFree).toSet(), {
      DrawingTool.pencil,
      DrawingTool.felt,
      DrawingTool.marker,
      DrawingTool.eraser,
      DrawingTool.rainbow,
    });
  });

  test('without access only free tools are usable', () {
    for (final t in DrawingTool.values) {
      expect(canUseTool(t, fullAccess: false), t.isFree, reason: t.name);
      expect(canUseTool(t, fullAccess: true), isTrue, reason: t.name);
    }
  });

  test('mirror needs the full version', () {
    expect(canUseSymmetry(fullAccess: false), isFalse);
    expect(canUseSymmetry(fullAccess: true), isTrue);
  });

  test('losing access falls back to the pencil and mirror off', () {
    expect(
      fallbackTool(DrawingTool.neon, fullAccess: false),
      DrawingTool.pencil,
    );
    expect(fallbackTool(DrawingTool.neon, fullAccess: true), DrawingTool.neon);
    expect(
      fallbackTool(DrawingTool.rainbow, fullAccess: false),
      DrawingTool.rainbow,
    );
    expect(
      fallbackSymmetry(SymmetryMode.vertical, fullAccess: false),
      SymmetryMode.off,
    );
    expect(
      fallbackSymmetry(SymmetryMode.vertical, fullAccess: true),
      SymmetryMode.vertical,
    );
  });
}
