import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'render/raster_engine.dart';

/// The strokes on screen that are not in the committed image yet (spec
/// §6.2): the one being drawn and those still waiting for their commit.
/// The canvas paints them over the committed image and repaints on every
/// notification. Owns the layers and disposes each when it is removed.
class LiveStroke extends ChangeNotifier {
  final List<LiveStrokeLayer> _layers = [];
  bool _disposed = false;

  bool get isEmpty => _layers.isEmpty;

  /// Shows [layer] on top of the others.
  void add(LiveStrokeLayer layer) {
    if (_disposed) {
      layer.dispose();
      return;
    }
    _layers.add(layer);
    notifyListeners();
  }

  /// A shown layer got new dabs.
  void changed() {
    if (!_disposed) notifyListeners();
  }

  /// Hides and disposes [layer].
  void remove(LiveStrokeLayer layer) {
    layer.dispose();
    if (_layers.remove(layer) && !_disposed) notifyListeners();
  }

  /// Draws every layer, oldest first, in canvas pixels.
  void paint(ui.Canvas canvas) {
    for (final layer in _layers) {
      layer.paint(canvas);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final layer in _layers) {
      layer.dispose();
    }
    _layers.clear();
    super.dispose();
  }
}
