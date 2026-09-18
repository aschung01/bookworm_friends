// Resolving an exact OverDrive title id, which is what lets the Libby row name a
// book instead of running a search.
//
// **Every fixture here is real.** The records are copied from live responses for
// *The Hard Thing About Hard Things* — including the study guide that OverDrive
// genuinely returns alongside it — because the failure this file guards is not a
// malformed response, it is a *well-formed response about the wrong book*.
//
// Nothing here touches the network. The two functions under test are the pure
// halves of the lookup, split out for exactly that reason.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/overdrive_lookup.dart';

/// The two records SFPL actually holds for the book: one ebook, one audiobook.
/// **The audiobook is listed first on purpose** — `media/bulk` does not preserve
/// the order of the ids it was sent, so any code that trusted position would pick
/// this one.
const _bothFormats = '''
[ { "id": "1582338",
    "type": { "id": "audiobook", "name": "Audiobook" },
    "title": "The Hard Thing About Hard Things",
    "firstCreatorName": "Ben Horowitz" },
  { "id": "1344919",
    "type": { "id": "ebook", "name": "eBook" },
    "title": "The Hard Thing About Hard Things",
    "firstCreatorName": "Ben Horowitz" } ]
''';

/// The real study guide OverDrive returns for this query, verbatim. Note the null
/// creator: a title-only matcher would have nothing to reject it with.
const _studyGuide = '''
[ { "id": "2623219",
    "type": { "id": "ebook", "name": "eBook" },
    "title": "A Joosr Guide to... the Hard Thing about Hard Things by Ben Horowitz",
    "firstCreatorName": null } ]
''';

const _title = 'The Hard Thing About Hard Things';
const _author = 'Ben Horowitz';

OverDriveResult match(
  String body, {
  List<String> candidates = const ['1582338', '1344919', '2623219'],
  String title = _title,
  String author = _author,
}) => overDriveMatchFromBulkJson(
  body,
  candidates: candidates,
  title: title,
  author: author,
);

void main() {
  group('overDriveCandidateIds', () {
    // A blunt scan, deliberately: every candidate is verified against JSON
    // afterwards, so there is nothing to gain from understanding the markup and
    // fewer ways for a scan to break.
    test('harvests ids in the order the page listed them', () {
      const html = '''
        <a href="/media/1344919/the-hard-thing-about-hard-things">…</a>
        <a href="/media/1582338/the-hard-thing-about-hard-things">…</a>
        <a href="/media/2623219/a-joosr-guide">…</a>
      ''';
      expect(overDriveCandidateIds(html), ['1344919', '1582338', '2623219']);
    });

    // A result links its own id more than once — cover, title and byline all point
    // at it — so duplicates are the normal case, not a malformed page.
    test('collapses the repeats a single result produces', () {
      const html = '''
        <a href="/media/1344919/x"><img src="/media/1344919/cover.jpg"></a>
        <a href="/media/1344919/x">The Hard Thing About Hard Things</a>
      ''';
      expect(overDriveCandidateIds(html), ['1344919']);
    });

    // The ids go into a URL, so the cap is not decorative. 24 is what one page of
    // results actually yields, which is where the number comes from.
    test('caps at one page worth of candidates', () {
      final html = List.generate(
        40,
        (i) => '<a href="/media/${1000 + i}/x">x</a>',
      ).join();
      expect(overDriveCandidateIds(html), hasLength(24));
    });

    // **This is the fail-safe property, and it is why harvesting from HTML is
    // acceptable at all.** A markup change produces no candidates, the lookup
    // returns nothing, and the Libby row falls back to the search it ran before.
    // A markup change can cause a miss; it cannot cause a wrong book.
    test('finds nothing in a page it does not recognise', () {
      expect(overDriveCandidateIds('<html><body>Nope.</body></html>'), isEmpty);
      expect(overDriveCandidateIds(''), isEmpty);
    });

    // A genuine zero-result page really is empty of these links — a nonsense query
    // returns a 200 with no `/media/` anywhere — so there is no navigational
    // chrome that needs filtering out.
    test('is not fooled by a media path with no id', () {
      expect(overDriveCandidateIds('<a href="/media/browse">all</a>'), isEmpty);
    });
  });

  group('overDriveMatchFromBulkJson', () {
    // Rule one: this is a reading app, so where a library lends both, the ebook is
    // the one to open. Asserted against a response that lists the audiobook first.
    test('prefers the ebook when a library lends both', () {
      final result = match(_bothFormats);
      expect(result.titleId, '1344919');
      expect(result.format, OverDriveFormat.ebook);
    });

    // **The bug that was nearly shipped.** An earlier plan filtered to `ebook`
    // only. Libraries lend audiobooks as first-class stock — for this very title,
    // 4 ebook licences against 19 audiobook — so an ebook-only filter reports "no
    // edition" for a book the library demonstrably lends, every single time for an
    // audio-only title.
    test('accepts an audiobook when that is all a library lends', () {
      const audioOnly = '''
        [ { "id": "1582338",
            "type": { "id": "audiobook", "name": "Audiobook" },
            "title": "The Hard Thing About Hard Things",
            "firstCreatorName": "Ben Horowitz" } ]
      ''';
      final result = match(audioOnly);
      expect(result.titleId, '1582338');
      expect(result.format, OverDriveFormat.audiobook);
    });

    // The real knock-off, rejected on both counts: its title is not the book's,
    // and its creator is null so nothing could confirm it even if the title had
    // matched. Taking the first result would have sent the reader to a study guide
    // under a row saying "borrow free from your library".
    test('rejects the study guide OverDrive returns alongside the book', () {
      expect(match(_studyGuide).found, isFalse);
    });

    // Title-only matching is not enough, and this is the case that proves it: the
    // record is the right book by name and there is no author to check it against.
    test('rejects a matching title with no creator listed', () {
      const noCreator = '''
        [ { "id": "1344919",
            "type": { "id": "ebook", "name": "eBook" },
            "title": "The Hard Thing About Hard Things",
            "firstCreatorName": null } ]
      ''';
      expect(match(noCreator).found, isFalse);
    });

    // The sequel trap, which the author check cannot catch because the author is
    // the same person. `startsWith` on folded titles accepted this; equality does
    // not. See `book_match.dart`.
    test('does not accept the sequel for the book', () {
      const messiah = '''
        [ { "id": "9999999",
            "type": { "id": "ebook", "name": "eBook" },
            "title": "Dune Messiah",
            "firstCreatorName": "Frank Herbert" } ]
      ''';
      final result = overDriveMatchFromBulkJson(
        messiah,
        candidates: const ['9999999'],
        title: 'Dune',
        author: 'Frank Herbert',
      );
      expect(result.found, isFalse);
    });

    // The other side of that rule: structure is used rather than thrown away, so a
    // subtitle and an edition marker are dropped before comparing. `(Unabridged)`
    // is how OverDrive marks a great many audiobooks.
    test('sees past a subtitle and an unabridged marker', () {
      const decorated = '''
        [ { "id": "111",
            "type": { "id": "audiobook", "name": "Audiobook" },
            "title": "Dune: Book One of the Dune Chronicles (Unabridged)",
            "firstCreatorName": "Frank Herbert" } ]
      ''';
      final result = overDriveMatchFromBulkJson(
        decorated,
        candidates: const ['111'],
        title: 'Dune',
        author: 'Frank Herbert',
      );
      expect(result.titleId, '111');
    });

    // `magazine` is OverDrive's third type and is not a book. Anything it adds
    // later is rejected the same way rather than guessed at.
    test('ignores types that are not books', () {
      const magazine = '''
        [ { "id": "1344919",
            "type": { "id": "magazine", "name": "Magazine" },
            "title": "The Hard Thing About Hard Things",
            "firstCreatorName": "Ben Horowitz" } ]
      ''';
      expect(match(magazine).found, isFalse);
    });

    // A record we did not ask about has no place in the ranking, and its presence
    // would mean the response is not answering our question.
    test('ignores a record outside the candidates it was sent', () {
      expect(match(_bothFormats, candidates: const ['2623219']).found, isFalse);
    });

    // Where format cannot decide, the search page's order does — that being the
    // only relevance signal available, and the response's own order being no
    // signal at all.
    test('breaks a format tie on the search page order', () {
      const twoEbooks = '''
        [ { "id": "222",
            "type": { "id": "ebook", "name": "eBook" },
            "title": "The Hard Thing About Hard Things",
            "firstCreatorName": "Ben Horowitz" },
          { "id": "111",
            "type": { "id": "ebook", "name": "eBook" },
            "title": "The Hard Thing About Hard Things",
            "firstCreatorName": "Ben Horowitz" } ]
      ''';
      final result = overDriveMatchFromBulkJson(
        twoEbooks,
        candidates: const ['111', '222'],
        title: _title,
        author: _author,
      );
      expect(result.titleId, '111');
    });

    // None of these is evidence of anything, and none may throw: the sheet has to
    // open regardless. Note the object case — this endpoint answers a bare list,
    // unlike Apple's, and an object is what an error page looks like here.
    test('treats an unusable body as no answer', () {
      expect(match('<html>502 Bad Gateway</html>').found, isFalse);
      expect(
        match('{"message": "Must specify at least 1 libraryKey"}').found,
        isFalse,
      );
      expect(match('[]').found, isFalse);
      expect(match('[null, 3, "x"]').found, isFalse);
      expect(match('[{"id": "1344919"}]').found, isFalse);
    });
  });
}
