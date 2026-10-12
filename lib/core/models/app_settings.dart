import 'sync_models.dart';

/// Monthly usage counters for the free plan. `monthKey` is `yyyy-MM`; the
/// counters are zero when the stored month is not the current month.
class UsageSnapshot {
  const UsageSnapshot({
    required this.monthKey,
    required this.scans,
    required this.transcripts,
  });

  final String monthKey;
  final int scans;
  final int transcripts;

  @override
  bool operator ==(Object other) =>
      other is UsageSnapshot &&
      other.monthKey == monthKey &&
      other.scans == scans &&
      other.transcripts == transcripts;

  @override
  int get hashCode => Object.hash(monthKey, scans, transcripts);

  @override
  String toString() => 'UsageSnapshot($monthKey, scans=$scans, '
      'transcripts=$transcripts)';
}

/// Everything in the settings store, in one immutable value.
class AppSettings {
  const AppSettings({
    this.syncProvider,
    this.wifiOnly = false,
    this.includeMedia = true,
    this.onboardingDone = false,
    this.plusDebug = false,
    this.lastSyncAt,
    required this.usage,
  });

  /// Null when no cloud is connected.
  final SyncProviderId? syncProvider;
  final bool wifiOnly;
  final bool includeMedia;
  final bool onboardingDone;

  /// The debug Plus toggle (see `Entitlements`).
  final bool plusDebug;
  final DateTime? lastSyncAt;
  final UsageSnapshot usage;
}
