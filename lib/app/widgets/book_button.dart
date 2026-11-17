import 'package:flutter/material.dart';

import '../book_palette.dart';

enum BookButtonKind { primary, secondary, text }

/// Pill button with an offset "step" shadow that shrinks while pressed.
class BookButton extends StatefulWidget {
  const BookButton({
    required this.label,
    required this.onPressed,
    this.kind = BookButtonKind.primary,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final BookButtonKind kind;
  final IconData? icon;

  @override
  State<BookButton> createState() => _BookButtonState();
}

class _BookButtonState extends State<BookButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final kind = widget.kind;
    final (face, step, fg) = switch (kind) {
      BookButtonKind.primary => (
        BookPalette.primary,
        BookPalette.primaryStep,
        Colors.white,
      ),
      BookButtonKind.secondary => (
        BookPalette.card,
        BookPalette.secondaryStep,
        BookPalette.text,
      ),
      BookButtonKind.text => (
        Colors.transparent,
        Colors.transparent,
        BookPalette.link,
      ),
    };
    final hasStep = kind != BookButtonKind.text;
    const stepHeight = 4.0;
    final depth = hasStep ? (_pressed ? 1.0 : stepHeight) : 0.0;
    // The face rests on its step and sinks when pressed. A text button has
    // no step but keeps its face where a resting step button's face is, so
    // labels of all kinds line up in a row.
    final sink = hasStep ? stepHeight - depth : 0.0;
    final style = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: fg, fontSize: 18);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onTap: widget.onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: EdgeInsets.only(top: sink, bottom: stepHeight - sink),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: face,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: hasStep
                      ? [BoxShadow(color: step, offset: Offset(0, depth))]
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: fg, size: 22),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          widget.label,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
