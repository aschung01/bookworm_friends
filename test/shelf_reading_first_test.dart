// Reading first: the in-progress books stand at the head of every shelf, in every
// density, in edit mode too.
//
// This is a display transform and nothing here writes a position — the same
// arrangement `withoutFinishedBooks` has, and the reason both live in
// `library_provider.dart` and are composed in one place.
//
// The stability assertions are the load-bearing ones. `List.sort` is not stable in
// Dart, so a sort on a status key would let two books that compare equal swap for
// no reason; these pin that both groups keep the order the reader arranged.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';

import 'support/home_page_harness.dart';

/// Ids of the books on the first shelf of [shelves], in order.
List<String> _ids(List<Shelf> shelves) => [
  for (final book in shelves.first.books) book.id,
];

Shelf _shelf(List<Book> books) => testShelf('s1', books);

void main() {
  group('withReadingFirst', () {
    test(
      'Given a reading book in the middle of a row, When promoted, Then it leads '
      'and the rest keep their order',
      () {
        final shelves = [
          _shelf([
            testBook('a', 's1', position: 0),
            testBook('b', 's1', position: 1, status: bookStatusReading),
            testBook('c', 's1', position: 2),
          ]),
        ];

        expect(_ids(withReadingFirst(shelves)), ['b', 'a', 'c']);
      },
    );

    test(
      'Given two reading books, When promoted, Then they keep their relative '
      'order',
      () {
        final shelves = [
          _shelf([
            testBook('a', 's1', position: 0),
            testBook('r1', 's1', position: 1, status: bookStatusReading),
            testBook('b', 's1', position: 2),
            testBook('r2', 's1', position: 3, status: bookStatusReading),
          ]),
        ];

        // r1 before r2, and a before b. A stable partition, not a sort.
        expect(_ids(withReadingFirst(shelves)), ['r1', 'r2', 'a', 'b']);
      },
    );

    test(
      'Given no reading books, When promoted, Then the row is unchanged',
      () {
        final shelves = [
          _shelf([
            testBook('a', 's1', position: 0),
            testBook('b', 's1', position: 1),
            testBook('c', 's1', position: 2),
          ]),
        ];

        expect(_ids(withReadingFirst(shelves)), ['a', 'b', 'c']);
      },
    );

    test(
      'Given every book is reading, When promoted, Then the row is unchanged',
      () {
        final shelves = [
          _shelf([
            testBook('a', 's1', position: 0, status: bookStatusReading),
            testBook('b', 's1', position: 1, status: bookStatusReading),
          ]),
        ];

        expect(_ids(withReadingFirst(shelves)), ['a', 'b']);
      },
    );

    test('Given an empty shelf, When promoted, Then it stays empty', () {
      expect(withReadingFirst([_shelf([])]).first.books, isEmpty);
    });

    test('Given a promoted shelf, When promoted again, Then nothing moves', () {
      final shelves = [
        _shelf([
          testBook('a', 's1', position: 0),
          testBook('r', 's1', position: 1, status: bookStatusReading),
        ]),
      ];

      final once = withReadingFirst(shelves);
      expect(_ids(withReadingFirst(once)), _ids(once));
    });

    test('Given any shelf, When promoted, Then no position is rewritten', () {
      final shelves = [
        _shelf([
          testBook('a', 's1', position: 0),
          testBook('r', 's1', position: 1, status: bookStatusReading),
        ]),
      ];

      final promoted = withReadingFirst(shelves).first.books;
      // 'r' leads the row but is still stored at 1. The view moved; the data did
      // not.
      expect(promoted.first.id, 'r');
      expect(promoted.first.position, 1);
      expect(promoted.last.position, 0);
    });

    test('Given more than one shelf, When promoted, Then each is promoted '
        'independently', () {
      final shelves = [
        testShelf('s1', [
          testBook('a', 's1'),
          testBook('r', 's1', status: bookStatusReading),
        ]),
        testShelf('s2', [testBook('c', 's2'), testBook('d', 's2')]),
      ];

      final promoted = withReadingFirst(shelves);
      expect([for (final b in promoted[0].books) b.id], ['r', 'a']);
      expect([for (final b in promoted[1].books) b.id], ['c', 'd']);
    });
  });

  group('composition with withoutFinishedBooks', () {
    // The library composes these two. They touch disjoint statuses, so the order
    // is a readability choice — this is what makes that claim true rather than
    // assumed.
    final shelves = [
      _shelf([
        testBook('done', 's1', position: 0, status: bookStatusFinished),
        testBook('unread', 's1', position: 1),
        testBook('reading', 's1', position: 2, status: bookStatusReading),
      ]),
    ];

    test(
      'Given a shelf with all three statuses, When composed either way, Then the '
      'result is the same',
      () {
        expect(
          _ids(withReadingFirst(withoutFinishedBooks(shelves))),
          _ids(withoutFinishedBooks(withReadingFirst(shelves))),
        );
      },
    );

    test(
      'Given a shelf with all three statuses, When composed, Then the finished '
      'book is gone and the reading book leads',
      () {
        expect(_ids(withReadingFirst(withoutFinishedBooks(shelves))), [
          'reading',
          'unread',
        ]);
      },
    );

    test(
      'Given promotion is applied, When counting the row, Then shelvedBookCount '
      'is unchanged',
      () {
        // Membership is untouched by promotion, which is what keeps the shelf-tab
        // hero the same width at both ends of its flight.
        expect(
          shelvedBookCount(withReadingFirst(shelves).first),
          shelvedBookCount(shelves.first),
        );
      },
    );
  });

  group('readingHeadCount', () {
    test(
      'Given a promoted shelf, When counted, Then it is the leading run',
      () {
        final shelf = withReadingFirst([
          _shelf([
            testBook('a', 's1'),
            testBook('r1', 's1', status: bookStatusReading),
            testBook('r2', 's1', status: bookStatusReading),
          ]),
        ]).first;

        expect(readingHeadCount(shelf), 2);
      },
    );

    test('Given no reading books, When counted, Then it is zero', () {
      expect(readingHeadCount(_shelf([testBook('a', 's1')])), 0);
    });

    test('Given an empty shelf, When counted, Then it is zero', () {
      expect(readingHeadCount(_shelf([])), 0);
    });

    test(
      'Given every book is reading, When counted, Then it is the length',
      () {
        final shelf = _shelf([
          testBook('a', 's1', status: bookStatusReading),
          testBook('b', 's1', status: bookStatusReading),
        ]);

        expect(readingHeadCount(shelf), 2);
      },
    );

    test(
      'Given an unpromoted shelf, When counted, Then it measures the leading run '
      'and not the total',
      () {
        // Documented behaviour, not an accident: it is `takeWhile`, so a caller
        // that skipped `withReadingFirst` gets a wrong answer rather than an
        // error. Callers get their shelves from `LibraryPane`, which promotes.
        final shelf = _shelf([
          testBook('a', 's1'),
          testBook('r', 's1', status: bookStatusReading),
        ]);

        expect(readingHeadCount(shelf), 0);
      },
    );
  });
}
