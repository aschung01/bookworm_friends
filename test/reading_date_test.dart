// Tests for the reading day's midnight rollover.
//
// A pure unit test with no clock in it, because `readingDate` takes the moment as an
// argument. Every case below is a wall-clock reading — the exact thing a phone would
// show the reader — and the assertions are about which day that reading is filed
// under, which is the only question the function answers.
//
// **The process's own timezone is not a variable these tests can set.** Dart reads
// the zone once at startup and pure Dart carries no zone database, so there is no
// way to run a case "in New York". The tests are written so that they do not need
// to: the rollover is defined on the local wall clock, so feeding it a local
// `DateTime` reproduces the reader's clock exactly, whatever zone this machine is in.
//
// The two timezone-change cases pin down a documented *loss*, not a fix. Crossing
// the date line can move a reader's day backwards or skip one, and this file states
// that in assertions so that nobody later "repairs" it and quietly invents a
// timezone the schema does not have.
//
// **This file used to carry a DST-boundary suite, back when the rollover was 4am.**
// At a nonzero rollover, a spring-forward or fall-back transition can make an
// elapsed-time subtraction disagree with a wall-clock one — see the comment in
// `readingDate` itself, which still explains why the arithmetic is written the long
// way. At zero the two are identical, so there is nothing left for a DST case to
// catch; it was deleted rather than kept as a test that could never fail. If
// `kReadingDayRolloverHour` is ever made nonzero again, that suite is worth writing
// back in.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/reading_date.dart';

void main() {
  group('readingDate', () {
    test(
      'Given 23:59, When the reading date is taken, Then it is that same evening',
      () {
        expect(
          readingDate(DateTime(2026, 3, 12, 23, 59)),
          DateTime(2026, 3, 12),
        );
      },
    );

    test(
      'Given midnight, When the reading date is taken, Then the day has already turned over',
      () {
        // The boundary itself: one minute apart, either side of midnight, and
        // both land on the day they look like they belong to. This is the case
        // that inverted when the rollover was 4 — midnight used to file under
        // the evening before.
        expect(readingDate(DateTime(2026, 3, 13)), DateTime(2026, 3, 13));
        expect(
          readingDate(DateTime(2026, 3, 12, 23, 59, 59, 999)),
          DateTime(2026, 3, 12),
        );
      },
    );

    test(
      'Given 00:30, When the reading date is taken, Then it already counts for the new day',
      () {
        // The case a 4am rollover existed to protect: a chapter finished at half
        // past midnight used to read as *tonight's* reading. At a midnight
        // rollover it does not, and that is the accepted cost of matching
        // Duolingo's reset rather than the earlier reasoning.
        expect(
          readingDate(DateTime(2026, 3, 13, 0, 30)),
          DateTime(2026, 3, 13),
        );
      },
    );

    test(
      'Given any moment, When the reading date is taken, Then it is local midnight with no time component',
      () {
        final day = readingDate(DateTime(2026, 7, 4, 17, 42, 13, 500, 250));

        expect(day.hour, 0);
        expect(day.minute, 0);
        expect(day.second, 0);
        expect(day.millisecond, 0);
        expect(day.microsecond, 0);
        expect(
          day.isUtc,
          isFalse,
          reason: 'a local date, so it matches what reading_days.day stores',
        );
      },
    );

    test(
      'Given two moments on the same calendar day, When both are taken, Then they are the same map key',
      () {
        // The property the derivation depends on: `DateTime` equality is equality of
        // instants, so a `Set<DateTime>` of days only works if every day came
        // through here.
        final morning = readingDate(DateTime(2026, 7, 4, 8, 5));
        final evening = readingDate(DateTime(2026, 7, 4, 21, 15));

        expect(morning, evening);
        expect(morning.hashCode, evening.hashCode);
        expect({morning, evening}, hasLength(1));
      },
    );

    test(
      'Given 00:30 on New Year\'s Day, When the reading date is taken, Then it is New Year\'s Day',
      () {
        expect(readingDate(DateTime(2027, 1, 1, 0, 30)), DateTime(2027, 1, 1));
      },
    );

    test(
      'Given a UTC instant, When the reading date is taken, Then it is converted to local first',
      () {
        // Timestamps come back from Postgres as UTC. Filing one by its UTC date
        // would put a reader up to a day out from what their own phone recorded.
        final utc = DateTime.utc(2026, 5, 20, 13, 15);

        expect(readingDate(utc), readingDate(utc.toLocal()));
        expect(readingDate(utc).isUtc, isFalse);
      },
    );

    test(
      'Given a flight east across the date line, When two consecutive calls are made, Then the reader loses a day',
      () {
        // Auckland 09:00 lands in Honolulu at 11:00 the previous calendar day. The
        // second call therefore precedes the first: this is not monotonic, and the
        // accepted cost is that a day can be revisited or skipped mid-journey.
        final beforeBoarding = readingDate(DateTime(2026, 6, 10, 9));
        final afterLanding = readingDate(DateTime(2026, 6, 9, 11));

        expect(beforeBoarding, DateTime(2026, 6, 10));
        expect(afterLanding, DateTime(2026, 6, 9));
        expect(afterLanding.isBefore(beforeBoarding), isTrue);
      },
    );

    test(
      'Given a flight west across the date line, When two consecutive calls are made, Then a day is skipped',
      () {
        // The mirror image, and the one that actually costs something: Honolulu
        // 23:00 lands in Auckland with the clock reading two calendar days on, so a
        // run can break with nothing missed. Accepted for the same reason — the fix
        // is a timezone `profiles` does not carry.
        final beforeBoarding = readingDate(DateTime(2026, 6, 9, 23));
        final afterLanding = readingDate(DateTime(2026, 6, 11, 20));

        expect(beforeBoarding, DateTime(2026, 6, 9));
        expect(afterLanding, DateTime(2026, 6, 11));
        expect(afterLanding.difference(beforeBoarding).inDays, 2);
      },
    );

    test(
      'Given the rollover constant, When it is read, Then it is the hour the copy quotes',
      () {
        // The evening warning names "midnight" in words. If this ever changes, the
        // copy changes with it, and this assertion is the reminder.
        expect(kReadingDayRolloverHour, 0);
      },
    );
  });
}
