import 'package:flutter/material.dart';

import '../../../../core/theme/varna_colors.dart';

/// Content is centred in a column of at most this width on wide screens.
const double kContentMaxWidth = 560;

/// Display (Bricolage Grotesque) text style at [size], with the tight tracking
/// used by the design. Built from the theme so the Telugu fallback applies.
TextStyle displayStyle(BuildContext context, double size) {
  final TextStyle base =
      Theme.of(context).textTheme.titleLarge ?? const TextStyle();
  return base.copyWith(
    fontSize: size,
    letterSpacing: -size * 0.025,
    height: 1.1,
  );
}

/// Body (Figtree) text style at [size].
TextStyle bodyStyle(
  BuildContext context,
  double size, {
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
}) {
  final TextStyle base =
      Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
  return base.copyWith(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );
}

/// The translucent white used for buttons and boxes on tinted backgrounds.
Color frostedWhite([double alpha = 0.6]) =>
    Colors.white.withValues(alpha: alpha);

/// A rounded "pill" toggle used for filters and folder choices: ink when
/// selected, white otherwise. At least 44dp high.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.ink : colors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      label,
                      style: bodyStyle(
                        context,
                        14,
                        weight: FontWeight.w600,
                        color: selected ? Colors.white : colors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round icon button with a tooltip (which doubles as its accessibility
/// label). 44dp by default.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 22,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize),
      style: IconButton.styleFrom(
        backgroundColor: background ?? frostedWhite(),
        foregroundColor: foreground ?? colors.ink,
        disabledBackgroundColor:
            (background ?? frostedWhite()).withValues(alpha: 0.3),
        fixedSize: Size(size, size),
        minimumSize: Size(size, size),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
    );
  }
}
