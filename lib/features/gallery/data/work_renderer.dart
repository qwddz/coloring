import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../coloring/model/region_map.dart';
import '../model/fill_pixels.dart';

/// A work drawn as a PNG of [width] × [height]: the fills from [map] and
/// [colors] (see [composeFillPixels]), then [lines] scaled over them. Runs
/// on the calling isolate without a shader. Every image made here is
/// disposed before returning; [lines] stays the caller's.
Future<Uint8List> renderWorkPng({
  required RegionMap map,
  required Uint32List colors,
  required ui.Image lines,
  required int width,
  required int height,
}) async {
  final fills = await _imageFromPixels(
    composeFillPixels(map: map, colors: colors, width: width, height: height),
    width,
    height,
  );
  ui.Image? rendered;
  try {
    final target = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..drawImage(fills, ui.Offset.zero, ui.Paint())
      ..drawImageRect(
        lines,
        ui.Rect.fromLTWH(0, 0, lines.width.toDouble(), lines.height.toDouble()),
        target,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    final picture = recorder.endRecording();
    try {
      rendered = await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG encoding failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    fills.dispose();
    rendered?.dispose();
  }
}

Future<ui.Image> _imageFromPixels(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
