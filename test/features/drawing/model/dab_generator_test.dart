import 'dart:math';

import 'package:coloring/features/drawing/model/brush_size.dart';
import 'package:coloring/features/drawing/model/dab_generator.dart';
import 'package:coloring/features/drawing/model/drawing_tool.dart';
import 'package:coloring/features/drawing/model/stroke.dart';
import 'package:coloring/features/drawing/model/symmetry.dart';
import 'package:flutter_test/flutter_test.dart';

const int red = 0xFFE53935;

StrokeInput input(
  DrawingTool tool,
  List<StrokePoint> points, {
  BrushSize size = BrushSize.medium,
  int seed = 7,
  SymmetryMode symmetry = SymmetryMode.off,
}) => StrokeInput(
  tool: tool,
  color: red,
  size: size,
  seed: seed,
  symmetry: symmetry,
  points: points,
);

List<StrokePoint> line(double x0, double y0, double x1, double y1, int n) => [
  for (var i = 0; i <= n; i++)
    StrokePoint(
      x0 + (x1 - x0) * i / n,
      y0 + (y1 - y0) * i / n,
      tMillis: i * 16,
    ),
];

/// A wobbly stroke with varying pressure.
List<StrokePoint> scribble(int seed, int n) {
  final r = Random(seed);
  var x = 300.0;
  var y = 300.0;
  return [
    for (var i = 0; i < n; i++)
      StrokePoint(
        x += r.nextDouble() * 30 - 10,
        y += r.nextDouble() * 30 - 15,
        pressure: r.nextDouble(),
        tMillis: i * 8,
      ),
  ];
}

double spacingOf(DrawingTool tool, BrushSize size, {double pressure = 1}) {
  final spec = tool.spec;
  return spec.spacing *
      2 *
      size.width /
      2 *
      spec.radiusFactor *
      spec.pressureScale(pressure);
}

/// Hue in degrees of an opaque ARGB color.
double hueOf(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255;
  final g = ((argb >> 8) & 0xFF) / 255;
  final b = (argb & 0xFF) / 255;
  final mx = [r, g, b].reduce(max);
  final mn = [r, g, b].reduce(min);
  final d = mx - mn;
  if (d == 0) return 0;
  double h;
  if (mx == r) {
    h = ((g - b) / d) % 6;
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return (h * 60) % 360;
}

void main() {
  group('spacing', () {
    test('pencil dabs are evenly spaced along a straight line (±1 px)', () {
      final dabs = DabGenerator.generate(
        input(DrawingTool.pencil, line(100, 100, 700, 100, 80)),
      );
      final expected = spacingOf(DrawingTool.pencil, BrushSize.medium);
      expect(dabs.length, greaterThan(100));
      expect(dabs.first.x, 100);
      for (var i = 1; i < dabs.length; i++) {
        final d = sqrt(
          pow(dabs[i].x - dabs[i - 1].x, 2) + pow(dabs[i].y - dabs[i - 1].y, 2),
        );
        expect(d, closeTo(expected, 1), reason: 'gap $i');
      }
    });

    test('felt dabs are evenly spaced along a curve (±1 px)', () {
      final points = [
        for (var i = 0; i <= 60; i++)
          StrokePoint(
            1000 + 400 * cos(i * pi / 60),
            800 + 400 * sin(i * pi / 60),
          ),
      ];
      final dabs = DabGenerator.generate(
        input(DrawingTool.felt, points, size: BrushSize.huge),
      );
      final expected = spacingOf(DrawingTool.felt, BrushSize.huge);
      expect(dabs.length, greaterThan(50));
      for (var i = 1; i < dabs.length; i++) {
        final d = sqrt(
          pow(dabs[i].x - dabs[i - 1].x, 2) + pow(dabs[i].y - dabs[i - 1].y, 2),
        );
        expect(d, closeTo(expected, 1), reason: 'gap $i');
      }
    });

    test('stamps are 1.6 × their size apart', () {
      final dabs = DabGenerator.generate(
        input(DrawingTool.stampStar, line(0, 500, 2000, 500, 100)),
      );
      final diameter =
          BrushSize.medium.width * DrawingTool.stampStar.spec.radiusFactor;
      for (var i = 1; i < dabs.length; i++) {
        expect(dabs[i].x - dabs[i - 1].x, closeTo(1.6 * diameter, 1));
      }
    });
  });

  test('incremental generation equals batch generation for every tool', () {
    for (final tool in DrawingTool.values) {
      for (final symmetry in SymmetryMode.values) {
        final stroke = input(
          tool,
          scribble(tool.index + 1, 40),
          seed: 99,
          symmetry: symmetry,
        );
        final copies = mirror(stroke.points, symmetry);
        final incremental = <Dab>[];
        for (var c = 0; c < copies.length; c++) {
          final g = DabGenerator.forInput(stroke, mirrored: c == 1);
          for (final p in copies[c]) {
            incremental.addAll(g.add(p));
          }
          incremental.addAll(g.finish());
        }
        expect(
          incremental,
          DabGenerator.generate(stroke),
          reason: '${tool.name} ${symmetry.name}',
        );
      }
    }
  });

  test('the same seed replays identically; other seeds differ', () {
    for (final tool in [DrawingTool.pastel, DrawingTool.airbrush]) {
      final points = scribble(3, 30);
      final a = DabGenerator.generate(input(tool, points, seed: 1));
      final b = DabGenerator.generate(input(tool, points, seed: 1));
      final c = DabGenerator.generate(input(tool, points, seed: 2));
      expect(a, b, reason: tool.name);
      expect(a, isNot(equals(c)), reason: tool.name);
    }
  });

  test('pastel picks among the 4 grain sprites', () {
    final dabs = DabGenerator.generate(
      input(DrawingTool.pastel, line(0, 0, 1500, 0, 60)),
    );
    expect(dabs.map((d) => d.variant).toSet(), {0, 1, 2, 3});
  });

  test('rainbow hue grows along the stroke by 1° per 6 px', () {
    final dabs = DabGenerator.generate(
      input(DrawingTool.rainbow, line(100, 700, 700, 700, 60)),
    );
    final hues = [for (final d in dabs) hueOf(d.color)];
    var unwrapped = hues.first;
    var previous = hues.first;
    for (final h in hues.skip(1)) {
      var step = h - previous;
      if (step < -180) step += 360;
      expect(step, greaterThan(-1), reason: 'hue never goes back');
      unwrapped += step;
      previous = h;
    }
    final length = dabs.last.x - dabs.first.x;
    expect(unwrapped - hues.first, closeTo(length / 6, 2));
  });

  group('taps', () {
    test('a tap is one dab', () {
      final g = DabGenerator(
        tool: DrawingTool.pencil,
        color: red,
        size: BrushSize.small,
        seed: 1,
      );
      final first = g.add(const StrokePoint(50, 60));
      expect(first, hasLength(1));
      expect(first.single.x, 50);
      expect(first.single.y, 60);
      expect(first.single.color, red);
      expect(g.add(const StrokePoint(50, 60)), isEmpty);
      expect(g.finish(), isEmpty);
    });

    test('a tap is one stamp', () {
      for (final tool in [DrawingTool.stampStar, DrawingTool.stampHeart]) {
        final dabs = DabGenerator.generate(
          input(tool, const [StrokePoint(400, 400)]),
        );
        expect(dabs, hasLength(1), reason: tool.name);
      }
    });

    test('stamps jitter rotation ±20° and size ±15 %', () {
      final dabs = DabGenerator.generate(
        input(DrawingTool.stampHeart, line(0, 500, 2000, 500, 100)),
      );
      final base = BrushSize.medium.width / 2;
      for (final d in dabs) {
        expect(d.rotation.abs(), lessThanOrEqualTo(20 * pi / 180));
        expect(d.radius, inInclusiveRange(base * 0.85, base * 1.15));
      }
      expect(dabs.map((d) => d.rotation).toSet().length, greaterThan(1));
    });
  });

  test('airbrush sprays only while moving', () {
    final g = DabGenerator(
      tool: DrawingTool.airbrush,
      color: red,
      size: BrushSize.large,
      seed: 5,
    );
    final first = g.add(const StrokePoint(500, 500, tMillis: 0));
    expect(first, isNotEmpty);
    for (var t = 1; t <= 20; t++) {
      expect(g.add(StrokePoint(500, 500, tMillis: t * 16)), isEmpty);
    }
    expect(g.finish(), isEmpty);
    final radius =
        BrushSize.large.width / 2 * DrawingTool.airbrush.spec.radiusFactor;
    for (final dot in first) {
      final d = sqrt(pow(dot.x - 500, 2) + pow(dot.y - 500, 2));
      expect(d, lessThanOrEqualTo(radius + 1e-9));
      expect(dot.alpha, DrawingTool.airbrush.spec.dabAlpha);
    }
  });

  test('neon draws a glow pass and a lighter core pass per point', () {
    final dabs = DabGenerator.generate(
      input(DrawingTool.neon, line(0, 0, 300, 0, 10)),
    );
    expect(dabs.length.isEven, isTrue);
    for (var i = 0; i < dabs.length; i += 2) {
      final glow = dabs[i];
      final core = dabs[i + 1];
      expect(glow.pass, 0);
      expect(core.pass, 1);
      expect(glow.x, core.x);
      expect(glow.radius / core.radius, closeTo(2.2 / 0.45, 1e-9));
      expect(glow.alpha, closeTo(0.35, 1e-9));
      expect(glow.color, red);
      expect(core.color, mixWithWhite(red, 0.7));
    }
  });

  test('eraser paints opaque white, fill paints nothing', () {
    final points = line(0, 0, 100, 0, 5);
    final eraser = DabGenerator.generate(input(DrawingTool.eraser, points));
    expect(eraser, isNotEmpty);
    expect(
      eraser.every((d) => d.color == drawingWhite && d.alpha == 1),
      isTrue,
    );
    expect(DabGenerator.generate(input(DrawingTool.fill, points)), isEmpty);
  });

  test('stylus pressure scales the pencil 0.5–1.2×', () {
    Dab tap(double pressure) => DabGenerator.generate(
      input(DrawingTool.pencil, [StrokePoint(0, 0, pressure: pressure)]),
    ).single;
    final full = BrushSize.medium.width / 2 * 0.5;
    expect(tap(0).radius, closeTo(full * 0.5, 1e-9));
    expect(tap(1).radius, closeTo(full * 1.2, 1e-9));
  });

  test('the mirror copy is the exact mirror image', () {
    for (final tool in [
      DrawingTool.pastel,
      DrawingTool.airbrush,
      DrawingTool.stampStar,
    ]) {
      final stroke = input(
        tool,
        scribble(11, 25),
        symmetry: SymmetryMode.vertical,
      );
      final all = DabGenerator.generate(stroke);
      final half = all.length ~/ 2;
      expect(all.length, half * 2, reason: tool.name);
      for (var i = 0; i < half; i++) {
        final a = all[i];
        final b = all[half + i];
        expect(b.x, closeTo(drawingCanvasWidth - a.x, 1e-6), reason: tool.name);
        expect(b.y, closeTo(a.y, 1e-6));
        expect(b.radius, closeTo(a.radius, 1e-9));
        expect(b.rotation, closeTo(-a.rotation, 1e-12));
        expect(b.variant, a.variant);
      }
    }
  });

  test('hsvToArgb hits the primaries', () {
    expect(hsvToArgb(0, 1, 1), 0xFFFF0000);
    expect(hsvToArgb(120, 1, 1), 0xFF00FF00);
    expect(hsvToArgb(240, 1, 1), 0xFF0000FF);
    expect(hsvToArgb(360, 1, 1), 0xFFFF0000);
    expect(mixWithWhite(0xFF000000, 1), 0xFFFFFFFF);
    expect(mixWithWhite(0x80000000, 0), 0x80000000);
  });
}
