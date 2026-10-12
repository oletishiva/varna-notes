import '../../../app_config.dart';
import '../../../core/models/models.dart';
import '../../../core/services/reminder_service.dart';
import '../../cards/ui/widgets/card_saver.dart';
import '../../cards/ui/widgets/format_utils.dart';

/// Renewal reminders fire this many days before the date, at 9:00.
const int kRenewalLeadDays = 7;

/// What happened when a renewal date was saved (and a reminder was wanted).
enum RenewalReminderResult {
  /// No reminder was asked for.
  notRequested,

  /// The reminder is scheduled.
  scheduled,

  /// Renewal reminders are part of Varna Plus; the date was still saved.
  needsPlus,

  /// This platform cannot show notifications (web).
  unsupported,

  /// The user did not allow notifications.
  permissionDenied,

  /// The reminder time ([kRenewalLeadDays] before) has already passed.
  tooLate,
}

/// When the reminder for [expiry] should fire: 9:00 local time
/// [kRenewalLeadDays] days before, or null when that moment is not in the
/// future of [now].
DateTime? renewalReminderTime(DateTime expiry, DateTime now) {
  final DateTime when = DateTime(
    expiry.year,
    expiry.month,
    expiry.day - kRenewalLeadDays,
    9,
  );
  return when.isAfter(now) ? when : null;
}

/// The earliest date the renewal date pickers offer. Parsed or old dates can
/// lie far in the past.
final DateTime kRenewalPickerFirstDate = DateTime(2000);

/// Moves [date] into [first]..[last]. `showDatePicker` asserts when its
/// `initialDate` lies outside that range, so always pass it through here.
DateTime clampPickerDate(DateTime date, DateTime first, DateTime last) {
  if (date.isBefore(first)) {
    return first;
  }
  if (date.isAfter(last)) {
    return last;
  }
  return date;
}

/// Picks one of `AppConfig.paperFolders` from text read off a paper.
String guessPaperFolder(String text) {
  final String t = text.toLowerCase();
  bool has(List<String> words) => words.any(t.contains);
  if (has(<String>['insurance', 'policy', 'premium', 'insured'])) {
    return 'Insurance';
  }
  if (has(<String>[
    'vehicle',
    'registration',
    'pollution',
    'driving licence',
    'driving license',
    'chassis',
  ])) {
    return 'Vehicle';
  }
  if (has(<String>['warranty', 'guarantee'])) {
    return 'Warranties';
  }
  if (has(<String>['bill', 'invoice', 'amount due', 'due date'])) {
    return 'Bills';
  }
  return AppConfig.paperFolders.last;
}

/// Saves the renewal date of a card (and its folder) and, when [remind] is
/// true, schedules the reminder if allowed. Reminders are a Plus feature: for
/// free users the date is saved and [RenewalReminderResult.needsPlus] is
/// returned so the caller can show the upsell line.
Future<RenewalReminderResult> saveRenewalDate({
  required CardSaver saver,
  required NoteCard card,
  required DateTime? expiry,
  required bool remind,
  required bool isPlus,
  required ReminderService reminders,
  String? folder,
  DateTime? now,
}) async {
  final DateTime? date =
      expiry == null ? null : DateTime.utc(expiry.year, expiry.month, expiry.day);
  await saver.update((NoteCard c) => c.copyWith(
        expiryDate: date,
        paperFolder: folder ?? c.paperFolder,
      ));
  if (date == null || !remind) {
    return RenewalReminderResult.notRequested;
  }
  if (!isPlus) {
    return RenewalReminderResult.needsPlus;
  }
  if (!reminders.isSupported) {
    return RenewalReminderResult.unsupported;
  }
  final DateTime? when = renewalReminderTime(date, now ?? DateTime.now());
  if (when == null) {
    return RenewalReminderResult.tooLate;
  }
  final bool allowed = await reminders.requestPermission();
  if (!allowed) {
    return RenewalReminderResult.permissionDenied;
  }
  final String title = card.title.trim().isEmpty ? 'Paper' : card.title.trim();
  await reminders.schedule(
    cardId: card.id,
    title: 'Renewal due soon: $title',
    body: 'Expires ${formatDate(date)}.',
    when: when,
  );
  await saver.update((NoteCard c) => c.copyWith(reminderAt: when.toUtc()));
  return RenewalReminderResult.scheduled;
}

/// A sentence for a snackbar describing [result]; null when nothing needs
/// saying.
String? describeRenewalResult(RenewalReminderResult result, DateTime date) {
  switch (result) {
    case RenewalReminderResult.notRequested:
      return null;
    case RenewalReminderResult.scheduled:
      return 'Date saved. We will remind you $kRenewalLeadDays days before '
          '${formatDate(date)}.';
    case RenewalReminderResult.needsPlus:
      return 'Date saved. Renewal reminders are part of '
          '${AppConfig.appName} Plus.';
    case RenewalReminderResult.unsupported:
      return 'Date saved. Reminders work in the ${AppConfig.appName} mobile '
          'app.';
    case RenewalReminderResult.permissionDenied:
      return 'Date saved. Turn on notifications in your phone settings to get '
          'reminders.';
    case RenewalReminderResult.tooLate:
      return 'Date saved. It is too close for a $kRenewalLeadDays-day reminder.';
  }
}
