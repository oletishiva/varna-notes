import 'package:flutter/material.dart';

import '../../core/theme/varna_colors.dart';
import 'tokens.dart';
import 'varna_button.dart';

/// A friendly empty state: a soft illustration, one headline, one action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const EmptyIllustration(),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: displayStyle(context, 24, letterSpacing: -0.4),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: bodyStyle(context, 15, color: c.muted, height: 1.45),
            ),
          ],
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: 20),
            VarnaButton(
              label: actionLabel!,
              onPressed: onAction,
              expand: false,
            ),
          ],
        ],
      ),
    );
  }
}

/// Three tilted coloured rounded rectangles, like cards on a table.
class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    Widget block(double w, double h, Color color) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
          ),
        );
    Widget line(double w, Color color, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(h / 2),
          ),
        );
    return ExcludeSemantics(
      child: SizedBox(
        width: 176,
        height: 132,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 4,
              top: 22,
              child: Transform.rotate(
                angle: -0.19,
                child: block(104, 86, c.cardColor(1)),
              ),
            ),
            Positioned(
              right: 4,
              top: 12,
              child: Transform.rotate(
                angle: 0.16,
                child: block(100, 82, c.cardColor(2)),
              ),
            ),
            Positioned(
              left: 34,
              top: 30,
              child: Container(
                width: 108,
                height: 88,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.cardColor(0),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: c.ink.withValues(alpha: 0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    line(54, c.ink, 8),
                    const SizedBox(height: 10),
                    line(78, c.ink.withValues(alpha: 0.35), 5),
                    const SizedBox(height: 7),
                    line(64, c.ink.withValues(alpha: 0.35), 5),
                    const SizedBox(height: 7),
                    line(40, c.ink.withValues(alpha: 0.35), 5),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
