import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/book_button.dart';
import '../../app/widgets/passe_partout.dart';
import '../../l10n/app_localizations.dart';

/// Shown over the finished picture: confetti, a popping star, a title and
/// two buttons. Input below it is blocked. Sound and haptics are triggered
/// by the controller, not here.
class CompletionOverlay extends StatelessWidget {
  const CompletionOverlay({
    super.key,
    required this.onKeepColoring,
    required this.onBack,
  });

  final VoidCallback onKeepColoring;
  final VoidCallback onBack;

  /// Screens lower than this get a smaller star and padding.
  static const double shortScreen = 500;

  Widget _card(BuildContext context, {required bool short}) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return PassePartout(
      child: ColoredBox(
        color: BookPalette.card,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: short ? 20 : 32,
            vertical: short ? 4 : 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 900),
                curve: Curves.elasticOut,
                builder: (context, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: Icon(
                  Icons.star_rounded,
                  size: short ? 40 : 88,
                  color: BookPalette.star,
                ),
              ),
              SizedBox(height: short ? 0 : 8),
              Text(
                l10n.coloringCompleteTitle,
                textAlign: TextAlign.center,
                style: short
                    ? textTheme.headlineSmall
                    : textTheme.headlineMedium,
              ),
              SizedBox(height: short ? 4 : 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    BookButton(
                      kind: BookButtonKind.secondary,
                      onPressed: onKeepColoring,
                      label: l10n.coloringKeepColoring,
                    ),
                    BookButton(
                      onPressed: onBack,
                      label: l10n.coloringBackToPictures,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blocks taps on the picture underneath.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: ColoredBox(color: BookPalette.scrim.withValues(alpha: .2)),
        ),
        LayoutBuilder(
          builder: (context, constraints) => Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: IntrinsicWidth(
                  child: _card(
                    context,
                    short: constraints.maxHeight < shortScreen,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!MediaQuery.disableAnimationsOf(context))
          const IgnorePointer(child: _Confetti()),
      ],
    );
  }
}

/// Paper pieces that fall and flutter over the screen once.
class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  )..forward();
  final _pieces = ConfettiPiece.burst(math.Random(), 90);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: ConfettiPainter(_controller, _pieces),
      size: Size.infinite,
    ),
  );
}

class ConfettiPiece {
  ConfettiPiece(math.Random random)
    : x = random.nextDouble(),
      delay = random.nextDouble() * 0.35,
      fall = 0.9 + random.nextDouble() * 0.4,
      sway = 8 + random.nextDouble() * 24,
      swaySpeed = 1 + random.nextDouble() * 2,
      phase = random.nextDouble() * 2 * math.pi,
      spin = (random.nextDouble() - 0.5) * 6 * math.pi,
      flip = 2 + random.nextDouble() * 4,
      width = 6 + random.nextDouble() * 6,
      color = BookPalette.confetti[random.nextInt(BookPalette.confetti.length)];

  static List<ConfettiPiece> burst(math.Random random, int count) => [
    for (var i = 0; i < count; i++) ConfettiPiece(random),
  ];

  /// Horizontal start as a share of the width.
  final double x;

  /// Share of the animation before this piece starts falling.
  final double delay;

  /// How far it falls, in screen heights, over its time.
  final double fall;
  final double sway;
  final double swaySpeed;
  final double phase;
  final double spin;
  final double flip;
  final double width;
  final Color color;
}

/// Draws the falling paper pieces; public so tests can check its colours.
@visibleForTesting
class ConfettiPainter extends CustomPainter {
  ConfettiPainter(this.animation, this.pieces) : super(repaint: animation);

  final Animation<double> animation;
  final List<ConfettiPiece> pieces;

  /// Colours of the pieces.
  Set<Color> get colors => {for (final p in pieces) p.color};

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final paint = Paint();
    for (final piece in pieces) {
      final p = ((t - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (p == 0) continue;
      final opacity = p > 0.8 ? (1 - p) / 0.2 : 1.0;
      paint.color = piece.color.withValues(alpha: opacity);
      final dx =
          piece.x * size.width +
          math.sin(p * piece.swaySpeed * 2 * math.pi + piece.phase) *
              piece.sway;
      final dy = -20 + p * piece.fall * (size.height + 40);
      // Squashing the height by a cosine makes the piece seem to turn over.
      final height =
          piece.width * 0.6 * math.cos(p * piece.flip * 2 * math.pi).abs() + 1;
      canvas
        ..save()
        ..translate(dx, dy)
        ..rotate(p * piece.spin + piece.phase)
        ..drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: piece.width,
            height: height,
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter oldDelegate) =>
      oldDelegate.pieces != pieces;
}
