import 'package:intl/intl.dart';

import '../../../../core/models/models.dart';

/// "0:42", "12:05" or "1:02:03".
String formatClock(Duration d) {
  final int total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final int h = total ~/ 3600;
  final int m = (total % 3600) ~/ 60;
  final int s = total % 60;
  final String ss = s < 10 ? '0$s' : '$s';
  if (h > 0) {
    final String mm = m < 10 ? '0$m' : '$m';
    return '$h:$mm:$ss';
  }
  return '$m:$ss';
}

/// "00:42" style used by the big recording timer.
String formatTimer(Duration d) {
  final int total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final int m = total ~/ 60;
  final int s = total % 60;
  final String mm = m < 10 ? '0$m' : '$m';
  final String ss = s < 10 ? '0$s' : '$s';
  return '$mm:$ss';
}

/// "Mon 12 Oct, 6:30 PM" in the device time zone.
String formatDateTime(DateTime value) =>
    DateFormat('EEE d MMM, h:mm a').format(value.toLocal());

/// "18 Oct 2026" for a calendar date (`DateTime.utc(y, m, d)`); the time zone
/// is ignored.
String formatDate(DateTime date) =>
    DateFormat('d MMM yyyy').format(DateTime(date.year, date.month, date.day));

/// "12 Oct, 6:30 PM" for default titles.
String formatStamp(DateTime value) =>
    DateFormat('d MMM, h:mm a').format(value.toLocal());

/// "today", "yesterday" or "12 Oct" for the "edited ..." line.
String editedLabel(DateTime updatedAt, DateTime now) {
  final DateTime a = updatedAt.toLocal();
  final DateTime b = now.toLocal();
  final DateTime dayA = DateTime(a.year, a.month, a.day);
  final DateTime dayB = DateTime(b.year, b.month, b.day);
  final int days = dayB.difference(dayA).inDays;
  if (days <= 0) {
    return 'today';
  }
  if (days == 1) {
    return 'yesterday';
  }
  return DateFormat('d MMM').format(a);
}

/// Human name of a card type, for list rows and search results.
String cardTypeLabel(CardType type) {
  switch (type) {
    case CardType.text:
      return 'Note';
    case CardType.checklist:
      return 'Checklist';
    case CardType.voice:
      return 'Voice note';
    case CardType.photo:
      return 'Photo';
    case CardType.scan:
      return 'Scan';
    case CardType.link:
      return 'Link';
  }
}

/// Title to show for a card that may have no title yet.
String displayTitle(NoteCard card) {
  final String t = card.title.trim();
  if (t.isNotEmpty) {
    return t;
  }
  switch (card.type) {
    case CardType.text:
      return 'Untitled note';
    case CardType.checklist:
      return 'Untitled checklist';
    case CardType.voice:
      return 'Voice note';
    case CardType.photo:
      return 'Photo';
    case CardType.scan:
      return 'Scan';
    case CardType.link:
      return 'Link';
  }
}

/// Guesses an audio mime type from a file name, for players that need one.
String audioMimeType(String fileName) {
  final String lower = fileName.toLowerCase();
  if (lower.endsWith('.m4a') || lower.endsWith('.mp4') || lower.endsWith('.aac')) {
    return 'audio/mp4';
  }
  if (lower.endsWith('.webm')) {
    return 'audio/webm';
  }
  if (lower.endsWith('.wav')) {
    return 'audio/wav';
  }
  if (lower.endsWith('.ogg') || lower.endsWith('.opus')) {
    return 'audio/ogg';
  }
  if (lower.endsWith('.mp3')) {
    return 'audio/mpeg';
  }
  return 'audio/mp4';
}

/// Guesses an image mime type from a file name.
String imageMimeType(String fileName) {
  final String lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  return 'image/jpeg';
}
