import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps Android's edge swipe "back" gesture off [child]: a stroke that
/// starts at the canvas edge draws instead of closing the screen. The
/// screens using it are in immersive sticky mode, where Android honors the
/// whole height (no 200 dp limit). Other platforms and Android < 10 ignore
/// it.
class BackGestureExclusion extends SingleChildRenderObjectWidget {
  const BackGestureExclusion({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBackGestureExclusion();
}

class _RenderBackGestureExclusion extends RenderProxyBox {
  Rect? _rect;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final rect = localToGlobal(Offset.zero) & size;
    if (rect != _rect) {
      _rect = rect;
      _GestureExclusions.set(this, rect);
    }
  }

  @override
  void detach() {
    _rect = null;
    _GestureExclusions.remove(this);
    super.detach();
  }
}

/// All excluded rects, sent to `MainActivity` at most once per frame.
abstract final class _GestureExclusions {
  static const _channel = MethodChannel('app.animosaic.coloring/gestures');
  static final _rects = <Object, Rect>{};
  static var _scheduled = false;

  static void set(Object owner, Rect rect) {
    _rects[owner] = rect;
    _schedule();
  }

  static void remove(Object owner) {
    if (_rects.remove(owner) != null) _schedule();
  }

  static void _schedule() {
    if (_scheduled || defaultTargetPlatform != TargetPlatform.android) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        _channel
            .invokeMethod<void>('setExclusionRects', [
              for (final r in _rects.values) [r.left, r.top, r.right, r.bottom],
            ])
            .catchError((Object _) {}); // no handler in tests
      })
      ..ensureVisualUpdate();
  }
}
