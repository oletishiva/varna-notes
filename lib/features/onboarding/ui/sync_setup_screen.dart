import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/varna_colors.dart';
import '../../sync/data/sync_controller.dart';
import '../../sync/logic/sync_status.dart';
import '../../../shared/nav.dart';
import '../../../shared/widgets/centered_column.dart';
import '../../../shared/widgets/selectable_card.dart';
import '../../../shared/widgets/settings_group.dart';
import '../../../shared/widgets/tokens.dart';
import '../../../shared/widgets/varna_button.dart';

/// "Where should your notes live?": Google Drive, iCloud (where available) or
/// this device only.
class SyncSetupScreen extends ConsumerStatefulWidget {
  const SyncSetupScreen({super.key});

  @override
  ConsumerState<SyncSetupScreen> createState() => _SyncSetupScreenState();
}

class _SyncSetupScreenState extends ConsumerState<SyncSetupScreen> {
  /// Null means "this device only".
  SyncProviderId? _selected = SyncProviderId.googleDrive;
  bool _busy = false;

  String get _buttonLabel {
    switch (_selected) {
      case SyncProviderId.googleDrive:
        return 'Continue with Google';
      case SyncProviderId.icloud:
        return 'Continue with iCloud';
      case null:
        return 'Continue';
    }
  }

  String get _footnote {
    switch (_selected) {
      case SyncProviderId.googleDrive:
        return 'Varna asks only for its own folder. It cannot see your other '
            'Drive files.';
      case SyncProviderId.icloud:
        return 'Varna keeps its backup in its own iCloud folder.';
      case null:
        return 'Your notes stay on this device. You can turn on backup any '
            'time from Settings.';
    }
  }

  String _failureMessage(SyncReport report) {
    if (report.errors.isNotEmpty) {
      return report.errors.first.message;
    }
    if (report.offline) {
      return 'You appear to be offline. Check your connection and try again.';
    }
    return 'Could not connect. Please try again.';
  }

  Future<void> _continue() async {
    if (_busy) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final GoRouter router = GoRouter.of(context);
    final SyncController controller = ref.read(syncControllerProvider);
    final SyncProviderId? provider = _selected;
    setState(() => _busy = true);
    try {
      if (provider != null) {
        final SyncReport report = await controller.connect(provider);
        if (report.aborted || report.offline) {
          messenger.showSnackBar(SnackBar(content: Text(_failureMessage(report))));
          if (mounted) {
            setState(() => _busy = false);
          }
          return;
        }
      }
      await ref.read(settingsRepositoryProvider).setOnboardingDone(true);
      router.go('/');
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final SyncController controller = ref.watch(syncControllerProvider);
    final bool icloudSupported = controller.isProviderSupported(SyncProviderId.icloud);
    final AppSettings? settings = ref.watch(settingsProvider).valueOrNull;
    final bool wifiOnly = settings?.wifiOnly ?? false;

    Widget option({
      required SyncProviderId? value,
      required IconData icon,
      required Color color,
      required String title,
      required String text,
    }) {
      final bool selected = _selected == value;
      return SelectableCard(
        selected: selected,
        onTap: _busy ? null : () => setState(() => _selected = value),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IconTile(icon: icon, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: bodyStyle(context, 17, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(text, style: bodyStyle(context, 14, color: c.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectionMark(selected: selected),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: CenteredColumn(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Step 1 of 1',
                              style: bodyStyle(
                                context,
                                14,
                                weight: FontWeight.w600,
                                color: c.muted,
                              ),
                            ),
                          ),
                          if (context.canPop())
                            VarnaButton(
                              label: 'Back',
                              kind: VarnaButtonKind.text,
                              expand: false,
                              onPressed: () => goBackOr(context, '/welcome'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Where should your notes live?',
                        style: displayStyle(
                          context,
                          32,
                          letterSpacing: -0.8,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Pick one. You can switch later without losing a card.',
                        style: bodyStyle(context, 16, color: c.muted, height: 1.45),
                      ),
                      const SizedBox(height: 26),
                      option(
                        value: SyncProviderId.googleDrive,
                        icon: Icons.add_to_drive_outlined,
                        color: c.cardColor(1),
                        title: 'Google Drive',
                        text: 'Works on Android and iPhone. Kept in a private '
                            'app folder only Varna can read.',
                      ),
                      if (icloudSupported) ...<Widget>[
                        const SizedBox(height: 12),
                        option(
                          value: SyncProviderId.icloud,
                          icon: Icons.cloud_outlined,
                          color: c.cardColor(4),
                          title: 'iCloud',
                          text: 'iPhone, iPad and Mac. Uses your Apple ID, '
                              'nothing to sign in to.',
                        ),
                      ],
                      const SizedBox(height: 12),
                      option(
                        value: null,
                        icon: Icons.smartphone_rounded,
                        color: c.hairline,
                        title: 'This device only',
                        text: 'No backup. Turn sync on any time from Settings.',
                      ),
                      const SizedBox(height: 14),
                      MergeSemantics(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => ref
                              .read(settingsRepositoryProvider)
                              .setWifiOnly(!wifiOnly),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      'Sync on Wi-Fi only',
                                      style: bodyStyle(
                                        context,
                                        16,
                                        weight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: wifiOnly,
                                    onChanged: (bool v) => ref
                                        .read(settingsRepositoryProvider)
                                        .setWifiOnly(v),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 20),
                      VarnaButton(
                        label: _buttonLabel,
                        busy: _busy,
                        onPressed: _continue,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _footnote,
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
