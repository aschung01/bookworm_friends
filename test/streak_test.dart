// Tests for the run lengths derived from a set of reading days.
//
// Pure functions over a `Set<DateTime>`, so there is no query to fake and no widget
// to pump — the same reason `libraryCardStats` is a function. The set is what the
// client already holds after fetching the trailing `reading_days` rows.
//
// What these cases really defend is one distinction the whole feature's tone depends
// on: **an unstamped today is an open day, not a broken run.** A test suite that only
// checked "today is stamped" would pass against an implementation that resets every
// streak in the app at 4am each morning, which is the single most damaging thing this
// number could do. Hence a case for a run ending yesterday, a case for one ending two
// days ago, and a case proving the record outlives the break.
//
// The remaining cases are about arithmetic that only fails months later: the longest
// run must be the maximum rather than the most recent, and walking days must be
// calendar arithmetic, so the long-run case is deliberately laid across two DST
// boundaries, a leap day and a year end.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/streak.dart';

/// The [length] consecutive days ending on [last], newest first.
///
/// Built with calendar arithmetic for the same reason the implementation is: adding
/// durations would drift by an hour at a DST boundary and the fixture would stop
/// describing consecutive days.
Set<DateTime> _runEndingOn(DateTime last, int length) => {
  for (var i = 0; i < length; i++)
    DateTime(last.year, last.month, last.day - i),
};

void main() {
  group('currentReadingRun', () {
    test('Given no history, When the run is derived, Then it is zero', () {
      expect(currentReadingRun({}, DateTime(2026, 9, 12)), 0);
    });

    test('Given only today, When the run is derived, Then it is one day', () {
      final today = DateTime(2026, 9, 12);

      expect(currentReadingRun({today}, today), 1);
    });

    test(
      'Given a run ending yesterday, When the run is derived, Then it still counts',
      () {
        // The load-bearing case. Today is unstamped because the reader has not read
        // *yet* — nothing has been lost, and the chip says so in grey rather than
        // saying zero.
        final today = DateTime(2026, 9, 12);
        final days = _runEndingOn(DateTime(2026, 9, 11), 5);

        expect(currentReadingRun(days, today), 5);
      },
    );

    test(
      'Given a run ending yesterday, When today is stamped, Then the run grows by one',
      () {
        final today = DateTime(2026, 9, 12);
        final days = _runEndingOn(DateTime(2026, 9, 11), 5);

        expect(currentReadingRun(days, today), 5);
        expect(currentReadingRun({...days, today}, today), 6);
      },
    );

    test(
      'Given a run ending two days ago, When the run is derived, Then it is zero',
      () {
        final today = DateTime(2026, 9, 12);
        final days = _runEndingOn(DateTime(2026, 9, 10), 12);

        expect(currentReadingRun(days, today), 0);
      },
    );

    test(
      'Given today stamped after a long gap, When the run is derived, Then it is one day',
      () {
        // Starting over reads as 1, not as a continuation of the abandoned run and
        // not as 0. The reader read today.
        final today = DateTime(2026, 9, 12);
        final days = {..._runEndingOn(DateTime(2026, 4, 3), 40), today};

        expect(currentReadingRun(days, today), 1);
      },
    );

    test(
      'Given a run interrupted by one missed day, When the run is derived, Then only the days since the gap count',
      () {
        // Freezes are deferred, so one missed night severs the thread outright. This
        // is the cost the design accepted, asserted here so that it is a decision
        // rather than a surprise.
        final today = DateTime(2026, 9, 12);
        final days = {
          ..._runEndingOn(today, 3),
          ..._runEndingOn(DateTime(2026, 9, 8), 8),
        };

        expect(currentReadingRun(days, today), 3);
      },
    );

    test(
      'Given days carrying a time component, When the run is derived, Then they still match',
      () {
        // Defensive normalisation, and not hypothetical: `DateTime` keys match as
        // instants, so one caller handing over a timestamp instead of a date would
        // otherwise report zero to a reader with a streak.
        final days = {
          DateTime(2026, 9, 12, 22, 40),
          DateTime(2026, 9, 11, 1, 5),
          DateTime(2026, 9, 10, 12),
        };

        expect(currentReadingRun(days, DateTime(2026, 9, 12, 23, 59)), 3);
      },
    );

    test(
      'Given a run spanning month and year ends, When the run is derived, Then it is unbroken',
      () {
        final today = DateTime(2027, 1, 2);

        expect(currentReadingRun(_runEndingOn(today, 45), today), 45);
      },
    );

    test(
      'Given a year-long run, When the run is derived, Then every day counts',
      () {
        // 400 days ending in April 2027 crosses two DST boundaries, a leap day and a
        // year end. A duration-based walk truncates somewhere in here; calendar
        // arithmetic does not.
        final today = DateTime(2027, 4, 20);

        expect(currentReadingRun(_runEndingOn(today, 400), today), 400);
      },
    );
  });

  group('longestReadingRun', () {
    test('Given no history, When the record is derived, Then it is zero', () {
      expect(longestReadingRun({}), 0);
    });

    test(
      'Given only today, When the record is derived, Then it is one day',
      () {
        expect(longestReadingRun({DateTime(2026, 9, 12)}), 1);
      },
    );

    test(
      'Given a broken run, When the record is derived, Then the history survives',
      () {
        // The pair that matters: the current run is gone, the record is not. Without
        // this the missed night reads as though the reading never happened.
        final today = DateTime(2026, 9, 12);
        final days = _runEndingOn(DateTime(2026, 9, 10), 12);

        expect(currentReadingRun(days, today), 0);
        expect(longestReadingRun(days), 12);
      },
    );

    test(
      'Given two runs, When the record is derived, Then it is the longest and not the latest',
      () {
        final today = DateTime(2026, 9, 12);
        final days = {
          ..._runEndingOn(DateTime(2026, 5, 30), 21),
          ..._runEndingOn(today, 4),
        };

        expect(longestReadingRun(days), 21);
        expect(currentReadingRun(days, today), 4);
      },
    );

    test(
      'Given several runs of different lengths, When the record is derived, Then it is the maximum',
      () {
        final days = {
          ..._runEndingOn(DateTime(2026, 2, 10), 3),
          ..._runEndingOn(DateTime(2026, 4, 18), 17),
          ..._runEndingOn(DateTime(2026, 6, 1), 9),
          ..._runEndingOn(DateTime(2026, 8, 25), 2),
        };

        expect(longestReadingRun(days), 17);
      },
    );

    test(
      'Given adjacent runs separated by one day, When the record is derived, Then they are not merged',
      () {
        // The gap is 2026-09-09. Ten days on one side, four on the other, and the
        // answer must be 10 rather than 14 — the join is what a freeze would buy, and
        // freezes are not built.
        final days = {
          ..._runEndingOn(DateTime(2026, 9, 8), 10),
          ..._runEndingOn(DateTime(2026, 9, 13), 4),
        };

        expect(longestReadingRun(days), 10);
      },
    );

    test(
      'Given days carrying a time component, When the record is derived, Then they still match',
      () {
        final days = {
          DateTime(2026, 9, 12, 22, 40),
          DateTime(2026, 9, 11, 1, 5),
          DateTime(2026, 9, 10, 12),
          // The same day twice, once with a time and once without: normalising has to
          // collapse these, or the record counts a day twice.
          DateTime(2026, 9, 10),
        };

        expect(longestReadingRun(days), 3);
      },
    );

    test(
      'Given a year-long run, When the record is derived, Then it is that run',
      () {
        expect(
          longestReadingRun(_runEndingOn(DateTime(2027, 4, 20), 400)),
          400,
        );
      },
    );
  });
}
