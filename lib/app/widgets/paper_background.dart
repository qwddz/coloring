import 'package:flutter/widgets.dart';

import '../book_palette.dart';

/// Warm paper gradient behind a screen body.
class PaperBackground extends StatelessWidget {
  const PaperBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.6, -0.7),
          radius: 1.5,
          colors: [
            BookPalette.paperLight,
            BookPalette.paper,
            BookPalette.paperDark,
          ],
          stops: [0, 0.55, 1],
        ),
      ),
      child: SizedBox.expand(child: child),
    );
  }
}
