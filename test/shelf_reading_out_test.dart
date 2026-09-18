// Reading books come *off* the shelves: they stand on the Reading shelf at the top of
// the library instead, the way finished books stand in the read pile at the bottom.
//
// `withoutReadingBooks` and `readingBooksOf` are the two halves of that move, and this
// file pins that they are halves of one thing — every book is in exactly one of the two
// places, none is in both, and nothing is lost.
//
// **This file replaces `shelf_reading_first_test.dart`, whose subject no longer exists.**
// `withReadingFirst` promoted an open book to the head of its own row, so a shelf was
// two regions with a barrier between them and most of what that file asserted was about
// the stability of a partition. There is no partition now. What it also documented — that
// edit mode wrote positions from the *promoted* row, so the first drag persisted the
// promotion — is the wart this filter retires, and the last group here is what pins that
// it is retired: a book's stored `position` is untouched, so clearing its status puts the
// cover back exactly where the reader filed it.

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
  group('withoutReadingBooks', () {
    test(
      'Given a reading book in the middle of a row, When filtered, Then it is gone '
      'and the rest keep their order',
      () {
        final shelves = [
          _shelf([
            testBook('a', 's1', position: 0),
            testBook('b', 's1', position: 1, status: bookStatusReading),
            testBook('c', 's1', position: 2),
          ]),
        ];

        // Not reordered, unlike the promotion this replaced: the gap simply closes.
        expect(_ids(withoutReadingBooks(shelves)), ['a', 'c']);
      },
    );

    test(
      'Given no reading books, When filtered, Then the row is unchanged',
      () {
        final shelves = [
          _shelf([
            testBook('a', 's1', position: 0),
            testBook('b', 's1', position: 1),
          ]),
        ];

        expect(_ids(withoutReadingBooks(shelves)), ['a', 'b']);
      },
    );

    test('Given every book is reading, When filtered, Then the shelf empties', () {
      // The visible consequence, and it is correct: a shelf whose whole queue has
      // been started shows an empty plank, because every one of its books is standing
      // on the Reading shelf above.
      final shelves = [
        _shelf([
          testBook('a', 's1', status: bookStatusReading),
          testBook('b', 's1', status: bookStatusReading),
        ]),
      ];

      expect(withoutReadingBooks(shelves).first.books, isEmpty);
    });

    test('Given an empty shelf, When filtered, Then it stays empty', () {
      expect(withoutReadingBooks([_shelf([])]).first.books, isEmpty);
    });

    test(
      'Given a filtered shelf, When filtered again, Then nothing changes',
      () {
        final shelves = [
          _shelf([
            testBook('a', 's1'),
            testBook('r', 's1', status: bookStatusReading),
          ]),
        ];

        final once = withoutReadingBooks(shelves);
        expect(_ids(withoutReadingBooks(once)), _ids(once));
      },
    );

    test('Given more than one shelf, When filtered, Then each is filtered '
        'independently', () {
      final shelves = [
        testShelf('s1', [
          testBook('a', 's1'),
          testBook('r', 's1', status: bookStatusReading),
        ]),
        testShelf('s2', [testBook('c', 's2'), testBook('d', 's2')]),
      ];

      final kept = withoutReadingBooks(shelves);
      expect([for (final b in kept[0].books) b.id], ['a']);
      expect([for (final b in kept[1].books) b.id], ['c', 'd']);
    });

    test('Given a finished book, When filtered, Then it is left alone', () {
      // This filter touches status 1 and nothing else. `withoutFinishedBooks` is what
      // takes the other one, and the library composes both.
      final shelves = [
        _shelf([testBook('done', 's1', status: bookStatusFinished)]),
      ];

      expect(_ids(withoutReadingBooks(shelves)), ['done']);
    });
  });

  group('where an opened book lands', () {
    // The rule `updateBookStatus` and `addBook` both write. Pure, so it is testable without
    // a database: the arithmetic is the substance and the query around it is one line.

    test('Given nothing open, When a book is opened, Then it takes 0', () {
      expect(readingHeadIndexFor(const []), 0);
    });

    test(
      'Given an open shelf, When another book is opened, Then it goes to the head',
      () {
        // Head, not tail: the row clips at about three covers, so appending would land a newly
        // opened book off-screen behind the fade and lose the arrival that says the shelf
        // changed.
        final open = [
          testBook('a', 's1', status: bookStatusReading, readingShelfIndex: 0),
          testBook('b', 's1', status: bookStatusReading, readingShelfIndex: 1),
        ];

        expect(readingHeadIndexFor(open), -1);
      },
    );

    test(
      'Given a shelf already headed by a negative index, Then it keeps going down',
      () {
        // `min - 1` never collides, and never has to shift the other rows to make room. The
        // next reorder renumbers the set back to 0..n-1.
        final open = [
          testBook('a', 's1', status: bookStatusReading, readingShelfIndex: -3),
          testBook('b', 's1', status: bookStatusReading, readingShelfIndex: 0),
        ];

        expect(readingHeadIndexFor(open), -4);
      },
    );

    test(
      'Given books with no stored index, Then they do not count as the head',
      () {
        // A null sorts *last*, so it is not at the head for a new book to get in front of.
        // Treating null as 0 here would put the new book at -1 and leave the unarranged one
        // stranded at the end of the row.
        final open = [
          testBook('none', 's1', status: bookStatusReading),
          testBook(
            'two',
            's1',
            status: bookStatusReading,
            readingShelfIndex: 2,
          ),
        ];

        expect(readingHeadIndexFor(open), 1);
      },
    );

    test('Given only unarranged books, Then the newcomer still takes 0', () {
      final open = [testBook('none', 's1', status: bookStatusReading)];

      expect(readingHeadIndexFor(open), 0);
    });

    test('Given the book itself is already open, When confirmed again, Then it does '
        'not shuffle forward', () {
      // Re-picking "reading" for a book that is already in progress must not bump it to the
      // front of the shelf: it is excluded from its own reckoning, so it lands where it
      // already was rather than one before itself.
      final open = [
        testBook('a', 's1', status: bookStatusReading, readingShelfIndex: 0),
        testBook('b', 's1', status: bookStatusReading, readingShelfIndex: 1),
      ];

      expect(readingHeadIndexFor(open, excluding: 'a'), 0);
    });
  });

  group('readingBooksOf', () {
    test('Given reading books with no stored index, When gathered, Then they arrive '
        'in shelf order', () {
      // The fallback, and the behaviour every reader had before `reading_shelf_index`
      // existed: a book with no stored place sorts last, and among books that all lack
      // one "last" is the order the reader arranged their shelves in. This is also what
      // makes the column's backfill invisible — it writes exactly this order.
      final shelves = [
        testShelf('s1', [
          testBook('a', 's1'),
          testBook('r1', 's1', status: bookStatusReading),
        ]),
        testShelf('s2', [
          testBook('r2', 's2', status: bookStatusReading),
          testBook('b', 's2'),
        ]),
      ];

      expect([for (final b in readingBooksOf(shelves)) b.id], ['r1', 'r2']);
    });

    test('Given a stored order, When gathered, Then it beats shelf order', () {
      // The whole point of the column: the reader's arrangement wins over where the
      // books happen to have come from. Here the indices invert the shelf walk.
      final shelves = [
        testShelf('s1', [
          testBook('r1', 's1', status: bookStatusReading, readingShelfIndex: 2),
        ]),
        testShelf('s2', [
          testBook('r2', 's2', status: bookStatusReading, readingShelfIndex: 1),
          testBook('r3', 's2', status: bookStatusReading, readingShelfIndex: 0),
        ]),
      ];

      expect(
        [for (final b in readingBooksOf(shelves)) b.id],
        ['r3', 'r2', 'r1'],
      );
    });

    test('Given a negative index, When gathered, Then it sorts to the head', () {
      // What opening a book writes. `updateBookStatus` puts a newly opened book at
      // `min - 1` rather than shifting every other row, so negatives are a normal state
      // of this column and not a corruption to defend against.
      final shelves = [
        _shelf([
          testBook(
            'old',
            's1',
            status: bookStatusReading,
            readingShelfIndex: 0,
          ),
          testBook(
            'justOpened',
            's1',
            status: bookStatusReading,
            readingShelfIndex: -1,
          ),
        ]),
      ];

      expect(
        [for (final b in readingBooksOf(shelves)) b.id],
        ['justOpened', 'old'],
      );
    });

    test('Given a mix of stored and missing indices, When gathered, Then the '
        'unarranged books come last', () {
      // A library part-way through the backfill, or one book opened by a build that
      // predates the column. An arranged book must not be pushed below one that has
      // never been arranged — which is what sorting nulls *first* would do.
      final shelves = [
        testShelf('s1', [
          testBook('noIndex1', 's1', status: bookStatusReading),
        ]),
        testShelf('s2', [
          testBook(
            'indexed',
            's2',
            status: bookStatusReading,
            readingShelfIndex: 7,
          ),
          testBook('noIndex2', 's2', status: bookStatusReading),
        ]),
      ];

      expect(
        [for (final b in readingBooksOf(shelves)) b.id],
        ['indexed', 'noIndex1', 'noIndex2'],
      );
    });

    test('Given two books sharing an index, When gathered, Then shelf order breaks '
        'the tie', () {
      // Duplicates are tolerated rather than prevented: a reorder rewrites the set one
      // row at a time, so a UNIQUE constraint would fail midway through a perfectly good
      // drag. The tie therefore has to resolve deterministically, and it must not depend
      // on `List.sort` being stable — it is not guaranteed to be.
      final shelves = [
        testShelf('s1', [
          testBook(
            'first',
            's1',
            status: bookStatusReading,
            readingShelfIndex: 3,
          ),
        ]),
        testShelf('s2', [
          testBook(
            'second',
            's2',
            status: bookStatusReading,
            readingShelfIndex: 3,
          ),
        ]),
      ];

      expect(
        [for (final b in readingBooksOf(shelves)) b.id],
        ['first', 'second'],
      );
    });

    test(
      'Given a reordered set, When gathered twice, Then the order is stable',
      () {
        // Sorting must be idempotent: the row is rebuilt on every frame that touches the
        // library, and an order that shifted between two identical inputs would show up as
        // covers swapping places on their own.
        final shelves = [
          _shelf([
            testBook(
              'x',
              's1',
              status: bookStatusReading,
              readingShelfIndex: 1,
            ),
            testBook(
              'y',
              's1',
              status: bookStatusReading,
              readingShelfIndex: 0,
            ),
            testBook('z', 's1', status: bookStatusReading),
          ]),
        ];

        final once = [for (final b in readingBooksOf(shelves)) b.id];
        expect([for (final b in readingBooksOf(shelves)) b.id], once);
        expect(once, ['y', 'x', 'z']);
      },
    );

    test('Given no reading books, When gathered, Then the result is empty', () {
      // What makes the shelf vanish rather than stand there empty.
      final shelves = [
        _shelf([
          testBook('a', 's1'),
          testBook('done', 's1', status: bookStatusFinished),
        ]),
      ];

      expect(readingBooksOf(shelves), isEmpty);
    });

    test(
      'Given no shelves at all, When gathered, Then the result is empty',
      () {
        expect(readingBooksOf(const []), isEmpty);
      },
    );
  });

  group('the two halves partition the shelf', () {
    final shelves = [
      _shelf([
        testBook('unread', 's1', position: 0),
        testBook('r', 's1', position: 1, status: bookStatusReading),
        testBook('unread2', 's1', position: 2),
      ]),
    ];

    test(
      'Given a shelf, When split, Then every book is in exactly one place',
      () {
        final onPlank = _ids(withoutReadingBooks(shelves)).toSet();
        final onReadingShelf = {for (final b in readingBooksOf(shelves)) b.id};

        expect(onPlank.intersection(onReadingShelf), isEmpty);
        expect(onPlank.union(onReadingShelf), {
          for (final b in shelves.first.books) b.id,
        });
      },
    );

    test('Given a shelf, When split, Then no position is rewritten', () {
      // The promise `withReadingFirst` could not keep. The book keeps its `shelf_id`
      // and its `position`, so clearing its reading status puts the cover back on that
      // plank between the two books the reader filed it between — rather than wherever
      // a promoted row happened to leave it after the first drag.
      final open = readingBooksOf(shelves).single;
      expect(open.shelfId, 's1');
      expect(open.position, 1);

      final kept = withoutReadingBooks(shelves).first.books;
      expect([for (final b in kept) b.position], [0, 2]);
    });
  });

  group('composition with withoutFinishedBooks', () {
    // The library composes these two. They touch disjoint statuses, so the order is a
    // readability choice — this is what makes that claim true rather than assumed.
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
          _ids(withoutReadingBooks(withoutFinishedBooks(shelves))),
          _ids(withoutFinishedBooks(withoutReadingBooks(shelves))),
        );
      },
    );

    test(
      'Given a shelf with all three statuses, When composed, Then only the unread '
      'book is left on the plank',
      () {
        expect(_ids(withoutReadingBooks(withoutFinishedBooks(shelves))), [
          'unread',
        ]);
      },
    );

    test('Given a shelf with all three statuses, When counted, Then the count is the '
        'covers on the plank', () {
      // The number a reader will check by scrolling the row to its end, so it has to
      // equal the row's length after both filters. Opening a book drops its shelf's
      // count by one, which is correct: the book has left the queue.
      expect(
        shelvedBookCount(shelves.first),
        _ids(withoutReadingBooks(withoutFinishedBooks(shelves))).length,
      );
    });
  });
}
