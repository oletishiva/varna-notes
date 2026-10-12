import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../shared/format.dart';
import '../../../shared/nav.dart';
import '../../../shared/widgets/centered_column.dart';
import '../../../shared/widgets/round_icon_button.dart';
import '../../../shared/widgets/section_label.dart';
import '../../../shared/widgets/settings_group.dart';
import '../../../shared/widgets/tokens.dart';
import '../../../shared/widgets/varna_button.dart';
import '../../sync/data/sync_controller.dart';
import '../../sync/logic/sync_status.dart';

class _SyncSummary {
  const _SyncSummary({required this.pending, required this.total});

  final int pending;
  final int total;
}

/// How many cards exist and how many changes still wait to upload. Re-runs
/// whenever the sync status changes.
final _syncSummaryProvider = FutureProvider.autoDispose<_SyncSummary>((ref) async {
  ref.watch(syncStatusProvider);
  final int pending = await ref.watch(syncControllerProvider).pendingChanges();
  final int total = (await ref.watch(notesRepositoryProvider).listAllCards()).length;
  return _SyncSummary(pending: pending, total: total);
});

/// "Sync and backup" settings.
class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  bool _syncing = false;
  bool _moving = false;

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _describe(SyncReport report) {
    if (report.offline) {
      return 'You appear to be offline. Your changes are saved here.';
    }
    if (report.aborted) {
      return report.errors.isNotEmpty
          ? report.errors.first.message
          : 'Could not reach your cloud.';
    }
    if (report.errors.isNotEmpty) {
      return 'Synced, but ${pluralize(report.errors.length, 'file')} could not be '
          'copied. Try again in a moment.';
    }
    if (report.conflicts > 0) {
      return '${pluralize(report.conflicts, 'card')} changed on two devices. '
          'Open Sync conflicts to choose.';
    }
    if (report.uploaded == 0 && report.downloaded == 0) {
      return 'Everything is up to date.';
    }
    return 'Synced. Sent ${report.uploaded}, received ${report.downloaded}.';
  }

  Future<void> _syncNow() async {
    if (_syncing) {
      return;
    }
    setState(() => _syncing = true);
    try {
      final SyncReport report = await ref.read(syncControllerProvider).syncNow();
      if (mounted) {
        _say(_describe(report));
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  Future<void> _moveTo(SyncProviderId target) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final VarnaColors c = VarnaColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Move to ${target.displayName}?', style: displayStyle(dialogContext, 22)),
          content: Text(
            'Varna copies all your cards to ${target.displayName} and uses it '
            'from now on. Nothing is deleted from your phone.',
            style: bodyStyle(dialogContext, 15),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Move'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) {
      return;
    }
    setState(() => _moving = true);
    try {
      final SyncReport report = await ref.read(syncControllerProvider).connect(target);
      if (!mounted) {
        return;
      }
      if (report.aborted || report.offline) {
        _say(_describe(report));
      } else {
        _say('Now using ${target.displayName}.');
      }
    } finally {
      if (mounted) {
        setState(() => _moving = false);
      }
    }
  }

  Future<void> _disconnect() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final VarnaColors c = VarnaColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Disconnect your cloud?', style: displayStyle(dialogContext, 22)),
          content: Text(
            'Varna stops backing up. Every card stays on this phone, and '
            'your cloud copy is left as it is.',
            style: bodyStyle(dialogContext, 15),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: c.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Disconnect'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) {
      return;
    }
    await ref.read(syncControllerProvider).disconnect();
    if (mounted) {
      _say('Disconnected. Your cards are still on this phone.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final SyncController controller = ref.watch(syncControllerProvider);
    final AppSettings? settings = ref.watch(settingsProvider).valueOrNull;
    final SyncStatus status =
        ref.watch(syncStatusProvider).valueOrNull ?? const SyncIdle();
    final int conflicts = ref.watch(conflictsProvider).valueOrNull?.length ?? 0;
    final _SyncSummary? summary = ref.watch(_syncSummaryProvider).valueOrNull;
    final SyncProviderId? provider = settings?.syncProvider;
    final bool connected = provider != null;
    void setWifiOnly(bool value) {
      unawaited(ref.read(settingsRepositoryProvider).setWifiOnly(value));
    }

    void setIncludeMedia(bool value) {
      unawaited(ref.read(settingsRepositoryProvider).setIncludeMedia(value));
    }

    // ---- status card text
    String headline;
    String subline;
    IconData icon = Icons.check_rounded;
    Color iconBg = c.cardColor(2);
    if (!connected) {
      headline = 'Backup is off';
      subline = 'Your cards are only on this device.';
      icon = Icons.cloud_off_outlined;
      iconBg = c.cardColor(0);
    } else if (status is SyncSyncing || _syncing) {
      headline = 'Syncing your cards';
      subline = 'This can take a moment.';
      icon = Icons.cloud_sync_outlined;
      iconBg = c.cardColor(1);
    } else if (status is SyncOffline) {
      headline = 'You are offline';
      subline = 'Changes are saved here and upload when you are back online.';
      icon = Icons.cloud_off_outlined;
      iconBg = c.cardColor(0);
    } else if (status is SyncError) {
      headline = 'Sync hit a problem';
      subline = status.message;
      icon = Icons.error_outline_rounded;
      iconBg = c.cardColor(3);
    } else if (status is SyncConflicts) {
      headline = status.count == 1
          ? '1 item needs your choice'
          : '${status.count} items need your choice';
      subline = 'Both versions are kept until you decide.';
      icon = Icons.warning_amber_rounded;
      iconBg = c.cardColor(3);
    } else if (summary != null && summary.pending > 0) {
      headline = '${pluralize(summary.pending, 'change')} waiting to upload';
      subline = 'Tap Sync now to send them.';
      icon = Icons.cloud_upload_outlined;
      iconBg = c.cardColor(0);
    } else {
      final int total = summary?.total ?? 0;
      headline = total == 0
          ? 'Everything is backed up'
          : 'All ${pluralize(total, 'card')} backed up';
      final DateTime? last = settings?.lastSyncAt;
      subline = last == null
          ? 'Not synced yet'
          : 'Last synced ${dayAndTime(last)}';
    }
    if (status is SyncSynced && connected && summary != null && summary.pending == 0) {
      subline = 'Last synced ${dayAndTime(status.at)}';
    }

    final SyncProviderId? other = provider == null
        ? null
        : (provider == SyncProviderId.googleDrive
            ? SyncProviderId.icloud
            : SyncProviderId.googleDrive);
    final SyncProviderId? movable =
        (other != null && controller.isProviderSupported(other)) ? other : null;

    return Scaffold(
      body: SafeArea(
        child: CenteredColumn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: <Widget>[
              Row(
                children: <Widget>[
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: () => goBackOr(context, '/settings'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Sync and backup',
                        style: displayStyle(context, 26),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: c.ink,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        ExcludeSemantics(
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: iconBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 26, color: c.ink),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                headline,
                                style: displayStyle(
                                  context,
                                  21,
                                  letterSpacing: -0.2,
                                  color: Colors.white,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subline,
                                style: bodyStyle(
                                  context,
                                  14,
                                  color: VarnaExtras.onDarkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    VarnaButton(
                      label: connected ? 'Sync now' : 'Choose a cloud',
                      background: c.cardColor(0),
                      foreground: c.ink,
                      busy: _syncing,
                      onPressed: connected
                          ? () => unawaited(_syncNow())
                          : () => unawaited(context.push<void>('/sync-setup')),
                    ),
                  ],
                ),
              ),
              if (conflicts > 0) ...<Widget>[
                const SectionLabel('Needs your choice'),
                SettingsGroup(
                  children: <Widget>[
                    SettingsRow(
                      leading: const IconTile(
                        icon: Icons.warning_amber_rounded,
                        color: VarnaExtras.warnBg,
                        size: 40,
                      ),
                      title: 'Sync conflicts',
                      subtitle: '${pluralize(conflicts, 'item')} changed on two devices',
                      subtitleColor: VarnaExtras.warnText,
                      chevron: true,
                      onTap: () => context.push<void>('/settings/sync/conflicts'),
                    ),
                  ],
                ),
              ],
              if (provider != null) ...<Widget>[
                const SectionLabel('Your cloud'),
                SettingsGroup(
                  children: <Widget>[
                    SettingsRow(
                      leading: IconTile(
                        icon: provider == SyncProviderId.googleDrive
                            ? Icons.add_to_drive_outlined
                            : Icons.cloud_outlined,
                        color: provider == SyncProviderId.googleDrive
                            ? c.cardColor(1)
                            : c.cardColor(4),
                        size: 40,
                      ),
                      title: provider.displayName,
                      subtitle: controller.accountLabel ?? 'Connected',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.successBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Active',
                          style: bodyStyle(
                            context,
                            13,
                            weight: FontWeight.w700,
                            color: c.successText,
                          ),
                        ),
                      ),
                    ),
                    if (movable != null)
                      SettingsRow(
                        title: 'Move to ${movable.displayName} instead',
                        chevron: !_moving,
                        trailing: _moving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                        onTap: _moving ? null : () => unawaited(_moveTo(movable)),
                      ),
                  ],
                ),
              ],
              const SectionLabel('How it syncs'),
              SettingsGroup(
                children: <Widget>[
                  SettingsSwitchRow(
                    title: 'Wi-Fi only',
                    value: settings?.wifiOnly ?? false,
                    onChanged: settings == null ? null : setWifiOnly,
                  ),
                  SettingsSwitchRow(
                    title: 'Include voice, photos and scans',
                    value: settings?.includeMedia ?? true,
                    onChanged: settings == null ? null : setIncludeMedia,
                  ),
                  const SettingsSwitchRow(
                    title: 'Encrypt backup with a passcode',
                    subtitle: 'Coming soon',
                    value: false,
                    onChanged: null,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Expanded(
                    child: VarnaButton(
                      label: 'Export as ZIP',
                      kind: VarnaButtonKind.secondary,
                      onPressed: null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: VarnaButton(
                      label: 'Disconnect',
                      kind: VarnaButtonKind.secondary,
                      foreground: c.danger,
                      background: c.surface,
                      onPressed: connected ? () => unawaited(_disconnect()) : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Export as ZIP is coming soon. Disconnecting keeps every card '
                'on this phone.',
                textAlign: TextAlign.center,
                style: bodyStyle(context, 13, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
