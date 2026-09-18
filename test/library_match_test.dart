// The matcher behind library search, tested without a widget.
//
// These are the rules most likely to be wrong in a way nobody notices, because
// every failure looks identical from the outside: an empty "In your library"
// section, indistinguishable from not owning the book — and the sheet then reads
// that as "add it", which is how a matcher bug becomes a duplicate row.
//
// The 초성 group is the one to keep. Initial-consonant search is a baseline
// expectation in Korean apps and a plain `contains` silently fails it.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/services/isbn.dart';
import 'package:bookworm_friends/services/library_match.dart';

Book _book({
  String id = 'b1',
  String title = 'Dune',
  List<String> authors = const ['Frank Herbert'],
  String isbn = '9780441013593',
  int status = 0,
  String shelfId = 's1',
}) => Book(
  id: id,
  userId: 'u',
  shelfId: shelfId,
  isbn: isbn,
  title: title,
  thumbnail: '',
  status: status,
  position: 0,
  createdAt: DateTime(2024),
  authors: authors,
);

Shelf _shelf(String id, List<Book> books) => Shelf(
  id: id,
  userId: 'u',
  name: id,
  position: 0,
  createdAt: DateTime(2024),
  books: books,
);

BookSearchResult _result({
  String title = 'Dune',
  List<String> authors = const ['Frank Herbert'],
  String isbn = '9780441013593',
}) =>
    BookSearchResult(title: title, isbn: isbn, thumbnail: '', authors: authors);

void main() {
  group('normalisation', () {
    test('ignores case', () {
      expect(normaliseForMatch('DUNE'), normaliseForMatch('dune'));
    });

    test('strips spacing rather than collapsing it', () {
      // Korean titles are spaced inconsistently between providers and by readers
      // typing them, and a space is never the thing anyone meant to search for.
      expect(normaliseForMatch('해리 포터'), normaliseForMatch('해리포터'));
    });

    test('strips the punctuation a catalogue sprinkles through a title', () {
      expect(
        normaliseForMatch('Dune: Messiah'),
        normaliseForMatch('Dune Messiah'),
      );
    });
  });

  group('초성 (initial consonant) search', () {
    test('takes the lead consonant of every syllable', () {
      expect(hangulInitials('해리포터'), 'ㅎㄹㅍㅌ');
      expect(hangulInitials('소년이 온다'), 'ㅅㄴㅇㅇㄷ');
    });

    test('carries non-Hangul through, so a mixed title still matches', () {
      expect(hangulInitials('해리포터 2'), 'ㅎㄹㅍㅌ2');
    });

    test('ㅎㄹㅍ finds 해리포터 — the case a plain contains fails', () {
      final hp = _book(title: '해리포터와 마법사의 돌', authors: const ['J.K. 롤링']);
      expect(bookMatchesQuery(hp, 'ㅎㄹㅍ'), isTrue);
    });

    test('a real Hangul word is matched as a word, not as initials', () {
      // The distinction that cannot be skipped: 한강 is a word and must match by
      // substring, ㅎㄱ is an abbreviation and must match by initials. Running
      // both unconditionally would make a single jamo match nearly everything.
      expect(isChoseongQuery('한강'), isFalse);
      expect(isChoseongQuery('ㅎㄱ'), isTrue);
      expect(isChoseongQuery(''), isFalse);
    });

    test('initials mode matches authors too', () {
      final boy = _book(title: '소년이 온다', authors: const ['한강']);
      expect(bookMatchesQuery(boy, 'ㅎㄱ'), isTrue);
    });

    test('an initials query does not match unrelated syllables', () {
      final boy = _book(title: '소년이 온다', authors: const ['한강']);
      expect(bookMatchesQuery(boy, 'ㅋㅋㅋ'), isFalse);
    });
  });

  group('matching a book', () {
    test('matches mid-title, not just the start', () {
      expect(
        bookMatchesQuery(_book(title: 'Kafka on the Shore'), 'shore'),
        isTrue,
      );
    });

    test('matches an author', () {
      expect(bookMatchesQuery(_book(), 'herbert'), isTrue);
    });

    test('an empty query matches nothing', () {
      // Otherwise the section would list the entire library the moment the field
      // was cleared.
      expect(bookMatchesQuery(_book(), ''), isFalse);
      expect(bookMatchesQuery(_book(), '   '), isFalse);
    });
  });

  group('searchOwnLibrary ordering', () {
    test('in-progress first, then unread, then finished', () {
      final shelves = [
        _shelf('s1', [
          _book(id: 'read', title: 'Dune Read', status: bookStatusFinished),
          _book(id: 'want', title: 'Dune Wanted'),
          _book(id: 'now', title: 'Dune Now', status: bookStatusReading),
        ]),
      ];
      expect(searchOwnLibrary(shelves, 'dune').map((b) => b.id).toList(), [
        'now',
        'want',
        'read',
      ]);
    });

    test('is stable within a status group', () {
      // A stable partition rather than a sort: `List.sort` is not stable in
      // Dart, so equal books would swap places between keystrokes for no reason
      // a reader could account for.
      final shelves = [
        _shelf('s1', [
          _book(id: 'a', title: 'Dune A'),
          _book(id: 'b', title: 'Dune B'),
          _book(id: 'c', title: 'Dune C'),
        ]),
      ];
      expect(searchOwnLibrary(shelves, 'dune').map((b) => b.id).toList(), [
        'a',
        'b',
        'c',
      ]);
    });

    test('spans every shelf', () {
      final shelves = [
        _shelf('s1', [_book(id: 'a', title: 'Dune A')]),
        _shelf('s2', [_book(id: 'b', title: 'Dune B')]),
      ];
      expect(searchOwnLibrary(shelves, 'dune'), hasLength(2));
    });
  });

  group('ISBN normalisation', () {
    test('passes a 13-digit ISBN through', () {
      expect(normalisedIsbn13('9788954699914'), '9788954699914');
    });

    test('tolerates the separators a printed line carries', () {
      expect(normalisedIsbn13('978-89-546-9991-4'), '9788954699914');
    });

    test('converts an ISBN-10, which is what Google often returns', () {
      // 0441013593 -> 978 + first nine digits + a recomputed EAN-13 check digit.
      expect(normalisedIsbn13('0441013593'), '9780441013593');
      expect(isValidEan13(normalisedIsbn13('0441013593')!), isTrue);
    });

    test('accepts an X check digit and discards it', () {
      expect(normalisedIsbn13('043942089X'), '9780439420891');
    });

    test('rejects a Google volume id', () {
      // Returned as `isbn` when a volume lists no identifier at all, so it must
      // not be mistaken for one.
      expect(normalisedIsbn13('zyTCAlFPjgYC'), isNull);
    });

    test('rejects nonsense and null', () {
      expect(normalisedIsbn13(''), isNull);
      expect(normalisedIsbn13(null), isNull);
      expect(normalisedIsbn13('12345'), isNull);
    });

    test('does not require the check digit of a 13-digit input to be right', () {
      // Deliberate, and the opposite of `isbnFromBarcode`. This reads values
      // already stored by providers of varying quality; refusing to compare two
      // identical strings over a publisher's typo would be the wrong trade.
      expect(normalisedIsbn13('9788954699915'), '9788954699915');
    });
  });

  group('ownership verdict', () {
    test('none when the library has nothing like it', () {
      expect(
        ownedVerdictFor(_result(), [
          _book(title: 'Pachinko', authors: const [], isbn: '9781455563937'),
        ]),
        OwnedVerdict.none,
      );
    });

    test('an ISBN match wins even when the titles disagree', () {
      // Caught by a bad fixture in the test above, and worth pinning: the
      // identifier is the identifier. Two rows under one ISBN with different
      // titles means a provider's metadata is wrong, not that these are two
      // books — and this is the safe direction to be wrong in, because the
      // alternative is offering to add a book the reader demonstrably has.
      expect(
        ownedVerdictFor(_result(title: 'Dune'), [_book(title: 'Pachinko')]),
        OwnedVerdict.identical,
      );
    });

    test('identical on the same ISBN — the case that gets suppressed', () {
      expect(ownedVerdictFor(_result(), [_book()]), OwnedVerdict.identical);
    });

    test('identical across the ISBN-10 / ISBN-13 boundary', () {
      // The reason `normalisedIsbn13` exists: a scan stores 13 digits and Google
      // may hand back 10 for the very same edition. Compared as raw strings this
      // would come out `probable` and leave a provable duplicate on screen.
      expect(
        ownedVerdictFor(_result(isbn: '0441013593'), [
          _book(isbn: '9780441013593'),
        ]),
        OwnedVerdict.identical,
      );
    });

    test('identical when both sides carry the same provider volume id', () {
      expect(
        ownedVerdictFor(_result(isbn: 'zyTCAlFPjgYC'), [
          _book(isbn: 'zyTCAlFPjgYC'),
        ]),
        OwnedVerdict.identical,
      );
    });

    test('probable on title and author when the identifiers differ', () {
      // A different edition, or the same one wearing an identifier a provider
      // got wrong. Kept and tagged, never hidden.
      expect(
        ownedVerdictFor(_result(isbn: '9999999999999'), [_book()]),
        OwnedVerdict.probable,
      );
    });

    test('probable when the stored book has no authors at all', () {
      // `books.authors` is NOT NULL DEFAULT '{}', so empty means "none listed"
      // and "never backfilled" alike. Treating it as a mismatch would silently
      // stop tagging every row written before the column existed.
      expect(
        ownedVerdictFor(_result(isbn: '9999999999999'), [
          _book(authors: const []),
        ]),
        OwnedVerdict.probable,
      );
    });

    test('not probable when the author disagrees', () {
      expect(
        ownedVerdictFor(_result(isbn: '9999999999999'), [
          _book(authors: const ['Someone Else']),
        ]),
        OwnedVerdict.none,
      );
    });

    test('a longer title is not swallowed by a shorter one', () {
      // Title equality, not containment: owning `Dune` must not mark
      // `Dune Messiah` as owned.
      expect(
        ownedVerdictFor(_result(title: 'Dune Messiah', isbn: '9999999999999'), [
          _book(title: 'Dune'),
        ]),
        OwnedVerdict.none,
      );
    });

    test('identical outranks an earlier probable', () {
      // Checks the whole library rather than short-circuiting, or a probable
      // found first would leave a provably-duplicate cover on screen.
      final library = [
        _book(id: 'other-edition', isbn: '9999999999999'),
        _book(id: 'same-edition'),
      ];
      expect(ownedVerdictFor(_result(), library), OwnedVerdict.identical);
    });

    test('an empty library owns nothing', () {
      // The state a search run before `libraryProvider` resolves sees. Nothing
      // is suppressed, and the widget tags instead — suppression degrading to a
      // visible mark rather than to a wrong hide.
      expect(ownedVerdictFor(_result(), const []), OwnedVerdict.none);
    });
  });
}
