import 'package:flutter/material.dart';

import '../../core/theme/varna_colors.dart';
import '../../core/theme/varna_theme.dart';
import 'tokens.dart';

/// Shows a Varna bottom sheet (ground background, 28dp top corners, scrim in
/// ink, scrolls instead of overflowing, keyboard aware).
Future<T?> showVarnaSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  EdgeInsets padding = const EdgeInsets.fromLTRB(20, 0, 20, 24),
}) {
  final VarnaColors c = VarnaColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: c.ground,
    barrierColor: c.ink.withValues(alpha: 0.72),
    constraints: const BoxConstraints(maxWidth: VarnaExtras.maxContentWidth),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(VarnaMetrics.sheetRadius),
      ),
    ),
    builder: (BuildContext sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            padding: padding,
            child: builder(sheetContext),
          ),
        ),
      );
    },
  );
}

/// One tappable row inside a sheet (icon, label, optional subtitle).
class SheetAction extends StatelessWidget {
  const SheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final Color fg = destructive ? c.danger : c.ink;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 24, color: fg),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: bodyStyle(context, 16, weight: FontWeight.w600, color: fg),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: bodyStyle(context, 13, color: c.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Big heading used at the top of sheets.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: displayStyle(context, 26)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: bodyStyle(context, 14, color: c.muted)),
            ),
        ],
      ),
    );
  }
}
