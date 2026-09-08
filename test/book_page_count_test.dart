// Guards the page-count data path, end to end from provider JSON to the rendered
// thickness.
//
// This path has two traps that a type signature does not catch. Google Books
// returns `pageCount: 0` for volumes it has no count for rather than omitting the
// key, so a reader that trusts the field draws the thinnest book on the shelf and
// calls it data. And Postgres hands `int4` back as `num` through some codecs, so a
// bare `as int` throws on a row that is otherwise fine.
//
// The design rule being pinned: null means "no credible count" and routes the book
// to the ISBN hash; a real number sets thickness directly. Those are different code
// paths, which is why the column is nullable where `authors` is NOT NULL.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

Map<String, dynamic> _row({Object? pageCount = _absent}) => {
  'id': 'b1',
  'user_id': 'u1',
  'shelf_id': 's1',
  'isbn': '9788936434120',
  'title': 'The Vegetarian',
  'thumbnail': '',
  'status': 0,
  'position': 0,
  'created_at': '2026-01-01T00:00:00.000Z',
  if (pageCount != _absent) 'page_count': pageCount,
};

const Object _absent = Object();

void main() {
  group('Book.page_count', () {
    test('reads a plain integer', () {
      expect(Book.fromJson(_row(pageCount: 320)).pageCount, 320);
    });

    test('accepts a num, which is how some Postgres codecs hand back int4', () {
      // A bare `as int` throws here, and it would take down the whole library
      // fetch rather than one book.
      expect(Book.fromJson(_row(pageCount: 320.0)).pageCount, 320);
    });

    test('treats zero as unknown, not as the thinnest book on the shelf', () {
      expect(Book.fromJson(_row(pageCount: 0)).pageCount, isNull);
    });

    test('treats a negative count as unknown', () {
      expect(Book.fromJson(_row(pageCount: -5)).pageCount, isNull);
    });

    test('is null on a row written before the column existed', () {
      expect(Book.fromJson(_row()).pageCount, isNull);
      expect(Book.fromJson(_row(pageCount: null)).pageCount, isNull);
    });

    test('survives copyWith', () {
      final book = Book.fromJson(_row(pageCount: 320));
      expect(book.copyWith(status: 1).pageCount, 320);
      expect(book.copyWith(pageCount: 480).pageCount, 480);
    });
  });

  group('a stored count reaches the geometry', () {
    test('a long book is drawn thicker than a short one', () {
      // The point of the whole chain. With a pure hash these two would be ordered
      // by ISBN, which is to say arbitrarily.
      final short = Book.fromJson(_row(pageCount: 120));
      final long = Book.fromJson(_row(pageCount: 850));
      double thickness(Book b) =>
          BookJitter.fromIsbn(b.isbn, pageCount: b.pageCount).thicknessFactor;
      expect(thickness(long), greaterThan(thickness(short)));
    });

    test(
      'an unknown count falls back to the hash rather than to a constant',
      () {
        // Books with no count must still vary, or every Kakao-sourced title on a
        // Korean shelf would be the same thickness.
        final a = BookJitter.fromIsbn('9788936434120').thicknessFactor;
        final b = BookJitter.fromIsbn('9780141439518').thicknessFactor;
        expect(a, isNot(closeTo(b, 1e-6)));
      },
    );

    test('a zero count is indistinguishable from no count at all', () {
      final zero = Book.fromJson(_row(pageCount: 0));
      expect(
        BookJitter.fromIsbn(zero.isbn, pageCount: zero.pageCount),
        BookJitter.fromIsbn(zero.isbn),
      );
    });
  });
}
