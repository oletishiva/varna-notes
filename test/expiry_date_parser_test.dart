import 'package:flutter_test/flutter_test.dart';
import 'package:varna/features/papers/logic/expiry_date_parser.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

void main() {
  group('date formats (day-first for numbers)', () {
    test('slashes', () {
      // "18/10/2026" is day 18, month 10, year 2026 -> 18 Oct 2026.
      expect(ExpiryDateParser.parse('Policy expires on 18/10/2026'), d(2026, 10, 18));
    });

    test('dashes', () {
      // "18-10-2026" -> 18 Oct 2026.
      expect(ExpiryDateParser.parse('Expiry Date: 18-10-2026'), d(2026, 10, 18));
    });

    test('dots', () {
      // "18.10.2026" -> 18 Oct 2026.
      expect(ExpiryDateParser.parse('Valid till 18.10.2026'), d(2026, 10, 18));
    });

    test('two-digit year is 20xx', () {
      // "18/10/26" -> 18 Oct 2026.
      expect(ExpiryDateParser.parse('Valid till 18/10/26'), d(2026, 10, 18));
    });

    test('day, abbreviated month name, year', () {
      // "18 Oct 2026" -> 18 Oct 2026.
      expect(ExpiryDateParser.parse('Valid till 18 Oct 2026'), d(2026, 10, 18));
    });

    test('day with ordinal and full month name', () {
      // "5th November 2026" -> 5 Nov 2026.
      expect(ExpiryDateParser.parse('Due Date: 5th November 2026'), d(2026, 11, 5));
    });

    test('hyphenated month name', () {
      // "18-Oct-2026" -> 18 Oct 2026.
      expect(ExpiryDateParser.parse('Expires 18-Oct-2026'), d(2026, 10, 18));
    });

    test('month name first with comma', () {
      // "October 18, 2026" -> 18 Oct 2026.
      expect(ExpiryDateParser.parse('Renewal due October 18, 2026'), d(2026, 10, 18));
    });

    test('ISO year first', () {
      // "2026-10-18" is year 2026, month 10, day 18.
      expect(ExpiryDateParser.parse('Valid until 2026-10-18'), d(2026, 10, 18));
    });

    test('is case-insensitive', () {
      // Upper-case keyword and month: still 18 Oct 2026.
      expect(ExpiryDateParser.parse('EXPIRY DATE 18 OCT 2026'), d(2026, 10, 18));
    });

    test('numbers are day-first, not month-first', () {
      // "03/04/2027" is 3 April 2027 in India, not 4 March.
      expect(ExpiryDateParser.parse('Expiry: 03/04/2027'), d(2027, 4, 3));
    });

    test('a month-first US date with month 18 is rejected', () {
      // "10/18/2026" would be day 10, month 18 -> invalid -> nothing found.
      expect(ExpiryDateParser.parse('Expiry 10/18/2026'), isNull);
    });

    test('impossible calendar dates are rejected', () {
      // 31 February does not exist.
      expect(ExpiryDateParser.parse('Expiry 31/02/2026'), isNull);
      // 2026 is not a leap year, so 29 Feb 2026 does not exist either.
      expect(ExpiryDateParser.parse('Expiry 29/02/2026'), isNull);
    });

    test('a leap day is accepted in a leap year', () {
      // 2028 is a leap year -> 29 Feb 2028 is valid.
      expect(ExpiryDateParser.parse('Expiry 29/02/2028'), d(2028, 2, 29));
    });
  });

  group('choosing among several dates', () {
    test('the keyword date wins over an issue date', () {
      // "Issued on 01/01/2024" has no expiry keyword; "Valid upto 31/12/2029"
      // does -> 31 Dec 2029.
      expect(
        ExpiryDateParser.parse('Issued on 01/01/2024\nValid upto 31/12/2029'),
        d(2029, 12, 31),
      );
    });

    test('policy period uses the end date', () {
      // "Policy Period: 01/04/2025 to 31/03/2026" -> the end date, 31 Mar 2026.
      expect(
        ExpiryDateParser.parse('Policy Period: 01/04/2025 to 31/03/2026'),
        d(2026, 3, 31),
      );
    });

    test('"from ... to ..." uses the end date', () {
      // "Valid from 01-01-2026 to 31-12-2026" -> 31 Dec 2026.
      expect(
        ExpiryDateParser.parse('Valid from 01-01-2026 to 31-12-2026'),
        d(2026, 12, 31),
      );
    });

    test('a keyword on the previous line still counts', () {
      // "Expiry Date" then the date on the next line -> 18 Oct 2026.
      expect(ExpiryDateParser.parse('Expiry Date\n18/10/2026'), d(2026, 10, 18));
    });

    test('a keyword two lines above does not count', () {
      // Two line breaks between keyword and date: too far, nothing found.
      expect(ExpiryDateParser.parse('Expiry Date\n\n18/10/2026'), isNull);
    });

    test('equally strong keywords: the later date wins', () {
      // "Renewal Date" 01/01/2026 and "Expiry Date" 01/06/2026 both score
      // the same, so the later one, 1 Jun 2026, is chosen.
      expect(
        ExpiryDateParser.parse(
          'Renewal Date: 01/01/2026\nExpiry Date: 01/06/2026',
        ),
        d(2026, 6, 1),
      );
    });

    test('a strong keyword beats the weak word "due"', () {
      // "due" scores 5, "Expiry" scores 10 -> 31 Dec 2030, not 05 Nov 2026.
      expect(
        ExpiryDateParser.parse('Premium due 05/11/2026 Expiry 31/12/2030'),
        d(2030, 12, 31),
      );
    });

    test('the weak word "due" is enough on its own', () {
      // Only "due" precedes the date -> 05 Nov 2026.
      expect(ExpiryDateParser.parse('Premium due 05/11/2026'), d(2026, 11, 5));
    });

    test('works inside noisy OCR text', () {
      const String text = 'ACME GENERAL INSURANCE\n'
          'Policy No: 123456789\n'
          'Insured: R. KUMAR\n'
          'Premium Rs. 12,450.00\n'
          'Policy Valid Till 14 Jun 2027\n'
          'Thank you for choosing us';
      // The only keyword-linked date is "Valid Till 14 Jun 2027".
      expect(ExpiryDateParser.parse(text), d(2027, 6, 14));
    });
  });

  group('returns null when not confident', () {
    test('empty and blank text', () {
      expect(ExpiryDateParser.parse(''), isNull);
      expect(ExpiryDateParser.parse('   \n '), isNull);
    });

    test('a date with no expiry keyword', () {
      // "Invoice date" is not an expiry keyword.
      expect(ExpiryDateParser.parse('Invoice date 05/06/2025'), isNull);
    });

    test('text without dates', () {
      expect(ExpiryDateParser.parse('Expiry date: see back of card'), isNull);
    });

    test('a keyword too far from the date', () {
      // More than 30 characters between "Expiry" and the date.
      expect(
        ExpiryDateParser.parse(
          'Expiry is explained in the long paragraph below 18/10/2026',
        ),
        isNull,
      );
    });

    test('implausible years are ignored', () {
      expect(ExpiryDateParser.parse('Expiry 18/10/1850'), isNull);
    });

    test('another date between keyword and candidate blocks the link', () {
      // The keyword belongs to 01/01/2026, not to the later 02/02/2026; the
      // later date is only reachable through the first one, so the result is
      // the first date.
      expect(
        ExpiryDateParser.parse('Expiry 01/01/2026 and 02/02/2026'),
        d(2026, 1, 1),
      );
    });
  });
}
