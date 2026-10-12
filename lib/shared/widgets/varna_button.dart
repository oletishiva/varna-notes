import 'package:flutter/material.dart';

import '../../core/theme/varna_colors.dart';
import '../../core/theme/varna_theme.dart';
import 'tokens.dart';

enum VarnaButtonKind { primary, secondary, text }

/// The app's button. Primary = ink background and white text (56 high),
/// secondary = 2px outline (52 high), text = link coloured (44 high).
class VarnaButton extends StatelessWidget {
  const VarnaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = VarnaButtonKind.primary,
    this.icon,
    this.busy = false,
    this.background,
    this.foreground,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final VarnaButtonKind kind;
  final IconData? icon;

  /// Shows a spinner and ignores taps.
  final bool busy;

  /// Overrides for the primary/secondary colours (for example a yellow button
  /// on the dark paywall).
  final Color? background;
  final Color? foreground;

  /// Fill the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final bool enabled = onPressed != null && !busy;

    final Color fg;
    switch (kind) {
      case VarnaButtonKind.primary:
        fg = foreground ?? Colors.white;
      case VarnaButtonKind.secondary:
        fg = foreground ?? c.ink;
      case VarnaButtonKind.text:
        fg = foreground ?? c.link;
    }
    final Color? bg = background ??
        (kind == VarnaButtonKind.primary ? c.ink : null);
    final double minHeight;
    final double fontSize;
    switch (kind) {
      case VarnaButtonKind.primary:
        minHeight = VarnaMetrics.primaryButtonHeight;
        fontSize = 17;
      case VarnaButtonKind.secondary:
        minHeight = 52;
        fontSize = 16;
      case VarnaButtonKind.text:
        minHeight = VarnaMetrics.minTouch;
        fontSize = 15;
    }
    final BorderSide side = kind == VarnaButtonKind.secondary
        ? BorderSide(color: foreground ?? c.ink, width: 2)
        : BorderSide.none;

    final Widget leading;
    if (busy) {
      leading = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: fg),
      );
    } else if (icon != null) {
      leading = Icon(icon, size: 20, color: fg);
    } else {
      leading = const SizedBox.shrink();
    }

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (busy || icon != null) ...<Widget>[
          leading,
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: bodyStyle(context, fontSize, weight: FontWeight.w700, color: fg),
          ),
        ),
      ],
    );

    Widget button = Material(
      color: bg ?? Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VarnaMetrics.buttonRadius),
        side: side,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: minHeight,
            minWidth: VarnaMetrics.minTouch,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Center(widthFactor: expand ? null : 1, child: content),
          ),
        ),
      ),
    );

    if (expand) {
      button = FractionallySizedBox(widthFactor: 1, child: button);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(opacity: onPressed == null ? 0.45 : 1, child: button),
    );
  }
}
