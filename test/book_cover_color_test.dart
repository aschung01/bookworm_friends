// Guards for `books.cover_color`: the wire format, and the three ways it can be
// absent.
//
// The column is cosmetic, which is precisely why it needs a test. A malformed
// value must put the book back on its ISBN-derived fallback rather than paint its
// spine a tone no cover ever had, and nothing about that failure is visible
// enough to be noticed in a simulator.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';

/// A row as Supabase returns it, with `cover_color` set to whatever is under
/// test. Every other field is the minimum `Book.fromJson` requires.
Map<String, dynamic> _row({Object? coverColor = _absent}) => {
  'id': 'b1',
  'user_id': 'u1',
  'shelf_id': 's1',
  'isbn': '9788936434120',
  'title': '채식주의자',
  'thumbnail': '',
  'status': 2,
  'created_at': '2026-01-01T00:00:00Z',
  if (coverColor != _absent) 'cover_color': coverColor,
};

/// Distinguishes "key omitted" from "key present and null", which are two
/// different situations in the database and must be the same one to the caller.
const Object _absent = Object();

void main() {
  group('bookCoverColorFromHex', () {
    test('Given a six-digit hex, Then it parses to an opaque colour', () {
      // The wire format, with and without the leading marker. Both appear: the
      // app writes `#RRGGBB`, and a value typed by hand into a table view may
      // not.
      expect(bookCoverColorFromHex('#2A1C14'), const Color(0xFF2A1C14));
      expect(bookCoverColorFromHex('2A1C14'), const Color(0xFF2A1C14));
    });

    test('Given lower case, Then it parses the same', () {
      expect(
        bookCoverColorFromHex('#dcd8d1'),
        bookCoverColorFromHex('#DCD8D1'),
      );
    });

    test('Given alpha is never stored, Then the result is always opaque', () {
      // The value is the average of an opaque cover. A translucent spine is not a
      // state the column represents, so the parser supplies the alpha rather than
      // reading one.
      expect(bookCoverColorFromHex('#000000')!.a, 1.0);
      expect(bookCoverColorFromHex('#FFFFFF')!.a, 1.0);
    });

    test('Given a malformed value, Then it is null rather than a colour', () {
      // Every one of these would otherwise be a plausible-looking bug: a black
      // spine, or a spine in some fragment of the intended colour. Null puts the
      // book back on the generated-cover fallback, which looks deliberate.
      for (final bad in <String>[
        '',
        '#',
        '#ABC', // three-digit shorthand is not the wire format
        '#ABCDE', // one short
        '#ABCDEFA', // one long
        '#GGGGGG', // not hex
        'rgb(1,2,3)',
        '0xFF2A1C14',
        ' #2A1C14', // padded, and int.parse would tolerate some of these
        '#2A1C14 ',
      ]) {
        expect(
          bookCoverColorFromHex(bad),
          isNull,
          reason: '"$bad" parsed to a colour instead of being rejected',
        );
      }
    });

    test('Given null, Then it is null', () {
      expect(bookCoverColorFromHex(null), isNull);
    });
  });

  group('bookCoverColorToHex', () {
    test('Given a colour, Then it round-trips through the wire format', () {
      for (final colour in <Color>[
        const Color(0xFF2A1C14),
        const Color(0xFFDCD8D1),
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
        const Color(0xFF09BC8A),
      ]) {
        expect(
          bookCoverColorFromHex(bookCoverColorToHex(colour)),
          colour,
          reason: 'lost information formatting or parsing $colour',
        );
      }
    });

    test('Given a translucent colour, Then the alpha is dropped', () {
      // `_sampleCoverColor` builds its result with a hard 255, so this should
      // never arrive — but dropping alpha silently is better than encoding a
      // channel the column does not have and the parser ignores.
      expect(bookCoverColorToHex(const Color(0x802A1C14)), '#2A1C14');
    });

    test('Given a low channel, Then it is zero-padded to six digits', () {
      // `toRadixString` drops leading zeros, which would produce a value the
      // parser then rejects — the failure would be a book losing its colour the
      // moment it was stored.
      expect(bookCoverColorToHex(const Color(0xFF000102)), '#000102');
    });
  });

  group('Book.fromJson', () {
    test('Given cover_color is set, Then the book carries it', () {
      expect(
        Book.fromJson(_row(coverColor: '#2A1C14')).coverColor,
        const Color(0xFF2A1C14),
      );
    });

    test('Given cover_color is null, Then the book has none', () {
      // The ordinary case for a book whose cover has never been decoded.
      expect(Book.fromJson(_row(coverColor: null)).coverColor, isNull);
    });

    test('Given the column is missing, Then the book has none', () {
      // A row written before the migration. Must not throw, and must be
      // indistinguishable from "never sampled" to every caller.
      expect(Book.fromJson(_row()).coverColor, isNull);
    });

    test('Given a malformed cover_color, Then the book has none', () {
      expect(
        Book.fromJson(_row(coverColor: 'not-a-colour')).coverColor,
        isNull,
      );
    });
  });

  group('Book.copyWith', () {
    test('Given a sampled colour, Then it can be set', () {
      // In the signature, unlike `isbn` or `thumbnail`, because this field really
      // does change after a row is written: the first widget to decode the cover
      // reports the sample and it is stored.
      final book = Book.fromJson(_row());
      expect(book.coverColor, isNull);
      expect(
        book.copyWith(coverColor: const Color(0xFF2A1C14)).coverColor,
        const Color(0xFF2A1C14),
      );
    });

    test('Given no argument, Then an existing colour survives', () {
      final book = Book.fromJson(_row(coverColor: '#2A1C14'));

      expect(book.copyWith(status: 1).coverColor, const Color(0xFF2A1C14));
    });
  });
}
