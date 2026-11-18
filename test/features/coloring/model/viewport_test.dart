import 'dart:math';

import 'package:coloring/features/coloring/model/viewport.dart';
import 'package:flutter_test/flutter_test.dart';

Viewport vp(double w, double h) => Viewport(
  canvasWidth: w,
  canvasHeight: h,
  imageWidth: 2048,
  imageHeight: 1536,
);

void main() {
  test('fits 4:3 inside a 16:9 canvas (height limits)', () {
    final v = vp(1600, 900);
    expect(v.baseScale, closeTo(900 / 1536, 1e-12));
    expect(v.origin.y, closeTo(0, 1e-9));
    expect(v.origin.x, closeTo((1600 - 2048 * 900 / 1536) / 2, 1e-9));
  });

  test('fits 4:3 inside a 16:10 canvas (height limits)', () {
    final v = vp(1600, 1000);
    expect(v.baseScale, closeTo(1000 / 1536, 1e-12));
    expect(v.origin.y, closeTo(0, 1e-9));
  });

  test('wide image in a tall canvas is limited by width', () {
    final v = vp(1024, 1000);
    expect(v.baseScale, closeTo(0.5, 1e-12));
    expect(v.origin.x, closeTo(0, 1e-9));
    expect(v.origin.y, closeTo((1000 - 768) / 2, 1e-9));
  });

  test('screen to image to screen is the identity', () {
    final v = vp(1600, 900).zoomAt(const Point(700, 300), 2.5);
    for (final p in const [
      Point(0.0, 0.0),
      Point(321.5, 77.25),
      Point(900.0, 600.0),
    ]) {
      final back = v.screenToImage(v.imageToScreen(p));
      expect(back.x, closeTo(p.x, 1e-9));
      expect(back.y, closeTo(p.y, 1e-9));
    }
  });

  test('zoom is clamped to 1..4', () {
    final v = vp(1600, 900);
    expect(v.zoomAt(const Point(800, 450), 10).zoom, 4);
    expect(v.zoomAt(const Point(800, 450), 0.1).zoom, 1);
    expect(
      v.zoomAt(const Point(800, 450), 10).zoomAt(const Point(0, 0), 0.01).zoom,
      1,
    );
    expect(
      Viewport(
        canvasWidth: 1600,
        canvasHeight: 900,
        imageWidth: 2048,
        imageHeight: 1536,
        zoom: 9,
      ).zoom,
      4,
    );
  });

  test('zoomAt keeps the focal image point under the finger', () {
    var v = vp(1600, 900);
    const focal = Point(900.0, 400.0);
    final before = v.screenToImage(focal);
    v = v.zoomAt(focal, 3);
    final after = v.screenToImage(focal);
    expect(after.x, closeTo(before.x, 1e-9));
    expect(after.y, closeTo(before.y, 1e-9));
    expect(v.zoom, closeTo(3, 1e-12));
  });

  test('1x is always centered and pan does nothing', () {
    final v = vp(1600, 900);
    final panned = v.panBy(const Point(200, -300));
    expect(panned.pan, const Point(0.0, 0.0));
    expect(panned.origin, v.origin);
    final back = v
        .zoomAt(const Point(100, 100), 3)
        .zoomAt(const Point(100, 100), 1 / 3);
    expect(back.zoom, closeTo(1, 1e-12));
    expect(back.pan.x, closeTo(0, 1e-9));
    expect(back.pan.y, closeTo(0, 1e-9));
  });

  test(
    'pan is clamped so the image never leaves the canvas more than needed',
    () {
      final v = vp(1600, 900).zoomAt(const Point(800, 450), 2);
      final far = v.panBy(const Point(100000, 100000));
      final o = far.origin;
      expect(o.x, closeTo(0, 1e-9));
      expect(o.y, closeTo(0, 1e-9));
      final other = v.panBy(const Point(-100000, -100000));
      final end = other.imageToScreen(const Point(2048, 1536));
      expect(end.x, closeTo(1600, 1e-9));
      expect(end.y, closeTo(900, 1e-9));
    },
  );

  test('zoomAt near an edge is clamped', () {
    final v = vp(1600, 900).zoomAt(const Point(0, 0), 4);
    expect(v.origin.x, lessThanOrEqualTo(1e-9));
    expect(v.origin.y, lessThanOrEqualTo(1e-9));
  });

  test('imagePxPerDp is 1 / (baseScale * zoom)', () {
    final v = vp(1600, 900).zoomAt(const Point(800, 450), 2);
    expect(v.imagePxPerDp, closeTo(1 / (900 / 1536 * 2), 1e-12));
  });
}
