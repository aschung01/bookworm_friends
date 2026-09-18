// The derived reads over `reading_days`.
//
// The pure arithmetic is pinned in `streak_test.dart` and `reading_date_test.dart`.
// What this file is for is the **wiring** — specifically that the three surfaces that
// ask "what day is it?" get one answer.
//
// That is the failure mode worth a file of its own. The chip, the sheet's checkbox and
// the Library Card's tile all depend on `readingDate(DateTime.now())`, and reading the
// clock separately in three widgets is exactly how they come to disagree across the
// 4am rollover — one of them says the streak is 12 and another says 11, for ten
// minutes a night, and nothing reproduces it in daylight. So the clock is read in these
// providers and nowhere downstream.
//
// The other property here is that `currentReadingRun` is fed a value that has already
// been through the rollover **once**. Applying it twice shifts every day in the set
// back by one, and `readingDate` of a date-only midnight is the day *before* it — so
// the mistake is silent and consistent, which is the worst kind.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';

class _FakeReadingDays extends ReadingDaysNotifier {
  _FakeReadingDays(this.days);

  final Set<DateTime> days;

  @override
  Future<Set<DateTime>> build() async => days;
}

Future<ProviderContainer> _container(Set<DateTime> days) async {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      readingDaysProvider.overrideWith(() => _FakeReadingDays(days)),
    ],
  );
  addTearDown(container.dispose);
  // Subscribed so the autoDispose chain stays alive for the length of the test.
  addTearDown(container.listen(readingDaysProvider, (_, _) {}).close);
  await container.read(readingDaysProvider.future);
  return container;
}

Set<DateTime> _run(int length, {required DateTime endingOn}) => {
  for (var back = 0; back < length; back++)
    DateTime(endingOn.year, endingOn.month, endingOn.day - back),
};

void main() {
  final today = readingDate(DateTime.now());
  final yesterday = DateTime(today.year, today.month, today.day - 1);

  group('before anything has loaded', () {
    test('every derived read answers 0 or false rather than throwing', () {
      // The first frame of a cold start. A chip that threw here would take the
      // library bar with it.
      final container = ProviderContainer(
        overrides: [currentUserIdProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);

      expect(container.read(readTodayProvider), isFalse);
      expect(container.read(currentStreakProvider), 0);
      expect(container.read(longestStreakProvider), 0);
    });
  });

  group('readTodayProvider', () {
    test('Given today is in the set, Then it is true', () async {
      final container = await _container({today});
      expect(container.read(readTodayProvider), isTrue);
    });

    test('Given only yesterday, Then today is still open', () async {
      final container = await _container({yesterday});
      expect(container.read(readTodayProvider), isFalse);
    });

    test('Given an empty ledger, Then today is open', () async {
      final container = await _container(const {});
      expect(container.read(readTodayProvider), isFalse);
    });
  });

  group('currentStreakProvider', () {
    test('counts a run ending today', () async {
      final container = await _container(_run(12, endingOn: today));
      expect(container.read(currentStreakProvider), 12);
    });

    test('Given a run ending yesterday, Then it is still current', () async {
      // Today being unstamped means the day is *open*, not that the streak is
      // broken. Without this every streak in the app reads 0 each morning and jumps
      // back at bedtime, which makes the number a threat rather than encouragement.
      final container = await _container(_run(12, endingOn: yesterday));
      expect(container.read(currentStreakProvider), 12);
    });

    test('Given a run that ended two days ago, Then it is over', () async {
      final twoDaysAgo = DateTime(today.year, today.month, today.day - 2);
      final container = await _container(_run(12, endingOn: twoDaysAgo));
      expect(container.read(currentStreakProvider), 0);
    });

    test(
      'Given a run ending today, Then the rollover was applied exactly once',
      () async {
        // If `readingDate` were applied a second time inside the derivation, the run
        // would be measured from the day before today and come back one short. A run
        // of 1 is the case that exposes it: it would read 0.
        final container = await _container({today});
        expect(container.read(currentStreakProvider), 1);
      },
    );
  });

  group('longestStreakProvider', () {
    test('Given two runs, Then it is the longest and not the latest', () async {
      // The record is a statement about the reader, and the only figure that
      // survives the missed night that resets everything else.
      final old = DateTime(today.year, today.month, today.day - 30);
      final container = await _container({
        ..._run(9, endingOn: old),
        ..._run(3, endingOn: today),
      });

      expect(container.read(currentStreakProvider), 3);
      expect(container.read(longestStreakProvider), 9);
    });

    test('Given an empty ledger, Then it is 0 rather than absent', () async {
      // Unlike the Library Card's tiles, "no runs yet" and "a run of zero" are the
      // same fact here, so there is no absent case to carry. The *tile* is what
      // omits itself.
      final container = await _container(const {});
      expect(container.read(longestStreakProvider), 0);
    });
  });

  group('the three surfaces agree', () {
    test('a run ending today is both current and recorded', () async {
      // One clock read, in the providers, so a chip and a tile cannot land on
      // different sides of the 4am boundary.
      final container = await _container(_run(5, endingOn: today));
      expect(container.read(readTodayProvider), isTrue);
      expect(container.read(currentStreakProvider), 5);
      expect(container.read(longestStreakProvider), 5);
    });

    test('a run ending yesterday is current but not recorded', () async {
      final container = await _container(_run(5, endingOn: yesterday));
      expect(container.read(readTodayProvider), isFalse);
      expect(container.read(currentStreakProvider), 5);
    });
  });

  group('the window', () {
    test('is a ceiling nobody is near, not a page', () async {
      // A run longer than this would be under-reported. 400 days is over a year of
      // unbroken nightly reading, and the oldest reading book in this database was
      // started 1205 days ago and never touched again.
      expect(kReadingDaysWindow, greaterThan(365));
    });
  });
}
