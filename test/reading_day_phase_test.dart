// Tests for the reading day's evening warning — the phase, and the boundary a clock-driven
// consumer waits on.
//
// A pure unit test with no clock in it, for the reason `reading_date_test.dart` states: both
// functions take the moment as an argument, so every case below is a wall-clock reading — the
// exact thing a phone would show the reader — and the assertions are about which of three
// things the app would then say.
//
// **What these cases are really guarding.** The phase is three lines of arithmetic and could
// not sensibly be got wrong; the boundary can be, in two ways that both fail quietly:
//
//  1. Returning a boundary that is *not strictly after* the moment handed in. A `Timer`
//     waiting out a zero or negative gap fires immediately, invalidates its provider, rebuilds
//     it, and schedules the same zero gap again — a spin that presents as heat and battery
//     rather than as a wrong answer on screen. The sweep at the bottom exists for that alone.
//  2. Returning today's warning hour again once the warning hour has passed, which is the same
//     spin arrived at from the other side.
//
// So the interesting cases are 21:00 exactly, and the two ends of the calendar.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/reading_date.dart';

void main() {
  group('readingDayPhase', () {
    // A day that is in the log, and the same day's evening. Recorded outranks late: once the
    // night is in there is nothing left to warn about, and this is the assertion that keeps a
    // later refactor from checking the hour first.
    test(
      'Given today is recorded, When it is 22:00, Then the phase is recorded rather than late',
      () {
        final now = DateTime(2026, 9, 22, 22);
        expect(
          readingDayPhase(now, [DateTime(2026, 9, 22)]),
          ReadingDayPhase.recorded,
        );
      },
    );

    test(
      'Given an unrecorded day, When it is 20:59, Then the day is open and not yet late',
      () {
        expect(
          readingDayPhase(DateTime(2026, 9, 22, 20, 59), const <DateTime>[]),
          ReadingDayPhase.open,
        );
      },
    );

    // The boundary itself, one minute apart. 21:00 is in the warning, not before it.
    test(
      'Given an unrecorded day, When it is 21:00, Then the day has gone late',
      () {
        expect(
          readingDayPhase(DateTime(2026, 9, 22, 21), const <DateTime>[]),
          ReadingDayPhase.openLate,
        );
      },
    );

    test(
      'Given an unrecorded day, When it is 23:59, Then the day is still late rather than lost',
      () {
        expect(
          readingDayPhase(DateTime(2026, 9, 22, 23, 59), const <DateTime>[]),
          ReadingDayPhase.openLate,
        );
      },
    );

    // Midnight is the rollover, so this is a *new* day with nothing recorded on it — and a new
    // day is calm. The evening it follows being unrecorded is not this function's business.
    test(
      'Given last night was missed, When midnight passes, Then the new day reads open rather than late',
      () {
        expect(
          readingDayPhase(DateTime(2026, 9, 23), const <DateTime>[]),
          ReadingDayPhase.open,
        );
      },
    );

    // The first night. Of 137 profiles in production exactly one has a reading day at all, so
    // the empty log is the common case rather than the edge, and the warning has to reach it.
    test(
      'Given nothing has ever been recorded, When it is 21:30, Then the day still goes late',
      () {
        expect(
          readingDayPhase(DateTime(2026, 9, 22, 21, 30), const <DateTime>[]),
          ReadingDayPhase.openLate,
        );
      },
    );

    test(
      'Given yesterday is recorded but today is not, When it is 21:30, Then the day goes late',
      () {
        expect(
          readingDayPhase(DateTime(2026, 9, 22, 21, 30), [
            DateTime(2026, 9, 21),
          ]),
          ReadingDayPhase.openLate,
        );
      },
    );
  });

  group('nextReadingPhaseBoundary', () {
    test(
      'Given the morning, When the next boundary is taken, Then it is this evening at the warning hour',
      () {
        expect(
          nextReadingPhaseBoundary(DateTime(2026, 9, 22, 9)),
          DateTime(2026, 9, 22, 21),
        );
      },
    );

    test(
      'Given one second before the warning hour, When the next boundary is taken, Then it is the warning hour',
      () {
        expect(
          nextReadingPhaseBoundary(DateTime(2026, 9, 22, 20, 59, 59)),
          DateTime(2026, 9, 22, 21),
        );
      },
    );

    // The case that would spin. At 21:00 the phase has *already* changed, so the next thing to
    // wait for is the rollover — not the boundary just crossed.
    test(
      'Given the warning hour exactly, When the next boundary is taken, Then it is the rollover and not itself',
      () {
        expect(
          nextReadingPhaseBoundary(DateTime(2026, 9, 22, 21)),
          DateTime(2026, 9, 23),
        );
      },
    );

    test(
      'Given late evening, When the next boundary is taken, Then it is the coming midnight',
      () {
        expect(
          nextReadingPhaseBoundary(DateTime(2026, 9, 22, 23, 59)),
          DateTime(2026, 9, 23),
        );
      },
    );

    // Calendar arithmetic by `DateTime` rather than by hand, asserted at both ends so nobody
    // later "simplifies" it into `day + 1` on a raw field.
    test(
      'Given the last evening of a month, When the next boundary is taken, Then it is the first of the next',
      () {
        expect(
          nextReadingPhaseBoundary(DateTime(2026, 9, 30, 22)),
          DateTime(2026, 10, 1),
        );
      },
    );

    test(
      'Given new year\'s eve, When the next boundary is taken, Then it is the first of January',
      () {
        expect(
          nextReadingPhaseBoundary(DateTime(2026, 12, 31, 22)),
          DateTime(2027, 1, 1),
        );
      },
    );

    // The spin guard, swept across a whole day at minute resolution. A boundary equal to or
    // behind the moment handed in is a `Timer` with a non-positive duration, which fires at
    // once and reschedules itself forever.
    test(
      'Given any minute of a day, When the next boundary is taken, Then it is strictly later',
      () {
        final day = DateTime(2026, 9, 22);
        for (var minute = 0; minute < 24 * 60; minute++) {
          final now = day.add(Duration(minutes: minute));
          final boundary = nextReadingPhaseBoundary(now);
          expect(
            boundary.isAfter(now),
            isTrue,
            reason: 'boundary $boundary is not after $now',
          );
        }
      },
    );

    // And that the two are consistent with each other: crossing the boundary is exactly when
    // the answer changes, so the phase at the boundary must differ from the phase just before
    // it. This is the assertion that would catch the constant being changed in one place.
    test(
      'Given the boundary, When it is crossed, Then the phase either side of it differs',
      () {
        final before = DateTime(2026, 9, 22, 20, 59);
        final boundary = nextReadingPhaseBoundary(before);
        expect(
          readingDayPhase(before, const <DateTime>[]),
          isNot(readingDayPhase(boundary, const <DateTime>[])),
        );
      },
    );
  });

  test(
    'Given the warning constant, When it is read, Then it is the hour the copy is written for',
    () {
      // `streakTodayLate` says "Nearly midnight", which is only true of an hour close to the
      // rollover. Moving this constant means rewriting that string, and this assertion is the
      // reminder — the same role the rollover's own case plays in `reading_date_test.dart`.
      expect(kReadingDayWarningHour, 21);
    },
  );
}
