import '../../app_config.dart';
import '../data/notes_repository.dart';
import '../data/settings_repository.dart';
import '../models/models.dart';
import 'entitlements.dart';

/// Why an action was refused.
enum LimitReason {
  notebookLimit,
  scanLimit,
  transcriptLimit,
}

/// Answer to "may the user do this?".
class LimitCheck {
  const LimitCheck({
    required this.allowed,
    required this.used,
    required this.limit,
    this.reason,
    this.message = '',
  });

  /// True when the action may go ahead.
  final bool allowed;

  /// How many have been used (notebooks now / scans this month / ...).
  final int used;

  /// The free limit, or null when unlimited (Plus).
  final int? limit;

  /// Why it was refused; null when [allowed].
  final LimitReason? reason;

  /// Text for the paywall prompt; empty when [allowed].
  final String message;

  /// Remaining uses, or null when unlimited.
  int? get remaining {
    final int? max = limit;
    if (max == null) {
      return null;
    }
    return used >= max ? 0 : max - used;
  }
}

/// Free-plan limits (see `AppConfig`). Plus users are unlimited.
class UsageLimits {
  UsageLimits({
    required NotesRepository notes,
    required SettingsRepository settings,
    required Entitlements entitlements,
  })  : _notes = notes,
        _settings = settings,
        _entitlements = entitlements;

  final NotesRepository _notes;
  final SettingsRepository _settings;
  final Entitlements _entitlements;

  /// May another notebook be created?
  Future<LimitCheck> canCreateNotebook() async {
    final int used = await _notes.countNotebooks();
    if (await _entitlements.isPlus()) {
      return LimitCheck(allowed: true, used: used, limit: null);
    }
    const int limit = AppConfig.freeNotebookLimit;
    if (used < limit) {
      return LimitCheck(allowed: true, used: used, limit: limit);
    }
    return LimitCheck(
      allowed: false,
      used: used,
      limit: limit,
      reason: LimitReason.notebookLimit,
      message: 'The free plan includes $limit notebooks. '
          'Upgrade to ${AppConfig.appName} Plus for unlimited notebooks.',
    );
  }

  /// May another scan (OCR) be made this month?
  Future<LimitCheck> canScan() async {
    final UsageSnapshot usage = await _settings.getUsage();
    if (await _entitlements.isPlus()) {
      return LimitCheck(allowed: true, used: usage.scans, limit: null);
    }
    const int limit = AppConfig.freeScansPerMonth;
    if (usage.scans < limit) {
      return LimitCheck(allowed: true, used: usage.scans, limit: limit);
    }
    return LimitCheck(
      allowed: false,
      used: usage.scans,
      limit: limit,
      reason: LimitReason.scanLimit,
      message: 'You have used all $limit free scans this month. '
          'Upgrade to ${AppConfig.appName} Plus for unlimited scans.',
    );
  }

  /// May another voice transcript be made this month?
  Future<LimitCheck> canTranscribe() async {
    final UsageSnapshot usage = await _settings.getUsage();
    if (await _entitlements.isPlus()) {
      return LimitCheck(allowed: true, used: usage.transcripts, limit: null);
    }
    const int limit = AppConfig.freeTranscriptsPerMonth;
    if (usage.transcripts < limit) {
      return LimitCheck(
        allowed: true,
        used: usage.transcripts,
        limit: limit,
      );
    }
    return LimitCheck(
      allowed: false,
      used: usage.transcripts,
      limit: limit,
      reason: LimitReason.transcriptLimit,
      message: 'You have used all $limit free transcripts this month. '
          'Upgrade to ${AppConfig.appName} Plus for more.',
    );
  }

  /// Counts one scan against this month's allowance. Call it after a scan
  /// actually happened.
  Future<UsageSnapshot> recordScan() => _settings.incrementScans();

  /// Counts one transcript against this month's allowance.
  Future<UsageSnapshot> recordTranscript() => _settings.incrementTranscripts();
}
