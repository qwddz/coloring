import 'dart:math';

const double minZoom = 1;
const double maxZoom = 4;

/// Maps between image pixels and canvas (screen) logical pixels.
///
/// The image is fitted (contain) into the canvas at 1x and centered; [pan] is
/// the extra translation on top of the centered position. Immutable: every
/// change returns a new [Viewport].
class Viewport {
  Viewport({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.imageWidth,
    required this.imageHeight,
    double zoom = minZoom,
    Point<double> pan = const Point(0, 0),
  }) : baseScale = min(canvasWidth / imageWidth, canvasHeight / imageHeight),
       zoom = zoom.clamp(minZoom, maxZoom).toDouble(),
       pan = _clampPan(
         pan,
         canvasWidth,
         canvasHeight,
         imageWidth,
         imageHeight,
         min(canvasWidth / imageWidth, canvasHeight / imageHeight) *
             zoom.clamp(minZoom, maxZoom).toDouble(),
       );

  final double canvasWidth;
  final double canvasHeight;
  final double imageWidth;
  final double imageHeight;

  /// Scale that fits the whole image into the canvas.
  final double baseScale;

  /// 1..4.
  final double zoom;

  /// Translation relative to the centered position (always zero at 1x).
  final Point<double> pan;

  double get scale => baseScale * zoom;

  /// Image pixels per logical pixel (dp).
  double get imagePxPerDp => 1 / scale;

  Point<double> get origin => Point(
    (canvasWidth - imageWidth * scale) / 2 + pan.x,
    (canvasHeight - imageHeight * scale) / 2 + pan.y,
  );

  Point<double> screenToImage(Point<double> p) {
    final o = origin;
    return Point((p.x - o.x) / scale, (p.y - o.y) / scale);
  }

  Point<double> imageToScreen(Point<double> p) {
    final o = origin;
    return Point(o.x + p.x * scale, o.y + p.y * scale);
  }

  /// Zooms by [factor] keeping the image point under [focal] fixed.
  Viewport zoomAt(Point<double> focal, double factor) {
    final newZoom = (zoom * factor).clamp(minZoom, maxZoom).toDouble();
    final image = screenToImage(focal);
    final newScale = baseScale * newZoom;
    final centered = Point(
      (canvasWidth - imageWidth * newScale) / 2,
      (canvasHeight - imageHeight * newScale) / 2,
    );
    return _with(
      newZoom,
      Point(
        focal.x - image.x * newScale - centered.x,
        focal.y - image.y * newScale - centered.y,
      ),
    );
  }

  Viewport panBy(Point<double> delta) =>
      _with(zoom, Point(pan.x + delta.x, pan.y + delta.y));

  Viewport _with(double zoom, Point<double> pan) => Viewport(
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    zoom: zoom,
    pan: pan,
  );

  static Point<double> _clampPan(
    Point<double> p,
    double cw,
    double ch,
    double iw,
    double ih,
    double scale,
  ) {
    final maxX = max(0.0, (iw * scale - cw) / 2);
    final maxY = max(0.0, (ih * scale - ch) / 2);
    return Point(
      p.x.clamp(-maxX, maxX).toDouble(),
      p.y.clamp(-maxY, maxY).toDouble(),
    );
  }
}
