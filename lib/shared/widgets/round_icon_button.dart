import 'package:flutter/material.dart';

import '../../core/theme/varna_colors.dart';

/// A 44dp round icon button (white by default) with a required tooltip.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: background ?? c.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 22, color: foreground ?? c.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// The big round "+" button (64dp, ink).
class VarnaFab extends StatelessWidget {
  const VarnaFab({
    super.key,
    required this.onPressed,
    this.tooltip = 'New card',
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: c.ink,
          elevation: 8,
          shadowColor: c.ink.withValues(alpha: 0.5),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const SizedBox(
              width: 64,
              height: 64,
              child: Icon(Icons.add_rounded, size: 30, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
