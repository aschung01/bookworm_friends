// Tests for the Library Card's figures.
//
// A pure unit test, because `libraryCardStats` is a pure function over a list the
// app already fetches. There is no query to fake and no widget to pump, and that
// is the point of having written it as a function.
//
// Two of the drawn stats are absent here on purpose. "4,180 pages" is not tested
// because it is not built: no catalogue can answer for these books (Kakao has no
// page field at all; Google Books covered 14 of 40 sampled titles). "Rating 4.2"
// is not built either — all 624 migrated rows are `rating: null` and no UI can set
// one. See `docs/superpowers/plans/2026-08-16-phase-3-library-card-plan.md`.
//
// What the cases below are really defending is a single idea: **a figure is either
// true or absent.** Every degenerate shape in the real data — a same-day span, a
// book with no authors, a one-book "favourite" author — has a case here, because
// each one is a chance for the card to state something it does not know.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';

Book _book({
  required String id,
  DateTime? start,
  DateTime? finish,
  List<String> authors = const [],
}) => Book(
  id: id,
  userId: 'u',
  shelfId: 's',
  isbn: id,
  title: 'Book $id',
  thumbnail: '',
  // 2 is `bookStatusFinished`, inlined so a pure stats test does not have to
  // import the provider library that declares it.
  status: 2,
  position: 0,
  startDate: start,
  finishDate: finish,
  createdAt: DateTime(2024),
  authors: authors,
);

/// A book that took [days] to read, finished on [finish].
Book _spanned(
  String id,
  int days,
  DateTime finish, {
  List<String> authors = const [],
}) => _book(
  id: id,
  start: finish.subtract(Duration(days: days)),
  finish: finish,
  authors: authors,
);

void main() {
  group('libraryCardStats', () {
    test(
      'Given no books, When the stats are derived, Then every figure is absent',
      () {
        final stats = libraryCardStats([]);

        expect(stats.booksRead, 0);
        expect(stats.pace, isNull);
        expect(stats.hasPace, isFalse);
        expect(stats.hasTopAuthor, isFalse);
        expect(stats.hasAnyTile, isFalse);
      },
    );

    test(
      'Given one book with a real span, When the stats are derived, Then pace is that span',
      () {
        final stats = libraryCardStats([
          _spanned('a', 6, DateTime(2024, 3, 10)),
        ]);

        expect(stats.booksRead, 1);
        expect(stats.daysReading, 6);
        expect(stats.paceSampleSize, 1);
        expect(stats.pace, 6);
      },
    );

    test('Given every book was logged same-day, When the stats are derived, '
        'Then pace is absent rather than zero', () {
      // The single most important case in this file. 168 of the 293 finished
      // books in the migrated corpus have `start == finish`, because flipping a
      // book straight to finished sets both to today. Reporting `0d per book`
      // for those would be a confident lie, and it is what 29 of 55 real users
      // would have seen.
      final sameDay = DateTime(2024, 5, 1);
      final stats = libraryCardStats([
        _book(id: 'a', start: sameDay, finish: sameDay),
        _book(id: 'b', start: sameDay, finish: sameDay),
        _book(id: 'c', start: sameDay, finish: sameDay),
      ]);

      expect(stats.booksRead, 3, reason: 'the books were still read');
      expect(stats.daysReading, 0);
      expect(stats.paceSampleSize, 0);
      expect(stats.pace, isNull, reason: 'unknown, not zero');
      expect(stats.hasPace, isFalse);
    });

    test('Given a mix of same-day and real spans, When the stats are derived, '
        'Then only the real spans count toward pace', () {
      final sameDay = DateTime(2024, 5, 1);
      final stats = libraryCardStats([
        _book(id: 'a', start: sameDay, finish: sameDay),
        _spanned('b', 4, DateTime(2024, 6, 1)),
        _spanned('c', 8, DateTime(2024, 7, 1)),
      ]);

      expect(stats.booksRead, 3);
      expect(stats.daysReading, 12);
      expect(
        stats.paceSampleSize,
        2,
        reason:
            'the same-day book is excluded from the divisor, not counted as 0',
      );
      expect(stats.pace, 6);
    });

    test(
      'Given books with no start date, When the stats are derived, Then they are excluded from pace',
      () {
        final stats = libraryCardStats([
          _book(id: 'a', finish: DateTime(2024, 5, 1)),
          _spanned('b', 10, DateTime(2024, 6, 1)),
        ]);

        expect(stats.booksRead, 2);
        expect(stats.paceSampleSize, 1);
        expect(stats.pace, 10);
      },
    );

    test(
      'Given an author with two books, When the stats are derived, Then they are the top author',
      () {
        final stats = libraryCardStats([
          _spanned('a', 3, DateTime(2024, 1, 1), authors: ['한강']),
          _spanned('b', 3, DateTime(2024, 2, 1), authors: ['한강']),
          _spanned('c', 3, DateTime(2024, 3, 1), authors: ['김영하']),
        ]);

        expect(stats.topAuthor, '한강');
        expect(stats.topAuthorCount, 2);
        expect(stats.hasTopAuthor, isTrue);
      },
    );

    test('Given every author has exactly one book, When the stats are derived, '
        'Then no author is named', () {
      // 40 of the 53 users with author data are shaped exactly like this. A
      // "favourite author" who wrote one of your three books is a fact about a
      // tie-break, not about your reading.
      final stats = libraryCardStats([
        _spanned('a', 3, DateTime(2024, 1, 1), authors: ['한강']),
        _spanned('b', 3, DateTime(2024, 2, 1), authors: ['김영하']),
      ]);

      expect(stats.topAuthorCount, 0);
      expect(stats.topAuthor, isNull);
      expect(stats.hasTopAuthor, isFalse);
    });

    test('Given only the first author is credited, When a book lists several, '
        'Then the co-authors do not accumulate', () {
      final stats = libraryCardStats([
        _spanned('a', 1, DateTime(2024, 1, 1), authors: ['한강', '공저자']),
        _spanned('b', 1, DateTime(2024, 2, 1), authors: ['한강', '다른 공저자']),
        // Listed second twice, so crediting every author would make this the
        // winner at 2 while 한강 also sits at 2 — a tie that should not exist.
        _spanned('c', 1, DateTime(2024, 3, 1), authors: ['김영하', '공저자']),
      ]);

      expect(stats.topAuthor, '한강');
      expect(stats.topAuthorCount, 2);
    });

    test('Given a tie on author count, When the stats are derived, '
        'Then the most recently finished wins rather than map order', () {
      final stats = libraryCardStats([
        _spanned('a', 1, DateTime(2024, 1, 1), authors: ['먼저']),
        _spanned('b', 1, DateTime(2024, 2, 1), authors: ['먼저']),
        _spanned('c', 1, DateTime(2024, 6, 1), authors: ['나중']),
        _spanned('d', 1, DateTime(2024, 7, 1), authors: ['나중']),
      ]);

      expect(
        stats.topAuthor,
        '나중',
        reason: 'both have two books; the tie breaks on the later finish',
      );
      expect(stats.topAuthorCount, 2);
    });

    test(
      'Given books with empty authors, When the stats are derived, Then no author is named',
      () {
        // 18 of 559 corpus ISBNs are not in Kakao, and 15 rows have no ISBN at
        // all, so an empty `authors` is a normal row rather than an error.
        final stats = libraryCardStats([
          _spanned('a', 2, DateTime(2024, 1, 1)),
          _spanned('b', 2, DateTime(2024, 2, 1)),
        ]);

        expect(stats.hasTopAuthor, isFalse);
        expect(
          stats.hasPace,
          isTrue,
          reason: 'pace does not depend on authors',
        );
        expect(stats.hasAnyTile, isTrue);
      },
    );

    test(
      'Given a whitespace-only author, When the stats are derived, Then it is not named',
      () {
        final stats = libraryCardStats([
          _spanned('a', 2, DateTime(2024, 1, 1), authors: ['   ']),
          _spanned('b', 2, DateTime(2024, 2, 1), authors: ['   ']),
        ]);

        expect(stats.hasTopAuthor, isFalse);
      },
    );
  });

  group('libraryCardStats year filter', () {
    final books = [
      _spanned('a', 4, DateTime(2024, 3, 1), authors: ['한강']),
      _spanned('b', 6, DateTime(2024, 8, 1), authors: ['한강']),
      _spanned('c', 20, DateTime(2023, 5, 1), authors: ['김영하']),
    ];

    test('Given year 0, When the stats are derived, Then all time is used', () {
      final stats = libraryCardStats(books, year: 0);

      expect(stats.booksRead, 3);
      expect(stats.daysReading, 30);
      expect(stats.topAuthor, '한강');
    });

    test(
      'Given a year, When the stats are derived, Then only that year counts',
      () {
        final stats = libraryCardStats(books, year: 2024);

        expect(stats.booksRead, 2);
        expect(stats.daysReading, 10);
        expect(stats.pace, 5);
        expect(stats.topAuthor, '한강');
      },
    );

    test('Given a year with one book, When the stats are derived, '
        'Then the author who cleared the floor all-time no longer does', () {
      final stats = libraryCardStats(books, year: 2023);

      expect(stats.booksRead, 1);
      expect(stats.pace, 20);
      expect(
        stats.hasTopAuthor,
        isFalse,
        reason: 'one book by 김영하 in 2023 does not clear the floor of two',
      );
    });

    test(
      'Given a year with no books, When the stats are derived, Then everything is absent',
      () {
        final stats = libraryCardStats(books, year: 1999);

        expect(stats.booksRead, 0);
        expect(stats.hasAnyTile, isFalse);
      },
    );
  });
}
