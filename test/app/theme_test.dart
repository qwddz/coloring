import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/app/book_palette.dart';
import 'package:coloring/app/theme.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('theme uses Nunito and the book palette', () {
    final theme = buildAppTheme();
    expect(theme.textTheme.bodyMedium!.fontFamily, 'Nunito');
    expect(theme.colorScheme.primary, BookPalette.primary);
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, BookPalette.paper);
    for (final (style, weight) in [
      (theme.textTheme.titleLarge!, 800),
      (theme.textTheme.headlineMedium!, 800),
      (theme.textTheme.bodyMedium!, 700),
    ]) {
      expect(style.fontWeight!.value, weight);
      expect(style.fontVariations, [FontVariation('wght', weight.toDouble())]);
    }
    expect(
      contrast(BookPalette.textMuted, BookPalette.card),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(BookPalette.text, BookPalette.paperDark),
      greaterThanOrEqualTo(7),
    );
  });

  test('inputs and snackbars use the paper style', () {
    final theme = buildAppTheme();
    final input = theme.inputDecorationTheme;
    expect(input.filled, isTrue);
    expect(input.fillColor, BookPalette.paperLight);
    expect(input.labelStyle!.color, BookPalette.textMuted);
    final enabled = input.enabledBorder! as OutlineInputBorder;
    expect(enabled.borderRadius, BorderRadius.circular(12));
    expect(enabled.borderSide.color, BookPalette.outline);
    expect(enabled.borderSide.width, 2);
    expect(
      (input.focusedBorder! as OutlineInputBorder).borderSide.color,
      BookPalette.primary,
    );
    final snack = theme.snackBarTheme;
    expect(snack.backgroundColor, BookPalette.text);
    expect(snack.behavior, SnackBarBehavior.floating);
    expect(snack.contentTextStyle!.color, BookPalette.card);
    expect(snack.contentTextStyle!.fontFamily, 'Nunito');
    expect(snack.contentTextStyle!.fontWeight, FontWeight.w700);
  });
}
