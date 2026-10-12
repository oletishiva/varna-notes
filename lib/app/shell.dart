import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/varna_colors.dart';
import '../features/cards/ui/new_card_sheet.dart';
import '../shared/widgets/round_icon_button.dart';
import '../shared/widgets/tokens.dart';

/// Wraps the four tab screens with the bottom bar: Notebooks, Papers, the
/// centre "+" button, Reminders and Settings.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  /// Current path, used to highlight the active tab.
  final String location;
  final Widget child;

  int get _index {
    if (location.startsWith('/papers')) {
      return 1;
    }
    if (location.startsWith('/reminders')) {
      return 2;
    }
    if (location.startsWith('/settings')) {
      return 3;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VarnaColors c = VarnaColors.of(context);
    final int index = _index;
    return Scaffold(
      body: child,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: VarnaFab(
        onPressed: () => unawaited(startNewCardFlow(context, ref)),
      ),
      bottomNavigationBar: Material(
        color: c.surface,
        elevation: 0,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: VarnaExtras.maxContentWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _NavItem(
                        label: 'Notebooks',
                        icon: Icons.menu_book_outlined,
                        activeIcon: Icons.menu_book_rounded,
                        selected: index == 0,
                        onTap: () => context.go('/'),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        label: 'Papers',
                        icon: Icons.description_outlined,
                        activeIcon: Icons.description_rounded,
                        selected: index == 1,
                        onTap: () => context.go('/papers'),
                      ),
                    ),
                    const SizedBox(width: 72),
                    Expanded(
                      child: _NavItem(
                        label: 'Reminders',
                        icon: Icons.notifications_none_rounded,
                        activeIcon: Icons.notifications_rounded,
                        selected: index == 2,
                        onTap: () => context.go('/reminders'),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        label: 'Settings',
                        icon: Icons.settings_outlined,
                        activeIcon: Icons.settings_rounded,
                        selected: index == 3,
                        onTap: () => context.go('/settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final Color fg = selected ? c.ink : c.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(selected ? activeIcon : icon, size: 22, color: fg),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: bodyStyle(
                        context,
                        12,
                        weight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: fg,
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
