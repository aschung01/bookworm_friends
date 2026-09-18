// Parsing the iTunes responses behind the Apple Books row.
//
// Worth testing on its own, because this is the one place in the "where to read"
// feature where an **outside party's JSON decides what the sheet promises**.
// A `trackViewUrl` that parses becomes `StoreReach.book`, which is what licenses
// the row to say "Opens this book" — so a guard missing here is the app making a
// promise on the strength of a response it never checked.
//
// Every fixture below is shaped after a real response body from the live endpoint,
// trimmed to the keys this code reads. The shapes were confirmed by request.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/apple_books_lookup.dart';

/// A real hit, as returned for `isbn=9780143127741&entity=ebook&country=us`.
const _hit = '''
{ "resultCount": 1, "results": [ {
    "kind": "ebook",
    "artistName": "Bessel van der Kolk, M.D.",
    "trackName": "The Body Keeps the Score",
    "trackViewUrl": "https://books.apple.com/us/book/the-body-keeps-the-score/id731076045?uo=4"
} ] }
''';

/// A real miss. Apple answers 200 with an empty list rather than a 404.
const _miss = '{ "resultCount": 0, "results": [] }';

/// The live `search` response for "The Body Keeps the Score Bessel van der Kolk",
/// in the order Apple actually returns it. **The knock-offs are the point.**
const _searchWithKnockOffs = '''
{ "resultCount": 3, "results": [
  { "kind": "ebook",
    "trackName": "The Body Keeps the Score by Bessel van der Kolk, MD - Summary and Analysis",
    "artistName": "Summary Life",
    "trackViewUrl": "https://books.apple.com/us/book/summary/id6737178603" },
  { "kind": "ebook",
    "trackName": "The Body Keeps the Score",
    "artistName": "Bessel van der Kolk, M.D.",
    "trackViewUrl": "https://books.apple.com/us/book/the-body-keeps-the-score/id731076045?uo=4" },
  { "kind": "ebook",
    "trackName": "The Body Keeps the Score By Bessel Van der kolk, M.D",
    "artistName": "Easy Reads",
    "trackViewUrl": "https://books.apple.com/us/book/easy/id6756572566" }
] }
''';

Uri? search(String body, {String title = 'x', String author = 'y'}) =>
    appleBookUrlFromSearchJson(body, title: title, author: author);

void main() {
  group('an ISBN hit', () {
    test('yields the book URL', () {
      expect(
        appleBookUrlFromLookupJson(_hit).toString(),
        'https://books.apple.com/us/book/the-body-keeps-the-score/id731076045',
      );
    });

    // `uo=4` is Apple's own affiliate/analytics marker and is echoed into every
    // `trackViewUrl`. It would otherwise end up in a URL the reader can see and
    // share, having been asked for by nobody.
    test('drops Apple\'s uo tracking parameter', () {
      final uri = appleBookUrlFromLookupJson(_hit)!;
      expect(uri.queryParameters, isEmpty);
      // And leaves no bare `?` behind, which `replace(query: "")` would.
      expect(uri.toString(), isNot(contains('?')));
    });

    test('keeps any other query parameter rather than flattening the URL', () {
      final uri = appleBookUrlFromLookupJson('''
        { "resultCount": 1, "results": [ {
            "kind": "ebook",
            "trackViewUrl": "https://books.apple.com/us/book/x/id1?uo=4&l=en"
        } ] }
      ''');
      expect(uri!.queryParameters, {'l': 'en'});
    });
  });

  group('no exact URL', () {
    // The ordinary outcome, not an error.
    test('a miss is null', () {
      expect(appleBookUrlFromLookupJson(_miss), isNull);
      expect(search(_miss), isNull);
    });

    test('so is a body that is not JSON at all', () {
      expect(
        appleBookUrlFromLookupJson('<html>502 Bad Gateway</html>'),
        isNull,
      );
    });

    test('so is valid JSON of the wrong shape', () {
      expect(appleBookUrlFromLookupJson('[1, 2, 3]'), isNull);
      expect(appleBookUrlFromLookupJson('{"results": "nope"}'), isNull);
    });

    test('so is a result with no trackViewUrl', () {
      expect(
        appleBookUrlFromLookupJson(
          '{"resultCount":1,"results":[{"kind":"ebook"}]}',
        ),
        isNull,
      );
    });
  });

  group('the guards on a result', () {
    // `entity=ebook` is a request, not a guarantee. An audiobook of the same
    // title is a different product.
    test('a non-ebook kind is refused', () {
      expect(
        appleBookUrlFromLookupJson('''
          { "resultCount": 1, "results": [ {
              "kind": "audiobook",
              "trackViewUrl": "https://books.apple.com/us/audiobook/x/id1"
          } ] }
        '''),
        isNull,
      );
    });

    // **The one with teeth.** This URL is handed to `launchUrl` with
    // `externalApplication`, so accepting an arbitrary host would let a
    // third-party response send the reader anywhere the OS can open.
    test('a host other than books.apple.com is refused', () {
      for (final host in const [
        'evil.example.com',
        'books.apple.com.evil.example.com',
        'apple.com',
      ]) {
        expect(
          appleBookUrlFromLookupJson('''
            { "resultCount": 1, "results": [ {
                "kind": "ebook",
                "trackViewUrl": "https://$host/us/book/x/id1"
            } ] }
          '''),
          isNull,
          reason: '$host was accepted as an Apple Books URL',
        );
      }
    });
  });

  // The title+author fallback exists because Apple's ISBN index is incomplete even
  // for books it sells. It is only safe because of these guards: an unguarded
  // `results[0]` on the live response below returns a third-party study guide.
  group('the title and author search', () {
    test('skips a knock-off above the real edition and finds the book', () {
      expect(
        search(
          _searchWithKnockOffs,
          title: 'The Body Keeps the Score',
          author: 'Bessel van der Kolk',
        ).toString(),
        'https://books.apple.com/us/book/the-body-keeps-the-score/id731076045',
      );
    });

    // The failure this guard is for, stated directly: the first result's title
    // *contains* the real one, and only the author check rejects it.
    test('refuses a summary published under another author', () {
      expect(
        search(
          '''
          { "resultCount": 1, "results": [ { "kind": "ebook",
              "trackName": "The Body Keeps the Score - Summary and Analysis",
              "artistName": "Summary Life",
              "trackViewUrl": "https://books.apple.com/us/book/s/id1" } ] }
          ''',
          title: 'The Body Keeps the Score',
          author: 'Bessel van der Kolk',
        ),
        isNull,
      );
    });

    // The bug this guard was rewritten for. `Dune Messiah` is a *different book
    // by the same author*, so the author check cannot reject it -- only the title
    // comparison can, and an earlier `startsWith` version let it through.
    test('refuses a sequel whose title merely extends the query', () {
      expect(
        search(
          '''
          { "resultCount": 1, "results": [ { "kind": "ebook",
              "trackName": "Dune Messiah", "artistName": "Frank Herbert",
              "trackViewUrl": "https://books.apple.com/us/book/d/id1" } ] }
          ''',
          title: 'Dune',
          author: 'Frank Herbert',
        ),
        isNull,
      );
    });

    test('accepts an edition that appends a subtitle', () {
      expect(
        search(
          '''
          { "resultCount": 1, "results": [ { "kind": "ebook",
              "trackName": "Dune: Book One", "artistName": "Frank Herbert",
              "trackViewUrl": "https://books.apple.com/us/book/d/id1" } ] }
          ''',
          title: 'Dune',
          author: 'Frank Herbert',
        ),
        isNotNull,
      );
    });

    // Apple marks editions in brackets where publisher metadata does not, so a
    // real edition would otherwise be missed for a reason that means nothing.
    test('accepts an edition carrying a bracketed edition marker', () {
      expect(
        search(
          '''
          { "resultCount": 1, "results": [ { "kind": "ebook",
              "trackName": "Dune (Enhanced Edition)",
              "artistName": "Frank Herbert",
              "trackViewUrl": "https://books.apple.com/us/book/d/id1" } ] }
          ''',
          title: 'Dune',
          author: 'Frank Herbert',
        ),
        isNotNull,
      );
    });

    // Apple appends credentials and co-authors, and publishers disagree with
    // Apple about punctuation constantly. None of that means a different book.
    test('tolerates appended credentials and differing punctuation', () {
      expect(
        search(
          _searchWithKnockOffs,
          title: 'the body keeps the score',
          author: 'bessel van der kolk, m.d.',
        ),
        isNotNull,
      );
    });

    // Without an author there is nothing to tell the real edition from a study
    // guide, so an unconfirmable match must not be taken.
    test('refuses to match on title alone when no author is known', () {
      expect(
        search(
          _searchWithKnockOffs,
          title: 'The Body Keeps the Score',
          author: '',
        ),
        isNull,
      );
    });
  });
}
