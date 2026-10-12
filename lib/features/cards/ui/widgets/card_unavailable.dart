import 'package:flutter/material.dart';

import '../../../../core/theme/varna_colors.dart';
import 'tinted_card_scaffold.dart';
import 'ui_kit.dart';

/// Shown instead of an editor when the card cannot be loaded.
class CardUnavailable extends StatelessWidget {
  const CardUnavailable({super.key, this.error = false});

  /// True when loading failed (as opposed to the card being deleted).
  final bool error;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: RoundIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Back',
                      background: colors.surface,
                      onPressed: () => leaveScreen(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            error
                                ? Icons.error_outline
                                : Icons.delete_sweep_outlined,
                            size: 48,
                            color: colors.muted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            error
                                ? 'This card could not be opened'
                                : 'Card not found',
                            textAlign: TextAlign.center,
                            style: displayStyle(context, 24),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error
                                ? 'Something went wrong while loading it. '
                                    'Please go back and try again.'
                                : 'It may have been deleted on this phone or '
                                    'on another device.',
                            textAlign: TextAlign.center,
                            style: bodyStyle(
                              context,
                              15,
                              color: colors.muted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => leaveScreen(context),
                            child: const Text('Go back'),
                          ),
                        ],
                      ),
                    ),
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

/// Shown instead of an editor while the card's notebook is locked. It shows
/// nothing of the card.
class CardLocked extends StatelessWidget {
  const CardLocked({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: RoundIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Back',
                      background: colors.surface,
                      onPressed: () => leaveScreen(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 48,
                            color: colors.muted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Locked note',
                            textAlign: TextAlign.center,
                            style: displayStyle(context, 24),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This note is in a locked notebook. Unlock it '
                            'with your fingerprint, face or passcode.',
                            textAlign: TextAlign.center,
                            style: bodyStyle(
                              context,
                              15,
                              color: colors.muted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: onUnlock,
                            child: const Text('Unlock'),
                          ),
                        ],
                      ),
                    ),
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

/// A plain loading page for card screens.
class CardLoading extends StatelessWidget {
  const CardLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
