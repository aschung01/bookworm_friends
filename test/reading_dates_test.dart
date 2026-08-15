// Tests for the reading-date invariant applied on the way to the database.
//
// The pickers stop an inverted start/finish pair being chosen, but they only
// guard new input: re-saving a book that was already stored inverted, or any
// code path that writes dates without a picker, has to be caught here.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/providers/library_provider.dart';

void main() {
  group('clampReadingDates', () {
    test('Given a finish date before the start, Then it is pulled up', () {
      // The state from the bug report: finished 08.09, started 08.10.
      final result = clampReadingDates(
        startDate: DateTime(2026, 8, 10),
        finishDate: DateTime(2026, 8, 9),
      );

      expect(result.startDate, DateTime(2026, 8, 10));
      expect(result.finishDate, DateTime(2026, 8, 10));
    });

    test('Given a valid range, Then both dates are left alone', () {
      final result = clampReadingDates(
        startDate: DateTime(2022, 11, 13),
        finishDate: DateTime(2022, 11, 15),
      );

      expect(result.startDate, DateTime(2022, 11, 13));
      expect(result.finishDate, DateTime(2022, 11, 15));
    });

    test('Given the same day for both, Then neither is changed', () {
      final day = DateTime(2026, 8, 10);
      final result = clampReadingDates(startDate: day, finishDate: day);

      expect(result.startDate, day);
      expect(result.finishDate, day);
    });

    test('Given a later time of day on the finish date, Then it is kept', () {
      // Same calendar day, so this is a valid range even though the raw
      // DateTime values differ.
      final result = clampReadingDates(
        startDate: DateTime(2026, 8, 10, 22, 0),
        finishDate: DateTime(2026, 8, 10, 6, 0),
      );

      expect(result.finishDate, DateTime(2026, 8, 10, 6, 0));
    });

    test('Given a missing date, Then nothing is invented', () {
      final onlyStart = clampReadingDates(startDate: DateTime(2026, 8, 10));
      expect(onlyStart.startDate, DateTime(2026, 8, 10));
      expect(onlyStart.finishDate, isNull);

      final onlyFinish = clampReadingDates(finishDate: DateTime(2026, 8, 10));
      expect(onlyFinish.startDate, isNull);
      expect(onlyFinish.finishDate, DateTime(2026, 8, 10));

      final neither = clampReadingDates();
      expect(neither.startDate, isNull);
      expect(neither.finishDate, isNull);
    });
  });
}
