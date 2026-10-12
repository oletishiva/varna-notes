import 'package:flutter/material.dart';

import 'tokens.dart';

/// Centres [child] in a column no wider than [maxWidth] (phones fill the
/// width; tablets and the web get a centred column).
class CenteredColumn extends StatelessWidget {
  const CenteredColumn({
    super.key,
    required this.child,
    this.maxWidth = VarnaExtras.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
