import 'package:flutter/material.dart';

import '../../core/theme/varna_colors.dart';
import 'tokens.dart';

/// White rounded group of rows separated by hairlines.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A row inside a [SettingsGroup].
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.chevron = false,
    this.subtitleColor,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool chevron;
  final Color? subtitleColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: bodyStyle(
                          context,
                          16,
                          weight: FontWeight.w600,
                          color: titleColor ?? c.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: bodyStyle(
                            context,
                            13,
                            color: subtitleColor ?? c.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: 8),
                  trailing!,
                ],
                if (chevron) ...<Widget>[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 22, color: c.muted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A [SettingsRow] with a switch. Pass `onChanged: null` to disable.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ValueChanged<bool>? handler = onChanged;
    return MergeSemantics(
      child: SettingsRow(
        title: title,
        subtitle: subtitle,
        enabled: handler != null,
        onTap: handler == null ? null : () => handler(!value),
        trailing: Switch(value: value, onChanged: handler),
      ),
    );
  }
}

/// A small coloured square holding an icon (cloud logos, section icons).
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: size * 0.55, color: c.ink),
      ),
    );
  }
}
