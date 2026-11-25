/// The 36 colors of the drawing screen, as opaque ARGB values: brighter and
/// more contrasting than the coloring `basePalette`, with black. Any two
/// differ by more than the flood fill tolerance.
const List<int> drawingPalette = [
  // Black, greys, white.
  0xFF000000, 0xFF555555, 0xFFA6A6A6, 0xFFFFFFFF,
  // Reds.
  0xFFFF6B6B, 0xFFE8222E, 0xFFA3111A,
  // Pinks and magenta.
  0xFFFF8FCB, 0xFFF0288C, 0xFFD42BD4, 0xFFA6125E,
  // Oranges.
  0xFFFFA552, 0xFFFF6F00, 0xFFC24A0A,
  // Yellows.
  0xFFFFF06A, 0xFFFFD000, 0xFFF0A500,
  // Greens.
  0xFFC4EB3B, 0xFF6CD44A, 0xFF1FA33A, 0xFF0D6328, 0xFF8C9A20,
  // Teals.
  0xFF4BE3C8, 0xFF00A896, 0xFF00655C,
  // Blues.
  0xFF7FD3FF, 0xFF1EA0F0, 0xFF2456D6, 0xFF14277A,
  // Purples.
  0xFFC9A0FF, 0xFF8A3DF0, 0xFF55179E,
  // Skin tones and browns.
  0xFFFFD3B0, 0xFFC47A3C, 0xFF8B5124, 0xFF4E2A10,
];
