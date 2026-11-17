import 'package:flutter/material.dart';

import 'book_palette.dart';

const String _fontFamily = 'Nunito';

/// Sets both fontWeight and the variable font's wght axis: the axis pins the
/// actual weight, so copyWith(fontWeight:) alone would not change the glyphs.
TextStyle? _weighted(TextStyle? style, FontWeight weight) {
  if (style == null) return null;
  return style.copyWith(
    fontFamily: _fontFamily,
    fontWeight: weight,
    // Nunito is bundled as one variable font; the axis picks the weight.
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
  );
}

TextTheme _buildTextTheme() {
  final base = Typography.material2021().black.apply(
    fontFamily: _fontFamily,
    bodyColor: BookPalette.text,
    displayColor: BookPalette.text,
  );
  const heading = FontWeight.w800;
  const body = FontWeight.w700;
  return TextTheme(
    displayLarge: _weighted(base.displayLarge, heading),
    displayMedium: _weighted(base.displayMedium, heading),
    displaySmall: _weighted(base.displaySmall, heading),
    headlineLarge: _weighted(base.headlineLarge, heading),
    headlineMedium: _weighted(base.headlineMedium, heading),
    headlineSmall: _weighted(base.headlineSmall, heading),
    titleLarge: _weighted(base.titleLarge, heading),
    titleMedium: _weighted(base.titleMedium, heading),
    titleSmall: _weighted(base.titleSmall, body),
    bodyLarge: _weighted(base.bodyLarge, body),
    bodyMedium: _weighted(base.bodyMedium, body),
    bodySmall: _weighted(base.bodySmall, body),
    labelLarge: _weighted(base.labelLarge, heading),
    labelMedium: _weighted(base.labelMedium, body),
    labelSmall: _weighted(base.labelSmall, body),
  );
}

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(12),
  borderSide: BorderSide(color: color, width: 2),
);

ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: BookPalette.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: BookPalette.primary,
        onPrimary: Colors.white,
        secondary: BookPalette.primaryStep,
        surface: BookPalette.card,
        onSurface: BookPalette.text,
        onSurfaceVariant: BookPalette.textMuted,
        outline: BookPalette.outline,
        shadow: BookPalette.shadow,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    textTheme: _buildTextTheme(),
    scaffoldBackgroundColor: BookPalette.paper,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BookPalette.paperLight,
      labelStyle: const TextStyle(color: BookPalette.textMuted),
      border: _inputBorder(BookPalette.outline),
      enabledBorder: _inputBorder(BookPalette.outline),
      focusedBorder: _inputBorder(BookPalette.primary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: BookPalette.text,
      contentTextStyle: _weighted(
        const TextStyle(fontSize: 14, color: BookPalette.card),
        FontWeight.w700,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.white
            : BookPalette.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? BookPalette.primary
            : BookPalette.secondaryStep,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.transparent
            : BookPalette.textMuted,
      ),
    ),
  );
}
