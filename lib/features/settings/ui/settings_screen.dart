import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_config.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/entitlements.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../shared/widgets/centered_column.dart';
import '../../../shared/widgets/section_label.dart';
import '../../../shared/widgets/settings_group.dart';
import '../../../shared/widgets/tokens.dart';
import '../../sync/logic/sync_status.dart';

/// App version shown in About. Override with
/// `--dart-define=APP_VERSION=1.2.3` in release builds.
const String _appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0',
);

/// The Settings tab.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  String _syncSubtitle(AppSettings? settings, SyncStatus status) {
    final SyncProviderId? provider = settings?.syncProvider;
    if (provider == null) {
      return 'Off. Your cards are only on this device.';
    }
    if (status is SyncSynced) {
      return '${provider.displayName}, all synced';
    }
    if (status is SyncSyncing) {
      return '${provider.displayName}, syncing';
    }
    if (status is SyncOffline) {
      return '${provider.displayName}, offline';
    }
    if (status is SyncError) {
      return '${provider.displayName}, needs attention';
    }
    if (status is SyncConflicts) {
      return '${provider.displayName}, ${status.count} need your choice';
    }
    return provider.displayName;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VarnaColors c = VarnaColors.of(context);
    final AppSettings? settings = ref.watch(settingsProvider).valueOrNull;
    final SyncStatus status =
        ref.watch(syncStatusProvider).valueOrNull ?? const SyncIdle();
    final bool isPlus = ref.watch(isPlusProvider).valueOrNull ?? false;
    final Entitlements entitlements = ref.watch(entitlementsProvider);

    return SafeArea(
      bottom: false,
      child: CenteredColumn(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
          children: <Widget>[
            Semantics(
              header: true,
              child: Text('Settings', style: displayStyle(context, 34, letterSpacing: -0.8)),
            ),
            const SizedBox(height: 12),
            SettingsGroup(
              children: <Widget>[
                SettingsRow(
                  leading: IconTile(
                    icon: Icons.cloud_sync_outlined,
                    color: c.cardColor(1),
                    size: 40,
                  ),
                  title: 'Sync and backup',
                  subtitle: _syncSubtitle(settings, status),
                  chevron: true,
                  onTap: () => context.push<void>('/settings/sync'),
                ),
                SettingsRow(
                  leading: IconTile(
                    icon: Icons.auto_awesome_outlined,
                    color: c.cardColor(0),
                    size: 40,
                  ),
                  title: '${AppConfig.appName} Plus',
                  subtitle: isPlus
                      ? 'Active on this device'
                      : '${AppConfig.plusPrice}, ${AppConfig.trialCopy}',
                  chevron: true,
                  onTap: () => context.push<void>('/paywall'),
                ),
              ],
            ),
            const SectionLabel('Appearance'),
            const SettingsGroup(
              children: <Widget>[
                SettingsRow(
                  title: 'Appearance',
                  subtitle: 'Light only for now',
                  enabled: false,
                ),
              ],
            ),
            const SectionLabel('About'),
            SettingsGroup(
              children: <Widget>[
                SettingsRow(
                  title: AppConfig.appName,
                  subtitle: 'Version $_appVersion',
                ),
                SettingsRow(
                  title: AppConfig.tagline,
                ),
              ],
            ),
            if (kDebugMode) ...<Widget>[
              const SectionLabel('Developer (debug builds only)'),
              SettingsGroup(
                children: <Widget>[
                  SettingsSwitchRow(
                    title: '${AppConfig.appName} Plus (local toggle)',
                    subtitle: 'Pretends you have Plus on this device. '
                        'No purchase is made.',
                    value: isPlus,
                    onChanged: entitlements.supportsDebugToggle
                        ? (bool v) => entitlements.setDebugPlus(v)
                        : null,
                  ),
                  SettingsRow(
                    title: 'Reset this month\'s usage',
                    subtitle: 'Sets the scan and transcript counters to zero.',
                    onTap: () async {
                      final ScaffoldMessengerState messenger =
                          ScaffoldMessenger.of(context);
                      await ref.read(settingsRepositoryProvider).resetUsage();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Usage counters reset.')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
