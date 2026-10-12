import 'package:flutter/material.dart';

import '../../core/theme/varna_colors.dart';
import 'tokens.dart';

/// Small bold grey heading above a group ("Your cloud").
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 8),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: bodyStyle(context, 13, weight: FontWeight.w700, color: c.muted),
        ),
      ),
    );
  }
}
