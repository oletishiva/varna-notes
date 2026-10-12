import '../../../app_config.dart';
import '../../../core/models/models.dart';

/// How urgent a renewal is.
enum RenewalUrgency {
  /// Past its date.
  overdue,

  /// Today or within the next 7 days.
  soon,

  /// Within the next 30 days (after the `soon` window).
  upcoming,

  /// Further away.
  later,
}

/// One row of the renewals list.
class RenewalItem {
  const RenewalItem({
    required this.card,
    required this.dueDate,
    required this.daysLeft,
    required this.urgency,
    required this.label,
    required this.folder,
  });

  final NoteCard card;

  /// Calendar date (`DateTime.utc(y, m, d)`).
  final DateTime dueDate;

  /// Whole days from today to [dueDate]; negative when overdue.
  final int daysLeft;

  final RenewalUrgency urgency;

  /// "Due today", "Due tomorrow", "Due in 12 days", "Overdue by 3 days", ...
  final String label;

  /// One of `AppConfig.paperFolders` (unknown or missing folders become the
  /// last entry, "Other").
  final String folder;
}

/// Pure logic behind the Papers / Renewals screens.
class RenewalsLogic {
  RenewalsLogic._();

  /// Folder names in display order (Insurance, Vehicle, Warranties, Bills,
  /// Other).
  static const List<String> folders = AppConfig.paperFolders;

  /// Maps any folder name (case-insensitive) to one of [folders]; null or
  /// unknown becomes the last entry.
  static String normalizeFolder(String? folder) {
    if (folder != null) {
      final String wanted = folder.trim().toLowerCase();
      for (final String f in folders) {
        if (f.toLowerCase() == wanted) {
          return f;
        }
      }
    }
    return folders.last;
  }

  /// Whole calendar days from the day of [now] to [expiry]'s calendar date.
  /// Only the year/month/day of both values are used (no time zones).
  static int daysUntil(DateTime expiry, DateTime now) {
    final DateTime a = DateTime.utc(expiry.year, expiry.month, expiry.day);
    final DateTime b = DateTime.utc(now.year, now.month, now.day);
    return a.difference(b).inDays;
  }

  /// Text for a day count: 0 "Due today", 1 "Due tomorrow", n "Due in n
  /// days", -1 "Overdue by 1 day", -n "Overdue by n days".
  static String dueLabel(int daysLeft) {
    if (daysLeft == 0) {
      return 'Due today';
    }
    if (daysLeft == 1) {
      return 'Due tomorrow';
    }
    if (daysLeft > 1) {
      return 'Due in $daysLeft days';
    }
    final int late = -daysLeft;
    return late == 1 ? 'Overdue by 1 day' : 'Overdue by $late days';
  }

  static RenewalUrgency urgencyFor(int daysLeft) {
    if (daysLeft < 0) {
      return RenewalUrgency.overdue;
    }
    if (daysLeft <= 7) {
      return RenewalUrgency.soon;
    }
    if (daysLeft <= 30) {
      return RenewalUrgency.upcoming;
    }
    return RenewalUrgency.later;
  }

  /// Renewal rows for all live cards that have an expiry date, soonest first
  /// (overdue ones first). [now] is "today" (pass `DateTime.now()`).
  ///
  /// [withinDays] keeps only items due within that many days (overdue items
  /// are kept unless [includeOverdue] is false).
  static List<RenewalItem> upcoming(
    Iterable<NoteCard> cards,
    DateTime now, {
    int? withinDays,
    bool includeOverdue = true,
  }) {
    final List<RenewalItem> items = <RenewalItem>[];
    for (final NoteCard card in cards) {
      final DateTime? expiry = card.expiryDate;
      if (card.deleted || expiry == null) {
        continue;
      }
      final int days = daysUntil(expiry, now);
      if (days < 0 && !includeOverdue) {
        continue;
      }
      if (withinDays != null && days > withinDays) {
        continue;
      }
      items.add(RenewalItem(
        card: card,
        dueDate: DateTime.utc(expiry.year, expiry.month, expiry.day),
        daysLeft: days,
        urgency: urgencyFor(days),
        label: dueLabel(days),
        folder: normalizeFolder(card.paperFolder),
      ));
    }
    items.sort((RenewalItem a, RenewalItem b) {
      final int c = a.dueDate.compareTo(b.dueDate);
      return c != 0 ? c : a.card.id.compareTo(b.card.id);
    });
    return items;
  }

  /// Groups [items] by folder, in [folders] order; folders without items are
  /// still present (empty lists) so the UI can show all of them.
  static Map<String, List<RenewalItem>> groupByFolder(
    Iterable<RenewalItem> items,
  ) {
    final Map<String, List<RenewalItem>> grouped = <String, List<RenewalItem>>{
      for (final String f in folders) f: <RenewalItem>[],
    };
    for (final RenewalItem item in items) {
      grouped[item.folder]!.add(item);
    }
    return grouped;
  }
}
