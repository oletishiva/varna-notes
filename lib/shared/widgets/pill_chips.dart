import 'package:flutter/material.dart';

import '../../core/theme/varna_colors.dart';
import '../../core/theme/varna_theme.dart';
import 'tokens.dart';

class PillOption<T> {
  const PillOption(this.value, this.label);

  final T value;
  final String label;
}

/// A wrapping row of single-select pills.
class PillChips<T> extends StatelessWidget {
  const PillChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<PillOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final PillOption<T> option in options)
          Semantics(
            button: true,
            selected: option.value == selected,
            child: Material(
              color: option.value == selected ? c.ink : c.surface,
              borderRadius: BorderRadius.circular(VarnaMetrics.pillRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelected(option.value),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: VarnaMetrics.minTouch),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          option.label,
                          style: bodyStyle(
                            context,
                            14,
                            weight: FontWeight.w600,
                            color: option.value == selected ? Colors.white : c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
