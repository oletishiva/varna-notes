import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_config.dart';
import '../../../core/providers.dart';
import '../../../core/services/entitlements.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../shared/nav.dart';
import '../../../shared/widgets/centered_column.dart';
import '../../../shared/widgets/round_icon_button.dart';
import '../../../shared/widgets/tokens.dart';
import '../../../shared/widgets/varna_button.dart';

/// The Varna Plus paywall. Purchases are not connected in this build: the
/// start button explains that (and, in debug builds, can toggle Plus locally).
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final Entitlements entitlements = ref.read(entitlementsProvider);
    final bool isPlus = ref.read(isPlusProvider).valueOrNull ?? false;
    final bool canToggle = kDebugMode && entitlements.supportsDebugToggle;
    final bool? toggle = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final VarnaColors c = VarnaColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Purchases are not connected yet in this build',
            style: displayStyle(dialogContext, 20),
          ),
          content: Text(
            canToggle
                ? 'Nothing was charged. Because this is a debug build you can '
                    'switch Plus ${isPlus ? 'off' : 'on'} on this device to try '
                    'the Plus features.'
                : 'Nothing was charged. Your notes and sync keep working on '
                    'the free plan.',
            style: bodyStyle(dialogContext, 15),
          ),
          actions: <Widget>[
            if (canToggle)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(isPlus ? 'Turn Plus off (debug)' : 'Turn Plus on (debug)'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (toggle == true) {
      await entitlements.setDebugPlus(!isPlus);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VarnaColors c = VarnaColors.of(context);
    final bool isPlus = ref.watch(isPlusProvider).valueOrNull ?? false;
    final int perMonth = (AppConfig.plusPriceInr / 12).round();

    final List<_Perk> perks = <_Perk>[
      _Perk(
        color: c.cardColor(3),
        icon: Icons.notifications_none_rounded,
        title: 'Renewal reminders',
        text: 'Scan a policy or bill, get reminded before it expires',
      ),
      _Perk(
        color: c.cardColor(4),
        icon: Icons.mic_none_rounded,
        title: 'Voice to text in your language',
        text: 'Telugu, Hindi and English, searchable',
      ),
      _Perk(
        color: c.cardColor(0),
        icon: Icons.auto_awesome_outlined,
        title: 'Ask your notes',
        text: 'Answers from your own cards, with sources',
      ),
      _Perk(
        color: c.cardColor(2),
        icon: Icons.manage_search_rounded,
        title: 'Searchable scans',
        text: 'Find words inside photos and scanned papers',
      ),
    ];

    return Scaffold(
      backgroundColor: c.ink,
      body: SafeArea(
        child: CenteredColumn(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Row(
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    AppConfig.appName.toLowerCase(),
                                    style: displayStyle(
                                      context,
                                      20,
                                      letterSpacing: -0.3,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.cardColor(0),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Plus',
                                    style: displayStyle(context, 14, letterSpacing: 0),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          RoundIconButton(
                            icon: Icons.close_rounded,
                            tooltip: 'Close',
                            background: Colors.white.withValues(alpha: 0.14),
                            foreground: Colors.white,
                            onPressed: () => goBackOr(context, '/'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Notes that remember for you.',
                        style: displayStyle(
                          context,
                          34,
                          letterSpacing: -0.9,
                          color: Colors.white,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 22),
                      for (final _Perk perk in perks)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: perk,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Also in Plus: more than ${AppConfig.freeNotebookLimit} '
                        'notebooks and scans beyond ${AppConfig.freeScansPerMonth} a month.',
                        style: bodyStyle(
                          context,
                          14,
                          color: VarnaExtras.onDarkMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Spacer(),
                      Semantics(
                        selected: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: c.cardColor(0), width: 3),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.check_circle_rounded, color: c.ink, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      'Yearly, ${AppConfig.plusPrice}',
                                      style: bodyStyle(
                                        context,
                                        17,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'About ₹$perMonth a month, '
                                      '${AppConfig.trialDays} days free first',
                                      style: bodyStyle(context, 13, color: c.muted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: c.ink,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Best value',
                                  style: bodyStyle(
                                    context,
                                    12,
                                    weight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      VarnaButton(
                        label: isPlus
                            ? 'Plus is on for this device'
                            : 'Start ${AppConfig.trialDays} days free',
                        background: c.cardColor(0),
                        foreground: c.ink,
                        onPressed: () => _start(context, ref),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Then ${AppConfig.plusPrice}. Your notes and sync stay '
                        'free if you cancel.',
                        textAlign: TextAlign.center,
                        style: bodyStyle(
                          context,
                          13,
                          color: VarnaExtras.onDarkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({
    required this.color,
    required this.icon,
    required this.title,
    required this.text,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(icon, size: 24, color: VarnaColors.of(context).ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: bodyStyle(context, 16, weight: FontWeight.w700)),
                Text(text, style: bodyStyle(context, 14, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
