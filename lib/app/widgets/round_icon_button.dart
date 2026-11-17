import 'package:flutter/material.dart';

import '../book_palette.dart';

/// 48 dp light circle with a step shadow and an icon.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: BookPalette.card,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: BookPalette.secondaryStep,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: BookPalette.text),
            ),
          ),
        ),
      ),
    );
  }
}
