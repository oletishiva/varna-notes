import 'package:sembast/sembast.dart';

import '../clock.dart';
import '../models/models.dart';

typedef _Snap = RecordSnapshot<String, Map<String, Object?>>;

/// App-level preferences and the free-plan usage counters, persisted in the
/// same database as the notes.
class SettingsRepository {
  SettingsRepository(this._db, {Clock? clock}) : _clock = clock ?? systemClock;

  final Database _db;
  final Clock _clock;

  final StoreRef<String, Map<String, Object?>> _store =
      stringMapStoreFactory.store('settings');

  static const String _kProvider = 'syncProvider';
  static const String _kWifiOnly = 'wifiOnly';
  static const String _kIncludeMedia = 'includeMedia';
  static const String _kOnboarding = 'onboardingDone';
  static const String _kPlusDebug = 'plusDebug';
  static const String _kLastSync = 'lastSyncAt';
  static const String _kUsageMonth = 'usageMonth';
  static const String _kUsageScans = 'usageScans';
  static const String _kUsageTranscripts = 'usageTranscripts';

  // ------------------------------------------------------------------ helpers

  Future<T?> _read<T>(DatabaseClient client, String key) async {
    final Map<String, Object?>? v = await _store.record(key).get(client);
    final Object? x = v?['value'];
    return x is T ? x : null;
  }

  Future<void> _write(DatabaseClient client, String key, Object? value) async {
    if (value == null) {
      await _store.record(key).delete(client);
    } else {
      await _store.record(key).put(client, <String, Object?>{'value': value});
    }
  }

  /// `yyyy-MM` of the injected clock's current time.
  String currentMonthKey() {
    final DateTime now = _clock();
    final String m = now.month < 10 ? '0${now.month}' : '${now.month}';
    return '${now.year}-$m';
  }

  AppSettings _fromMap(Map<String, Object?> map) {
    T? get<T>(String key) {
      final Object? x = map[key];
      return x is T ? x : null;
    }

    final String month = currentMonthKey();
    final bool sameMonth = get<String>(_kUsageMonth) == month;
    final String? lastSync = get<String>(_kLastSync);
    return AppSettings(
      syncProvider: SyncProviderId.fromName(get<String>(_kProvider)),
      wifiOnly: get<bool>(_kWifiOnly) ?? false,
      includeMedia: get<bool>(_kIncludeMedia) ?? true,
      onboardingDone: get<bool>(_kOnboarding) ?? false,
      plusDebug: get<bool>(_kPlusDebug) ?? false,
      lastSyncAt: lastSync == null ? null : DateTime.parse(lastSync).toUtc(),
      usage: UsageSnapshot(
        monthKey: month,
        scans: sameMonth ? (get<int>(_kUsageScans) ?? 0) : 0,
        transcripts: sameMonth ? (get<int>(_kUsageTranscripts) ?? 0) : 0,
      ),
    );
  }

  Map<String, Object?> _flatten(List<_Snap> snaps) {
    final Map<String, Object?> map = <String, Object?>{};
    for (final _Snap s in snaps) {
      map[s.key] = s.value['value'];
    }
    return map;
  }

  // -------------------------------------------------------------------- reads

  /// All settings at once.
  Future<AppSettings> load() async {
    return _fromMap(_flatten(await _store.find(_db)));
  }

  /// Emits the current settings, then again after every change.
  Stream<AppSettings> watch() {
    return _store
        .query()
        .onSnapshots(_db)
        .map((List<_Snap> snaps) => _fromMap(_flatten(snaps)));
  }

  Future<SyncProviderId?> getSyncProvider() async =>
      (await load()).syncProvider;
  Future<bool> getWifiOnly() async => (await load()).wifiOnly;
  Future<bool> getIncludeMedia() async => (await load()).includeMedia;
  Future<bool> getOnboardingDone() async => (await load()).onboardingDone;
  Future<bool> getPlusDebug() async => (await load()).plusDebug;
  Future<DateTime?> getLastSyncAt() async => (await load()).lastSyncAt;

  // ------------------------------------------------------------------- writes

  /// Pass null to disconnect (local data is untouched).
  Future<void> setSyncProvider(SyncProviderId? provider) =>
      _write(_db, _kProvider, provider?.name);

  Future<void> setWifiOnly(bool value) => _write(_db, _kWifiOnly, value);
  Future<void> setIncludeMedia(bool value) =>
      _write(_db, _kIncludeMedia, value);
  Future<void> setOnboardingDone(bool value) =>
      _write(_db, _kOnboarding, value);
  Future<void> setPlusDebug(bool value) => _write(_db, _kPlusDebug, value);
  Future<void> setLastSyncAt(DateTime? value) =>
      _write(_db, _kLastSync, value?.toUtc().toIso8601String());

  // -------------------------------------------------------------------- usage

  /// This month's counters (zero when the stored month is not this month).
  Future<UsageSnapshot> getUsage() async => (await load()).usage;

  Future<UsageSnapshot> incrementScans([int by = 1]) =>
      _increment(by, 0);

  Future<UsageSnapshot> incrementTranscripts([int by = 1]) =>
      _increment(0, by);

  /// Sets both counters to zero for the current month (debug/support).
  Future<void> resetUsage() async {
    await _db.transaction((Transaction txn) async {
      await _write(txn, _kUsageMonth, currentMonthKey());
      await _write(txn, _kUsageScans, 0);
      await _write(txn, _kUsageTranscripts, 0);
    });
  }

  Future<UsageSnapshot> _increment(int scansBy, int transcriptsBy) {
    return _db.transaction((Transaction txn) async {
      final String month = currentMonthKey();
      final bool same = (await _read<String>(txn, _kUsageMonth)) == month;
      final int scans =
          (same ? (await _read<int>(txn, _kUsageScans) ?? 0) : 0) + scansBy;
      final int transcripts =
          (same ? (await _read<int>(txn, _kUsageTranscripts) ?? 0) : 0) +
              transcriptsBy;
      await _write(txn, _kUsageMonth, month);
      await _write(txn, _kUsageScans, scans);
      await _write(txn, _kUsageTranscripts, transcripts);
      return UsageSnapshot(
        monthKey: month,
        scans: scans,
        transcripts: transcripts,
      );
    });
  }
}
