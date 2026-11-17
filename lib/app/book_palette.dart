import 'package:flutter/painting.dart';

/// Colours of the «Бумага и акварель» style.
abstract final class BookPalette {
  // Paper gradient, light to dark.
  static const Color paperLight = Color(0xFFFFF8EA);
  static const Color paper = Color(0xFFF6EAD3);
  static const Color paperDark = Color(0xFFEFDCC0);

  /// Passe-partout / card surface.
  static const Color card = Color(0xFFFFFDF8);

  static const Color text = Color(0xFF4A3628);
  static const Color textMuted = Color(0xFF7A6250);

  /// Primary button and its lower "step".
  static const Color primary = Color(0xFFE07B52);
  static const Color primaryStep = Color(0xFFB65A37);

  /// Secondary button step (its face is [card]).
  static const Color secondaryStep = Color(0xFFE2CFAE);

  /// Text buttons.
  static const Color link = Color(0xFFB65A37);

  static const Color star = Color(0xFFE2A33B);

  /// Field outlines and dividers.
  static const Color outline = Color(0xFFECDCC2);

  /// Warm shadow, about rgba(120, 80, 40, .18).
  static const Color shadow = Color(0x2E785028);

  /// Dark warm tone for modal scrims; use with an alpha.
  static const Color scrim = Color(0xFF402A18);

  static const List<Color> confetti = [
    primary,
    star,
    Color(0xFF8DB8D8), // soft blue
    Color(0xFF8FBF8A), // green
    Color(0xFFE6A0B4), // pink
    Color(0xFFB59AD0), // lavender
  ];
}
