// The snapshot handed to the iOS home-screen widget, and the two things about it that would
// fail silently.
//
// **This file is the contract, not a formality.** `ios/StreakWidget/StreakSnapshot.swift`
// decodes these exact key names with `JSONDecoder` and every optional field is nullable there,
// so a renamed or dropped key does not throw on either side: the widget simply draws the
// invitation state to a reader who has a live streak, and nothing anywhere says why. A test is
// the only place that mismatch can be caught.
//
// The second thing is `writtenAt` being excluded from equality. It changes on every build, so
// including it would make every snapshot unequal to the last, and `StreakWidgetSync` would call
// `reloadAllTimelines` on every rebuild -- which is how a widget exhausts the refresh budget iOS
// grants it and then stops updating at all. That is a performance bug with no visible symptom
// until the widget goes stale, so it is asserted rather than trusted.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/models/streak_widget_snapshot.dart';

import 'support/home_page_harness.dart';

const StreakWidgetCopy _copy = StreakWidgetCopy(
  dayStreak: 'day streak',
  todayOpen: 'A page is enough. Today counts until midnight.',
  todayLate: 'Nearly midnight. A page is enough.',
  todayDone: 'Today is recorded.',
  nothingYet: 'Record a day and it starts here.',
);

const StreakWidgetLines _lines = StreakWidgetLines(
  dawn: 'Keep it going!',
  morning: "Your book's waiting!",
  afternoon: 'Anything yet?',
  evening: "You said you'd read.",
  late: 'Midnight approaches. So do I.',
  last: 'This is how it ends?',
  none: 'Start a streak!',
);

StreakWidgetSnapshot _snapshot({
  int streak = 12,
  int longestStreak = 31,
  DateTime? lastReadDay,
  bool withBook = false,
}) => StreakWidgetSnapshot(
  streak: streak,
  longestStreak: longestStreak,
  lastReadDay: lastReadDay ?? DateTime(2026, 9, 22),
  book: withBook
      ? testBook('b1', 'reading', title: 'Piranesi', progress: 0.41)
      : null,
  copy: _copy,
  lines: _lines,
);

void main() {
  group('the wire format', () {
    test(
      'Given a snapshot, When it is encoded, Then it carries the keys Swift decodes',
      () {
        final json = jsonDecode(_snapshot().encode()) as Map<String, Object?>;

        expect(json['v'], StreakWidgetSnapshot.version);
        expect(json['streak'], 12);
        expect(json['longestStreak'], 31);
        expect(json['lastReadDay'], '2026-09-22');
        expect((json['copy']! as Map)['dayStreak'], 'day streak');
      },
    );

    // The whole reason Swift can be correct days after the app last ran: it derives the phase
    // from these two numbers plus the date it is drawing, so they have to travel.
    test(
      'Given the hour constants, When a snapshot is encoded, Then both travel with it',
      () {
        final json = jsonDecode(_snapshot().encode()) as Map<String, Object?>;

        expect(json['rolloverHour'], kReadingDayRolloverHour);
        expect(json['warningHour'], kReadingDayWarningHour);
      },
    );

    // A date-only local value, formatted by hand. `toIso8601String` would send a time component
    // and a `Z`, and the Swift side parses exactly three integers.
    test(
      'Given a day, When it is written, Then it is yyyy-MM-dd with no time and no zone',
      () {
        final json =
            jsonDecode(_snapshot(lastReadDay: DateTime(2026, 1, 5)).encode())
                as Map<String, Object?>;

        expect(json['lastReadDay'], '2026-01-05');
      },
    );

    test(
      'Given nothing recorded, When a snapshot is encoded, Then the day is null rather than absent',
      () {
        final snapshot = StreakWidgetSnapshot(
          streak: 0,
          longestStreak: 0,
          lastReadDay: null,
          copy: _copy,
          lines: _lines,
        );
        final json = jsonDecode(snapshot.encode()) as Map<String, Object?>;

        expect(json.containsKey('lastReadDay'), isTrue);
        expect(json['lastReadDay'], isNull);
      },
    );

    test(
      'Given a book, When it is encoded, Then the jacket is six opaque hex digits',
      () {
        final json =
            jsonDecode(_snapshot(withBook: true).encode())
                as Map<String, Object?>;
        final book = json['book']! as Map<String, Object?>;

        expect(book['title'], 'Piranesi');
        expect(book['progress'], 0.41);
        final colour = book['coverColor'];
        if (colour != null) {
          expect(colour, matches(r'^#[0-9A-F]{6}$'));
        }
      },
    );

    test(
      'Given no reading book, When a snapshot is encoded, Then the book is null',
      () {
        final json = jsonDecode(_snapshot().encode()) as Map<String, Object?>;
        expect(json['book'], isNull);
      },
    );

    // The jacket thumbnail's filename. Swift resolves it inside the App Group's `covers/`
    // directory and derives nothing itself, so a rename here is a widget that silently draws the
    // `coverColor` rectangle forever -- the fallback working is exactly what would hide it.
    test(
      'Given a book, When it is encoded, Then the cover filename is keyed on the book id',
      () {
        final json =
            jsonDecode(_snapshot(withBook: true).encode())
                as Map<String, Object?>;
        final book = json['book']! as Map<String, Object?>;

        expect(book['coverFile'], 'cover-b1.png');
        expect(book['coverFile'], StreakWidgetSnapshot.coverFileName('b1'));
      },
    );

    // **Keyed on the id rather than one fixed `cover.png`**, so the previous book's jacket can
    // never be drawn under the next book's title while a fetch is in flight. That would be a
    // wrong picture that looks like a right one, which is the failure mode this whole file exists
    // to catch.
    test(
      'Given two books, When both are encoded, Then their cover filenames differ',
      () {
        expect(
          StreakWidgetSnapshot.coverFileName('b1'),
          isNot(StreakWidgetSnapshot.coverFileName('b2')),
        );
      },
    );

    // The native side validates this rather than trusting it, because it is the one place a value
    // out of Postgres becomes a filesystem path. `isSafeCoverName` in `AppDelegate.swift` is a
    // whitelist of UUID characters plus `-` and `.`, so the name Dart builds has to stay inside
    // it -- a `..` or a `/` reaching there would be rejected and the jacket would never appear.
    test(
      'Given a Postgres uuid, When a cover filename is built, Then it has no path separators',
      () {
        final name = StreakWidgetSnapshot.coverFileName(
          '373bec95-ac73-40f8-b217-0442cb5a2bf0',
        );

        expect(name, matches(r'^[A-Za-z0-9.-]+\.png$'));
        expect(name.contains('..'), isFalse);
        expect(name.contains('/'), isFalse);
      },
    );

    // The copy ladder. Swift keys off these exact names, and the tier it draws is derived from
    // the entry's own hour -- so all seven travel every time and none of them is "the current
    // one". A missing key here is a tile that falls back to the app's flat status line without
    // anything failing.
    test(
      'Given the ladder, When a snapshot is encoded, Then every tier travels under its own key',
      () {
        final json = jsonDecode(_snapshot().encode()) as Map<String, Object?>;
        final lines = json['lines']! as Map<String, Object?>;

        expect(lines.keys, [
          'dawn',
          'morning',
          'afternoon',
          'evening',
          'late',
          'final',
          'none',
        ]);
        expect(lines['dawn'], 'Keep it going!');
        expect(lines['late'], 'Midnight approaches. So do I.');
      },
    );

    // `final` is a Dart keyword and `last` is not a tier anyone named, so the field and the wire
    // disagree on purpose. The wire is what Swift and the mockup's labels both say, which makes
    // this the one key a rename would break invisibly in two languages at once.
    test(
      'Given the 23:00 line, When it is encoded, Then the wire key is final rather than last',
      () {
        final lines =
            (jsonDecode(_snapshot().encode()) as Map<String, Object?>)['lines']!
                as Map<String, Object?>;

        expect(lines['final'], 'This is how it ends?');
        expect(lines.containsKey('last'), isFalse);
      },
    );

    // There is no `recorded` line in any voice: the lit flame says it, and a sentence under it
    // would be the tile explaining its own drawing. Asserted because the obvious "completeness"
    // refactor is to add one.
    test(
      'Given a recorded day, When the ladder is encoded, Then it carries no line for it',
      () {
        final lines =
            (jsonDecode(_snapshot().encode()) as Map<String, Object?>)['lines']!
                as Map<String, Object?>;

        expect(lines.containsKey('recorded'), isFalse);
        expect(lines.containsKey('done'), isFalse);
      },
    );
  });

  group('equality, which is what stops a reload per rebuild', () {
    test(
      'Given two snapshots built a moment apart, When they are compared, Then writtenAt is ignored',
      () async {
        final first = _snapshot();
        // Encoding is what stamps `writtenAt`, so force two different stamps.
        first.encode();
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final second = _snapshot();
        second.encode();

        expect(first, second);
        expect(first.hashCode, second.hashCode);
      },
    );

    test(
      'Given a day recorded, When the snapshot changes, Then it is no longer equal',
      () {
        expect(_snapshot(streak: 12), isNot(_snapshot(streak: 13)));
        expect(
          _snapshot(lastReadDay: DateTime(2026, 9, 22)),
          isNot(_snapshot(lastReadDay: DateTime(2026, 9, 23))),
        );
      },
    );

    // The book's identity and its position both matter: turning a page changes what the widget
    // draws, and a snapshot that compared only the id would never publish it.
    test(
      'Given progress moving on the same book, When compared, Then the snapshot differs',
      () {
        final still = StreakWidgetSnapshot(
          streak: 12,
          longestStreak: 31,
          lastReadDay: DateTime(2026, 9, 22),
          book: testBook('b1', 'reading', title: 'Piranesi', progress: 0.41),
          copy: _copy,
          lines: _lines,
        );
        final moved = StreakWidgetSnapshot(
          streak: 12,
          longestStreak: 31,
          lastReadDay: DateTime(2026, 9, 22),
          book: testBook('b1', 'reading', title: 'Piranesi', progress: 0.62),
          copy: _copy,
          lines: _lines,
        );

        expect(still, isNot(moved));
      },
    );

    // A locale change moves nothing else on this payload -- same run, same day, same book -- so
    // without the ladder in equality the widget would keep drawing yesterday's language until a
    // day happened to be recorded.
    test(
      'Given the ladder changing language, When compared, Then the snapshot differs',
      () {
        final english = _snapshot();
        final korean = StreakWidgetSnapshot(
          streak: 12,
          longestStreak: 31,
          lastReadDay: DateTime(2026, 9, 22),
          copy: _copy,
          lines: const StreakWidgetLines(
            dawn: '오늘도 독서!',
            morning: '책이 기다려요!',
            afternoon: '아직인가요..?',
            evening: '읽기로 했잖아요.',
            late: '곧 자정인데, 책은 언제 펴려나..',
            last: '이렇게 끝내요?',
            none: '책 읽기 좋은 날이에요!',
          ),
        );

        expect(english, isNot(korean));
      },
    );
  });
}
