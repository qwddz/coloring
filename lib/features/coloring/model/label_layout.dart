import 'dart:math' as math;

/// Smallest on-screen radius (dp) at which a region number is drawn.
const double labelMinVisibleRadiusDp = 10;

const double _labelMinFontDp = 10;
const double _labelMaxFontDp = 28;
const double _toleranceDp = 6;
const double _toleranceMinImagePx = 4;
const double _toleranceMaxImagePx = 16;

double _onScreenRadiusDp(double radiusImagePx, double imagePxPerDp) =>
    radiusImagePx / imagePxPerDp;

/// A number is shown when its region is at least [labelMinVisibleRadiusDp]
/// (10 dp) in radius on screen.
bool labelVisible(double radiusImagePx, double imagePxPerDp) =>
    _onScreenRadiusDp(radiusImagePx, imagePxPerDp) >= labelMinVisibleRadiusDp;

/// Label font size in dp: `clamp(onScreenRadius * 0.9, 10, 28)`.
double labelFontSize(double radiusImagePx, double imagePxPerDp) => math
    .max(
      _labelMinFontDp,
      math.min(
        _labelMaxFontDp,
        _onScreenRadiusDp(radiusImagePx, imagePxPerDp) * 0.9,
      ),
    )
    .toDouble();

/// Tap tolerance for region lookup near lines, in image px:
/// `clamp(6 dp * imagePxPerDp, 4, 16)`, rounded to a whole pixel.
int lineTolerance(double imagePxPerDp) => math
    .max(
      _toleranceMinImagePx,
      math.min(_toleranceMaxImagePx, _toleranceDp * imagePxPerDp),
    )
    .round();
