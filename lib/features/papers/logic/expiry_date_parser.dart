/// Finds the most likely expiry / due / valid-until date in OCR text. Pure
/// Dart.
///
/// Recognised date shapes (numeric forms are always day-first, as in India):
/// `18/10/2026`, `18-10-2026`, `18.10.2026`, `18/10/26`, `18 Oct 2026`,
/// `18th October, 2026`, `October 18, 2026`, `2026-10-18`.
///
/// A date is only returned when it is tied to an expiry keyword (see
/// below) or is the end date of a policy period ("from X to Y"); otherwise
/// the result is null, because guessing would be worse than asking the user.
///
/// Keywords: expiry / expires / expiration / expiry date, valid
/// till|until|upto|thru|through|to, due date / due on / due, renewal / renews
/// / renew by / next due, exp. The date must follow the keyword closely (same
/// line, or the next line). When several dates qualify the strongest keyword
/// wins, then the closest, then the later date.
class ExpiryDateParser {
  ExpiryDateParser._();

  static const String _months =
      'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|'
      'aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|'
      'dec(?:ember)?';

  // Groups: 1 day, 2 month name, 3 year.
  static final RegExp _dayMonthName = RegExp(
    '(?<!\\d)(\\d{1,2})(?:st|nd|rd|th)?[\\s\\-/.,]*($_months)\\b\\.?'
    '[\\s\\-/.,]*(\\d{4}|\\d{2})(?!\\d)',
    caseSensitive: false,
  );

  // Groups: 1 month name, 2 day, 3 year.
  static final RegExp _monthNameFirst = RegExp(
    '\\b($_months)\\b\\.?[\\s\\-/.]*(\\d{1,2})(?:st|nd|rd|th)?,?[\\s\\-/.]*'
    '(\\d{4})(?!\\d)',
    caseSensitive: false,
  );

  // Groups: 1 year, 2 month, 3 day.
  static final RegExp _iso = RegExp(
    r'(?<![\d/\-.])(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)',
  );

  // Groups: 1 day, 2 month, 3 year (2 or 4 digits).
  static final RegExp _numeric = RegExp(
    r'(?<![\d/\-.])(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})(?!\d)',
  );

  static final List<_Keyword> _keywords = <_Keyword>[
    _Keyword(
      RegExp(
        r'date\s+of\s+expiry|expiry\s+date|expiration\s+date|expires?\s+on|'
        r'expires?|expiry|expiration|exp\.?\s+date|'
        r'valid\s+(?:till|until|upto|up\s+to|thru|through|to)|'
        r'due\s+date|due\s+on|renewal\s+date|renewal\s+due|renews?\s+on|'
        r'renew\s+by|next\s+due|renewal',
        caseSensitive: false,
      ),
      10,
    ),
    _Keyword(RegExp(r'\bexp\b\.?', caseSensitive: false), 9),
    _Keyword(RegExp(r'\bdue\b', caseSensitive: false), 5),
  ];

  static final RegExp _rangeSeparator = RegExp(
    r'^\s*(?:to|till|until|upto|up\s+to|-|–|—)\s*$',
    caseSensitive: false,
  );

  static final RegExp _periodWord = RegExp(
    r'period|from|valid|policy|cover|tenure|term',
    caseSensitive: false,
  );

  /// Returns the most likely expiry date as `DateTime.utc(year, month, day)`,
  /// or null when no date is confidently tied to an expiry keyword.
  static DateTime? parse(String text) {
    if (text.trim().isEmpty) {
      return null;
    }
    final List<_Candidate> candidates = _findCandidates(text);
    if (candidates.isEmpty) {
      return null;
    }

    _Scored? best;
    for (int i = 0; i < candidates.length; i++) {
      final _Scored? scored = _score(text, candidates, i);
      if (scored == null) {
        continue;
      }
      if (best == null || _isBetter(scored, best)) {
        best = scored;
      }
    }
    return best?.candidate.date;
  }

  static bool _isBetter(_Scored a, _Scored b) {
    if (a.strength != b.strength) {
      return a.strength > b.strength;
    }
    if (a.gap != b.gap) {
      return a.gap < b.gap;
    }
    return a.candidate.date.isAfter(b.candidate.date);
  }

  static _Scored? _score(String text, List<_Candidate> all, int index) {
    final _Candidate c = all[index];
    int strength = 0;
    int gap = 1 << 20;

    // 1. A keyword just before the date.
    final int windowStart = c.start > 80 ? c.start - 80 : 0;
    final String window = text.substring(windowStart, c.start);
    for (final _Keyword k in _keywords) {
      for (final RegExpMatch m in k.pattern.allMatches(window)) {
        final String between = window.substring(m.end);
        if (between.length > 30 || '\n'.allMatches(between).length > 1) {
          continue;
        }
        final int betweenStart = windowStart + m.end;
        bool blocked = false;
        for (final _Candidate other in all) {
          if (other.start >= betweenStart && other.end <= c.start) {
            blocked = true;
            break;
          }
        }
        if (blocked) {
          continue;
        }
        if (k.strength > strength ||
            (k.strength == strength && between.length < gap)) {
          strength = k.strength;
          gap = between.length;
        }
      }
    }

    // 2. The end date of a "from X to Y" policy period.
    if (index > 0) {
      final _Candidate previous = all[index - 1];
      final String link = text.substring(previous.end, c.start);
      if (_rangeSeparator.hasMatch(link)) {
        final int from = previous.start > 60 ? previous.start - 60 : 0;
        final String before = text.substring(from, previous.start);
        if (_periodWord.hasMatch(before) && 9 > strength) {
          strength = 9;
          gap = link.length;
        }
      }
    }

    if (strength == 0) {
      return null;
    }
    return _Scored(c, strength, gap);
  }

  static List<_Candidate> _findCandidates(String text) {
    final List<_Candidate> found = <_Candidate>[];

    void add(RegExpMatch m, int? year, int? month, int? day) {
      final DateTime? date = _build(year, month, day);
      if (date == null) {
        return;
      }
      for (final _Candidate c in found) {
        if (m.start < c.end && c.start < m.end) {
          return;
        }
      }
      found.add(_Candidate(m.start, m.end, date));
    }

    for (final RegExpMatch m in _dayMonthName.allMatches(text)) {
      add(m, _year(m.group(3)!), _monthNumber(m.group(2)!), int.parse(m.group(1)!));
    }
    for (final RegExpMatch m in _monthNameFirst.allMatches(text)) {
      add(m, _year(m.group(3)!), _monthNumber(m.group(1)!), int.parse(m.group(2)!));
    }
    for (final RegExpMatch m in _iso.allMatches(text)) {
      add(m, int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    }
    for (final RegExpMatch m in _numeric.allMatches(text)) {
      add(m, _year(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
    }
    found.sort((_Candidate a, _Candidate b) => a.start.compareTo(b.start));
    return found;
  }

  static int _year(String digits) {
    final int value = int.parse(digits);
    return digits.length == 2 ? 2000 + value : value;
  }

  static int _monthNumber(String name) {
    const List<String> names = <String>[
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec', //
    ];
    return names.indexOf(name.substring(0, 3).toLowerCase()) + 1;
  }

  static DateTime? _build(int? year, int? month, int? day) {
    if (year == null || month == null || day == null) {
      return null;
    }
    if (year < 1990 || year > 2100 || month < 1 || month > 12 || day < 1) {
      return null;
    }
    final DateTime date = DateTime.utc(year, month, day);
    if (date.month != month || date.day != day) {
      return null; // e.g. 31/02 rolled over into March
    }
    return date;
  }
}

class _Keyword {
  const _Keyword(this.pattern, this.strength);
  final RegExp pattern;
  final int strength;
}

class _Candidate {
  const _Candidate(this.start, this.end, this.date);
  final int start;
  final int end;
  final DateTime date;
}

class _Scored {
  const _Scored(this.candidate, this.strength, this.gap);
  final _Candidate candidate;
  final int strength;
  final int gap;
}
