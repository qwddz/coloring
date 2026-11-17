import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../book_palette.dart';

/// Card-coloured frame around a picture, with a warm shadow, an optional
/// caption and a slight decorative tilt that never moves the layout box.
class PassePartout extends StatefulWidget {
  const PassePartout({
    required this.child,
    this.tiltDegrees = 0,
    this.caption,
    this.onTap,
    super.key,
  });

  final Widget child;
  final double tiltDegrees;
  final Widget? caption;
  final VoidCallback? onTap;

  @override
  State<PassePartout> createState() => _PassePartoutState();
}

class _PassePartoutState extends State<PassePartout> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context);
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: BookPalette.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: BookPalette.shadow,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: widget.child,
            ),
            if (widget.caption != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                child: widget.caption,
              ),
          ],
        ),
      ),
    );
    if (animate) {
      card = AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 100),
        child: card,
      );
    }
    if (widget.tiltDegrees != 0) {
      card = Transform.rotate(
        angle: widget.tiltDegrees * math.pi / 180,
        child: card,
      );
    }
    if (widget.onTap == null) return card;
    return Semantics(
      button: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: card,
      ),
    );
  }
}
