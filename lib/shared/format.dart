import 'package:intl/intl.dart';

/// "3 cards", "1 card".
String pluralize(int n, String one, [String? many]) =>
    n == 1 ? '$n $one' : '$n ${many ?? '${one}s'}';

/// m:ss for a duration in milliseconds.
String formatDuration(int? ms) {
  final int seconds = ((ms ?? 0) / 1000).round();
  final String rest = (seconds % 60).toString().padLeft(2, '0');
  return '${seconds ~/ 60}:$rest';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// "today", "yesterday", "2 Oct" or "2 Oct 2025" (lower case, for use inside
/// a sentence).
String relativeDay(DateTime when, {DateTime? now}) {
  final DateTime local = when.toLocal();
  final DateTime today = _day(now ?? DateTime.now());
  final int diff = today.difference(_day(local)).inDays;
  if (diff == 0) {
    return 'today';
  }
  if (diff == 1) {
    return 'yesterday';
  }
  if (local.year == today.year) {
    return DateFormat('d MMM').format(local);
  }
  return DateFormat('d MMM y').format(local);
}

/// "12:34 PM".
String clockTime(DateTime when) => DateFormat('h:mm a').format(when.toLocal());

/// "today at 12:34 PM".
String dayAndTime(DateTime when, {DateTime? now}) =>
    '${relativeDay(when, now: now)} at ${clockTime(when)}';

/// Heading for a group of reminders: "Today", "Tomorrow", "Mon 14 Oct".
String dayHeading(DateTime when, {DateTime? now}) {
  final DateTime local = when.toLocal();
  final DateTime today = _day(now ?? DateTime.now());
  final int diff = _day(local).difference(today).inDays;
  if (diff == 0) {
    return 'Today';
  }
  if (diff == 1) {
    return 'Tomorrow';
  }
  if (local.year == today.year) {
    return DateFormat('EEE d MMM').format(local);
  }
  return DateFormat('EEE d MMM y').format(local);
}

/// The first day of next month as "1 November" (monthly limits reset then).
String nextMonthStart(DateTime now) {
  final DateTime first = DateTime(now.year, now.month + 1, 1);
  return DateFormat('d MMMM').format(first);
}
