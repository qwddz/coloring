import 'package:flutter/services.dart';

/// Immersive sticky full screen while at least one screen holds it. The
/// coloring and drawing screens can both be on the stack, so the system
/// bars come back only when the last of them leaves.
abstract final class ImmersiveMode {
  static var _holders = 0;

  /// Call from `initState`.
  static void enter() {
    _holders++;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Call from `dispose`, once per [enter].
  static void leave() {
    if (--_holders == 0) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}
