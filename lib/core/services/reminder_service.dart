/// Stable positive 31-bit notification id for a card id (a simple polynomial
/// hash, identical on every platform and run). Used so a card's reminder can
/// be re-scheduled or cancelled later.
int reminderNotificationId(String cardId) {
  int hash = 7;
  for (final int unit in cardId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return hash;
}

/// Local (on-device) notifications for card reminders and renewal alerts.
/// A no-op on web and desktop ([isSupported] is false).
abstract class ReminderService {
  bool get isSupported;

  /// Asks the OS for notification permission; returns whether it is granted.
  /// Call it in response to a user action (for example when they first set a
  /// reminder).
  Future<bool> requestPermission();

  /// Schedules (or re-schedules) the single reminder of card [cardId] at
  /// [when]. A time in the past is ignored.
  Future<void> schedule({
    required String cardId,
    required String title,
    String? body,
    required DateTime when,
  });

  /// Cancels the reminder of card [cardId]; no error if none exists.
  Future<void> cancel(String cardId);
}

/// Does nothing; used on web/desktop and as a safe default.
class NoopReminderService implements ReminderService {
  const NoopReminderService();

  @override
  bool get isSupported => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule({
    required String cardId,
    required String title,
    String? body,
    required DateTime when,
  }) async {}

  @override
  Future<void> cancel(String cardId) async {}
}
