import 'package:flutter/material.dart';

import '../../core/theme/varna_colors.dart';

/// A card the user can select (replaces radio buttons): white or coloured
/// surface, 2px ink outline when selected.
class SelectableCard extends StatelessWidget {
  const SelectableCard({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.color,
    this.radius = 18,
    this.padding = const EdgeInsets.all(16),
    this.semanticLabel,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final Color? color;
  final double radius;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      label: semanticLabel,
      child: Material(
        color: color ?? c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
            color: selected ? c.ink : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// The round tick/empty circle shown at the end of a [SelectableCard].
class SelectionMark extends StatelessWidget {
  const SelectionMark({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return ExcludeSemantics(
      child: Icon(
        selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
        size: 24,
        color: selected ? c.ink : c.muted,
      ),
    );
  }
}
