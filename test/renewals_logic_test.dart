import 'package:flutter_test/flutter_test.dart';
import 'package:varna/app_config.dart';
import 'package:varna/core/models/models.dart';
import 'package:varna/features/papers/logic/renewals_logic.dart';

NoteCard paper(
  String id,
  DateTime? expiry, {
  String? folder,
  bool deleted = false,
}) {
  return NoteCard(
    id: id,
    notebookId: 'nb',
    type: CardType.scan,
    title: id,
    expiryDate: expiry,
    paperFolder: folder,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    deleted: deleted,
  );
}

void main() {
  // "Today" for all tests: 12 Oct 2026, late evening (time must not matter).
  final DateTime today = DateTime(2026, 10, 12, 23, 59);

  group('daysUntil', () {
    test('same day is 0', () {
      expect(RenewalsLogic.daysUntil(DateTime.utc(2026, 10, 12), today), 0);
    });

    test('18 Oct is 6 days after 12 Oct', () {
      // 18 - 12 = 6.
      expect(RenewalsLogic.daysUntil(DateTime.utc(2026, 10, 18), today), 6);
    });

    test('past dates are negative', () {
      // 9 Oct is 3 days before 12 Oct.
      expect(RenewalsLogic.daysUntil(DateTime.utc(2026, 10, 9), today), -3);
    });

    test('counts across a month end', () {
      // 12 Oct -> 31 Oct = 19 days, -> 2 Nov = 21 days.
      expect(RenewalsLogic.daysUntil(DateTime.utc(2026, 11, 2), today), 21);
    });

    test('counts across a leap day', () {
      // 28 Feb 2028 -> 29 Feb -> 1 Mar = 2 days (2028 is a leap year).
      expect(
        RenewalsLogic.daysUntil(DateTime.utc(2028, 3, 1), DateTime(2028, 2, 28)),
        2,
      );
    });

    test('counts across daylight-saving changes (calendar days only)', () {
      // Local midnight values; whole calendar days, never 23/25 hour effects.
      expect(
        RenewalsLogic.daysUntil(DateTime.utc(2026, 11, 2), DateTime(2026, 11, 1, 0, 30)),
        1,
      );
    });
  });

  group('labels and urgency', () {
    test('dueLabel', () {
      expect(RenewalsLogic.dueLabel(0), 'Due today');
      expect(RenewalsLogic.dueLabel(1), 'Due tomorrow');
      expect(RenewalsLogic.dueLabel(2), 'Due in 2 days');
      expect(RenewalsLogic.dueLabel(45), 'Due in 45 days');
      expect(RenewalsLogic.dueLabel(-1), 'Overdue by 1 day');
      expect(RenewalsLogic.dueLabel(-3), 'Overdue by 3 days');
    });

    test('urgencyFor', () {
      expect(RenewalsLogic.urgencyFor(-1), RenewalUrgency.overdue);
      expect(RenewalsLogic.urgencyFor(0), RenewalUrgency.soon);
      expect(RenewalsLogic.urgencyFor(7), RenewalUrgency.soon);
      expect(RenewalsLogic.urgencyFor(8), RenewalUrgency.upcoming);
      expect(RenewalsLogic.urgencyFor(30), RenewalUrgency.upcoming);
      expect(RenewalsLogic.urgencyFor(31), RenewalUrgency.later);
    });
  });

  group('upcoming', () {
    test('sorts soonest first, overdue first of all, skips unusable cards', () {
      final List<NoteCard> cards = <NoteCard>[
        paper('later', DateTime.utc(2027, 1, 1)),
        paper('overdue', DateTime.utc(2026, 10, 9)),
        paper('none', null),
        paper('gone', DateTime.utc(2026, 10, 20), deleted: true),
        paper('soon', DateTime.utc(2026, 10, 18)),
      ];
      final List<RenewalItem> items = RenewalsLogic.upcoming(cards, today);
      expect(items.map((RenewalItem i) => i.card.id),
          <String>['overdue', 'soon', 'later']);
      expect(items[0].daysLeft, -3);
      expect(items[0].label, 'Overdue by 3 days');
      expect(items[0].urgency, RenewalUrgency.overdue);
      expect(items[1].daysLeft, 6);
      expect(items[1].label, 'Due in 6 days');
      expect(items[1].urgency, RenewalUrgency.soon);
      // 12 Oct 2026 -> 1 Jan 2027: 19 (rest of Oct) + 30 (Nov) + 31 (Dec) + 1 = 81.
      expect(items[2].daysLeft, 81);
      expect(items[2].urgency, RenewalUrgency.later);
      expect(items[1].dueDate, DateTime.utc(2026, 10, 18));
    });

    test('withinDays and includeOverdue filter the list', () {
      final List<NoteCard> cards = <NoteCard>[
        paper('overdue', DateTime.utc(2026, 10, 9)),
        paper('soon', DateTime.utc(2026, 10, 18)),
        paper('later', DateTime.utc(2027, 1, 1)),
      ];
      expect(
        RenewalsLogic.upcoming(cards, today, withinDays: 30)
            .map((RenewalItem i) => i.card.id),
        <String>['overdue', 'soon'],
      );
      expect(
        RenewalsLogic.upcoming(cards, today, withinDays: 30, includeOverdue: false)
            .map((RenewalItem i) => i.card.id),
        <String>['soon'],
      );
    });

    test('same-day items are ordered by id so the list is stable', () {
      final List<RenewalItem> items = RenewalsLogic.upcoming(<NoteCard>[
        paper('b', DateTime.utc(2026, 10, 18)),
        paper('a', DateTime.utc(2026, 10, 18)),
      ], today);
      expect(items.map((RenewalItem i) => i.card.id), <String>['a', 'b']);
    });
  });

  group('folders', () {
    test('the folder list comes from AppConfig', () {
      expect(RenewalsLogic.folders, AppConfig.paperFolders);
      expect(RenewalsLogic.folders,
          <String>['Insurance', 'Vehicle', 'Warranties', 'Bills', 'Other']);
    });

    test('normalizeFolder is case-insensitive and falls back to Other', () {
      expect(RenewalsLogic.normalizeFolder('insurance'), 'Insurance');
      expect(RenewalsLogic.normalizeFolder(' Bills '), 'Bills');
      expect(RenewalsLogic.normalizeFolder('Pets'), 'Other');
      expect(RenewalsLogic.normalizeFolder(null), 'Other');
    });

    test('groupByFolder keeps every folder, in order', () {
      final List<RenewalItem> items = RenewalsLogic.upcoming(<NoteCard>[
        paper('car', DateTime.utc(2026, 11, 1), folder: 'Vehicle'),
        paper('home', DateTime.utc(2026, 12, 1), folder: 'Insurance'),
        paper('misc', DateTime.utc(2026, 12, 5)),
        paper('car2', DateTime.utc(2027, 1, 1), folder: 'vehicle'),
      ], today);
      final Map<String, List<RenewalItem>> grouped =
          RenewalsLogic.groupByFolder(items);
      expect(grouped.keys.toList(), AppConfig.paperFolders);
      expect(grouped['Vehicle']!.map((RenewalItem i) => i.card.id),
          <String>['car', 'car2']);
      expect(grouped['Insurance']!.single.card.id, 'home');
      expect(grouped['Other']!.single.card.id, 'misc');
      expect(grouped['Bills'], isEmpty);
      expect(grouped['Warranties'], isEmpty);
    });
  });
}
