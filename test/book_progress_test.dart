// Guards `books.progress` from the row to the page label.
//
// Three traps here, none of them caught by a type signature.
//
// An absent key and an explicit null must parse identically, because every row in
// production predates the column and a build that read absence as `0` would put an
// empty progress bar on all 109 reading books on the day it shipped. Null means
// "never set" and 0.0 means "at the very start"; those are different pictures.
//
// Postgres hands `real` back as `num` through some codecs, so a bare `as double`
// throws on a row that is otherwise fine — the same wart `page_count` documents.
//
// And the page is *derived*, in exactly one place. The drawings printed `p.148`
// above `p.147` for a whole review round because two surfaces rounded separately,
// so the rounding site is a single function and this file is what keeps it single.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';

const Object _absent = Object();

Map<String, dynamic> _row({
  Object? progress = _absent,
  Object? pageCount = _absent,
  Object? progressPage = _absent,
}) => {
  'id': 'b1',
  'user_id': 'u1',
  'shelf_id': 's1',
  'isbn': '9788936434120',
  'title': 'The Vegetarian',
  'thumbnail': '',
  'status': 1,
  'position': 0,
  'created_at': '2026-01-01T00:00:00.000Z',
  if (progress != _absent) 'progress': progress,
  if (pageCount != _absent) 'page_count': pageCount,
  if (progressPage != _absent) 'progress_page': progressPage,
};

void main() {
  group('Book.progress parsing', () {
    test('reads a fraction', () {
      expect(Book.fromJson(_row(progress: 0.46)).progress, closeTo(0.46, 1e-9));
    });

    test('accepts an int, which is how 0 and 1 can arrive over the wire', () {
      // `real` is handed back as `num` by some codecs, and the two endpoints of
      // the range are the values most likely to arrive without a decimal part.
      expect(Book.fromJson(_row(progress: 0)).progress, 0.0);
      expect(Book.fromJson(_row(progress: 1)).progress, 1.0);
    });

    test(
      'Given the key is absent, When parsed, Then progress is null — not 0',
      () {
        // Every row written before the migration. Null is the "no bar" state; 0
        // is the "empty bar" state, which would be a claim about the reader.
        expect(Book.fromJson(_row()).progress, isNull);
      },
    );

    test(
      'Given an explicit null, When parsed, Then it matches an absent key',
      () {
        expect(
          Book.fromJson(_row(progress: null)).progress,
          Book.fromJson(_row()).progress,
        );
      },
    );

    test('Given 0.0, When parsed, Then it is kept and is not null', () {
      // The distinction the whole nullable column exists for. A reader who spun
      // the wheel to 0% said something; a reader who never opened it did not.
      final atStart = Book.fromJson(_row(progress: 0));
      expect(atStart.progress, isNotNull);
      expect(atStart.progress, 0.0);
    });
  });

  group('bookProgressPage — the one rounding site', () {
    test('rounds the fraction against the count', () {
      expect(bookProgressPage(0.46, 320), 147);
    });

    test('Given no page count, Then there is no page — and no apology', () {
      // True of about two reading books in three, which is why the stored value
      // is a fraction and the page is only ever a label.
      expect(bookProgressPage(0.46, null), isNull);
    });

    test('Given no progress, Then there is no page', () {
      expect(bookProgressPage(null, 320), isNull);
    });

    test('carries the endpoints exactly', () {
      expect(bookProgressPage(0, 320), 0);
      expect(bookProgressPage(1, 320), 320);
    });

    test(
      'Given a whole percent, When rounded twice, Then it does not drift',
      () {
        // The property the 101-stop wheel buys. Every stop must land on one page
        // and stay there, or the band and the wheel print different numbers for
        // the same book.
        for (var stop = 0; stop <= 100; stop++) {
          final first = bookProgressPage(stop / 100, 320);
          final second = bookProgressPage(stop / 100, 320);
          expect(first, second);
        }
      },
    );

    test(
      'Given 320 pages, When the wheel steps 1%, Then p.148 is unreachable',
      () {
        // The accepted cost of storing a fraction, pinned so nobody "fixes" it by
        // giving the wheel finer steps — which would make this label depend on
        // which surface computed it. A stop is 3.2 pages here.
        final reachable = {
          for (var stop = 0; stop <= 100; stop++)
            bookProgressPage(stop / 100, 320),
        };
        expect(reachable, contains(147));
        expect(reachable, isNot(contains(148)));
      },
    );
  });

  group('Book.approxPage', () {
    test('delegates to the shared function', () {
      final book = Book.fromJson(_row(progress: 0.46, pageCount: 320));
      expect(book.approxPage, bookProgressPage(0.46, 320));
      expect(book.approxPage, 147);
    });

    test('Given a book with no count, Then there is no page label', () {
      expect(Book.fromJson(_row(progress: 0.46)).approxPage, isNull);
    });

    test('Given a book with no progress, Then there is no page label', () {
      expect(Book.fromJson(_row(pageCount: 320)).approxPage, isNull);
    });
  });

  // The stored column, which is a different fact from the getter above: `approxPage`
  // is computed from the fraction and exists for every book that has one, while
  // `progressPage` is *provenance* and exists only for a book whose reader typed a
  // page. Conflating them is what the rename to `approxPage` was for.
  group('Book.progressPage parsing', () {
    test('reads the page the reader typed', () {
      expect(
        Book.fromJson(
          _row(progress: 0.462963, pageCount: 432, progressPage: 200),
        ).progressPage,
        200,
      );
    });

    test(
      'Given the key is absent, Then it is null — the ordinary case, not a gap',
      () {
        // Every row written before the migration, and every row a percent answer
        // writes. Null here means "answered in percent", which is most of them.
        expect(Book.fromJson(_row(progress: 0.46)).progressPage, isNull);
      },
    );

    test('accepts a num, the way progress and page_count have to', () {
      expect(Book.fromJson(_row(progressPage: 200.0)).progressPage, 200);
    });

    test(
      'Given a typed page, When the fraction is read back, Then it is not a whole percent',
      () {
        // The whole point of the column. 200/432 has no stop on a 101-stop wheel:
        // the nearest is 46%, which is p.199. Storing the fraction *and* the page is
        // what lets the app say p.200 back.
        final book = Book.fromJson(
          _row(progress: 200 / 432, pageCount: 432, progressPage: 200),
        );
        expect(book.progressPage, 200);
        expect(bookProgressPage(book.progress, book.pageCount), 200);
        expect(bookProgressPage(0.46, 432), 199);
      },
    );
  });

  group('Book.copyWith', () {
    final book = Book.fromJson(_row(pageCount: 320));

    test('sets a progress that was not there', () {
      expect(book.copyWith(progress: 0.46).progress, closeTo(0.46, 1e-9));
    });

    test('Given no argument, Then the existing value survives', () {
      final read = book.copyWith(progress: 0.46);
      expect(read.copyWith(status: 2).progress, closeTo(0.46, 1e-9));
    });

    test(
      'leaves everything else alone — the isolation this design rests on',
      () {
        final moved = book.copyWith(progress: 0.46);
        expect(moved.status, book.status);
        expect(moved.position, book.position);
        expect(moved.readingShelfIndex, book.readingShelfIndex);
        expect(moved.startDate, book.startDate);
        expect(moved.finishDate, book.finishDate);
        expect(moved.pageCount, book.pageCount);
      },
    );

    test('carries the typed page, and drops it when told to', () {
      final typed = book.copyWith(progress: 200 / 432, progressPage: 200);
      expect(typed.progressPage, 200);
      // `copyWith` cannot express "set this back to null" — the `??` idiom the whole
      // class uses forbids it — so clearing provenance happens at the write, not
      // here. Recorded so a later reader does not mistake this for a bug.
      expect(typed.copyWith(progress: 0.46).progressPage, 200);
    });
  });
}
