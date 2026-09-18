// Tests for the reading day's 4am rollover.
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
// `DateTime` reproduces the reader's clock exactly, whatever zone this machine is
// in. That is also what the DST cases below assert — not that some zone's
// transition is handled, but that **there is no such thing as a special day**, which
// is precisely what an elapsed-time `Duration` subtraction would get wrong on one
// morning a year.
//
// The two timezone-change cases pin down a documented *loss*, not a fix. Crossing
// the date line can move a reader's day backwards or skip one, and this file states
// that in assertions so that nobody later "repairs" it and quietly invents a
// timezone the schema does not have.

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
      'Given midnight, When the reading date is taken, Then it is the evening before',
      () {
        expect(readingDate(DateTime(2026, 3, 13)), DateTime(2026, 3, 12));
      },
    );

    test(
      'Given 00:30, When the reading date is taken, Then it is the evening before',
      () {
        // The case the rollover exists for: a chapter finished at half past midnight
        // is tonight's reading, and must not cost the run it just extended.
        expect(
          readingDate(DateTime(2026, 3, 13, 0, 30)),
          DateTime(2026, 3, 12),
        );
      },
    );

    test(
      'Given 03:59, When the reading date is taken, Then it is still the evening before',
      () {
        expect(
          readingDate(DateTime(2026, 3, 13, 3, 59)),
          DateTime(2026, 3, 12),
        );
      },
    );

    test(
      'Given 04:00, When the reading date is taken, Then the day has turned over',
      () {
        // The boundary itself, and the pair above is the whole of it: one minute
        // apart, two different days, and 04:00 belongs to the new one.
        expect(readingDate(DateTime(2026, 3, 13, 4)), DateTime(2026, 3, 13));
      },
    );

    test(
      'Given 04:00 and 03:59 on the same morning, When both are taken, Then they differ by exactly one day',
      () {
        final before = readingDate(DateTime(2026, 3, 13, 3, 59, 59, 999));
        final after = readingDate(DateTime(2026, 3, 13, 4));

        expect(after.difference(before).inDays, 1);
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
      'Given two moments on the same reading day, When both are taken, Then they are the same map key',
      () {
        // The property the derivation depends on: `DateTime` equality is equality of
        // instants, so a `Set<DateTime>` of days only works if every day came
        // through here.
        final evening = readingDate(DateTime(2026, 7, 4, 21, 15));
        final smallHours = readingDate(DateTime(2026, 7, 5, 2, 5));

        expect(smallHours, evening);
        expect(smallHours.hashCode, evening.hashCode);
        expect({evening, smallHours}, hasLength(1));
      },
    );

    test(
      'Given 00:30 on New Year\'s Day, When the reading date is taken, Then it rolls back across the year',
      () {
        expect(
          readingDate(DateTime(2027, 1, 1, 0, 30)),
          DateTime(2026, 12, 31),
        );
      },
    );

    test(
      'Given 01:00 on the first of March, When the reading date is taken, Then it rolls back onto the leap day',
      () {
        expect(readingDate(DateTime(2028, 3, 1, 1)), DateTime(2028, 2, 29));
      },
    );

    test(
      'Given the spring-forward morning, When the boundary is crossed, Then the rule is unchanged',
      () {
        // 2026-03-08 is the US spring-forward date, and 2026-03-29 the EU one. The
        // point is that neither is special: the rollover is a wall-clock rule, so
        // the day that is 23 hours long files its moments exactly like any other.
        // Subtracting four *elapsed* hours would fail this — 04:00 on a
        // spring-forward morning is 23:00 the previous evening in elapsed terms.
        expect(readingDate(DateTime(2026, 3, 8, 3, 59)), DateTime(2026, 3, 7));
        expect(readingDate(DateTime(2026, 3, 8, 4)), DateTime(2026, 3, 8));
        expect(
          readingDate(DateTime(2026, 3, 29, 3, 59)),
          DateTime(2026, 3, 28),
        );
        expect(readingDate(DateTime(2026, 3, 29, 4)), DateTime(2026, 3, 29));
      },
    );

    test(
      'Given the 25-hour fall-back night, When each hour is read, Then all of it is one reading day',
      () {
        // 2026-11-01 falls back at 02:00 in the US, so 01:30 occurs twice. Both
        // passes are the same wall clock and therefore the same reading day — a
        // reader cannot bank two days by sitting up through the repeat, and the
        // longer night does not shift the 04:00 boundary either.
        final night = [
          DateTime(2026, 10, 31, 22, 15),
          DateTime(2026, 11, 1, 0, 30),
          DateTime(2026, 11, 1, 1, 30),
          DateTime(2026, 11, 1, 2, 30),
          DateTime(2026, 11, 1, 3, 59),
        ].map(readingDate).toSet();

        expect(night, {DateTime(2026, 10, 31)});
        expect(readingDate(DateTime(2026, 11, 1, 4)), DateTime(2026, 11, 1));
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
        // The evening warning names 4am in words. If this ever changes, the copy
        // changes with it, and this assertion is the reminder.
        expect(kReadingDayRolloverHour, 4);
      },
    );
  });
}
