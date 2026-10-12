import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_config.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../shared/widgets/centered_column.dart';
import '../../../shared/widgets/tokens.dart';
import '../../../shared/widgets/varna_button.dart';

/// First screen: the promise, plus "Get started".
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: CenteredColumn(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        AppConfig.appName.toLowerCase(),
                        style: displayStyle(context, 22, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 28),
                      const Center(child: _WelcomeArt()),
                      const SizedBox(height: 24),
                      Text(
                        'Every thought gets its own card.',
                        style: displayStyle(
                          context,
                          38,
                          letterSpacing: -1,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Text, checklists, voice, photos and scans, kept in '
                        'notebooks and backed up to your own cloud.',
                        style: bodyStyle(context, 17, color: c.muted, height: 1.45),
                      ),
                      const Spacer(),
                      const SizedBox(height: 24),
                      VarnaButton(
                        label: 'Get started',
                        onPressed: () => context.go('/sync-setup'),
                      ),
                      const SizedBox(height: 4),
                      VarnaButton(
                        label: 'Restore from a backup',
                        kind: VarnaButtonKind.text,
                        onPressed: () => context.go('/sync-setup'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No ${AppConfig.appName} account. Your notes stay in '
                        'your Google Drive or iCloud.',
                        textAlign: TextAlign.center,
                        style: bodyStyle(context, 13, color: c.muted),
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

/// Three tilted cards and a voice bubble. Drawn at 340x330 and scaled down
/// on narrow screens.
class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    Widget line(double w, double h, Color color) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(h / 2),
          ),
        );
    Widget bar(double h) => Container(
          width: 4,
          height: h,
          decoration: BoxDecoration(
            color: c.ink,
            borderRadius: BorderRadius.circular(2),
          ),
        );
    return ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 340,
          height: 330,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: 14,
                top: 46,
                child: Transform.rotate(
                  angle: -11 * 3.1415926535 / 180,
                  child: Container(
                    width: 190,
                    height: 230,
                    decoration: BoxDecoration(
                      color: c.cardColor(1),
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 150,
                top: 30,
                child: Transform.rotate(
                  angle: 9 * 3.1415926535 / 180,
                  child: Container(
                    width: 180,
                    height: 220,
                    decoration: BoxDecoration(
                      color: c.cardColor(2),
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 70,
                top: 60,
                child: Container(
                  width: 200,
                  height: 250,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
                  decoration: BoxDecoration(
                    color: c.cardColor(0),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: c.ink.withValues(alpha: 0.18),
                        blurRadius: 40,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      line(110, 14, c.ink),
                      const SizedBox(height: 14),
                      line(150, 8, c.ink.withValues(alpha: 0.35)),
                      const SizedBox(height: 14),
                      line(130, 8, c.ink.withValues(alpha: 0.35)),
                      const SizedBox(height: 14),
                      line(150, 8, c.ink.withValues(alpha: 0.35)),
                      const SizedBox(height: 14),
                      line(90, 8, c.ink.withValues(alpha: 0.35)),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 236,
                top: 232,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: c.cardColor(4),
                    shape: BoxShape.circle,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      bar(16),
                      const SizedBox(width: 4),
                      bar(30),
                      const SizedBox(width: 4),
                      bar(22),
                      const SizedBox(width: 4),
                      bar(12),
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
