import 'package:flutter/material.dart';

import '../../core/theme/varna_colors.dart';
import '../../core/theme/varna_theme.dart';
import '../../features/sync/logic/sync_status.dart';
import 'tokens.dart';

/// The sync status pill ("Synced", "Syncing...", "Offline"...).
///
/// [connected] is false when no cloud is chosen: the pill then says
/// "This device".
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.connected = true,
    this.onTap,
  });

  final SyncStatus status;
  final bool connected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);

    String label;
    IconData icon;
    Color bg;
    Color fg;
    bool spinner = false;

    final SyncStatus s = status;
    if (!connected) {
      label = 'This device';
      icon = Icons.smartphone_rounded;
      bg = c.hairline;
      fg = c.muted;
    } else if (s is SyncSynced) {
      label = 'Synced';
      icon = Icons.cloud_done_outlined;
      bg = c.successBg;
      fg = c.successText;
    } else if (s is SyncSyncing) {
      label = 'Syncing';
      icon = Icons.cloud_sync_outlined;
      bg = c.surface;
      fg = c.ink;
      spinner = true;
    } else if (s is SyncOffline) {
      label = 'Offline';
      icon = Icons.cloud_off_outlined;
      bg = c.hairline;
      fg = c.muted;
    } else if (s is SyncError) {
      label = 'Sync problem';
      icon = Icons.error_outline_rounded;
      bg = c.danger.withValues(alpha: 0.12);
      fg = c.danger;
    } else if (s is SyncConflicts) {
      label = s.count == 1 ? '1 needs you' : '${s.count} need you';
      icon = Icons.warning_amber_rounded;
      bg = VarnaExtras.warnBg;
      fg = VarnaExtras.warnText;
    } else {
      label = 'Not synced yet';
      icon = Icons.cloud_queue_rounded;
      bg = c.surface;
      fg = c.ink;
    }

    return Semantics(
      button: onTap != null,
      label: 'Sync status',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(VarnaMetrics.pillRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: VarnaMetrics.minTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (spinner)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                    )
                  else
                    Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: bodyStyle(context, 13, weight: FontWeight.w600, color: fg),
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
