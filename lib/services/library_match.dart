/// Matching a reader's own books against what they typed, and a catalogue result
/// against what they already own.
///
/// Kept apart from the search sheet for the reason `isbn.dart` is kept apart from
/// the scanner: the rules are text arithmetic, not UI. They are also the part of
/// library search most likely to be wrong in a way nobody notices, because every
/// failure looks the same from the outside — an empty section, indistinguishable
/// from not owning the book. So they are testable without pumping a widget.
library;

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/services/isbn.dart';

/// Everything a comparison should ignore: case, spacing, and the punctuation a
/// catalogue sprinkles through a title.
///
/// Deliberately strips whitespace rather than collapsing it, so `해리 포터` and
/// `해리포터` are the same string. Korean titles are spaced inconsistently between
/// providers and by readers typing them, and a space is never the thing someone
/// meant to search for.
final RegExp _ignorable = RegExp(
  r'[\s\.,:;!?\-–—_/\\()\[\]{}"'
  r"'’“”·`~]+",
);

/// Lower-cased, stripped of [_ignorable]. The form every comparison happens in.
String normaliseForMatch(String raw) =>
    raw.toLowerCase().replaceAll(_ignorable, '');

/// The nineteen Hangul lead consonants, in the order the syllable block encodes
/// them — *not* the order of the compatibility-jamo block, which interleaves
/// vowels and final-only consonants and cannot be indexed arithmetically.
///
/// A syllable at U+AC00..U+D7A3 encodes its lead as `(code - 0xAC00) ~/ 588`,
/// which indexes straight into this string.
const String kHangulLeads = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';

const int _syllableBase = 0xAC00;
const int _syllableLast = 0xD7A3;
const int _leadStride = 588; // 21 vowels * 28 finals

/// [raw] with every Hangul syllable replaced by its lead consonant.
///
/// Non-Hangul is carried through normalised, so a mixed title still matches on
/// its Latin part: `해리포터 2` yields `ㅎㄹㅍㅌ2`.
String hangulInitials(String raw) {
  final out = StringBuffer();
  for (final code in normaliseForMatch(raw).runes) {
    if (code >= _syllableBase && code <= _syllableLast) {
      out.write(kHangulLeads[(code - _syllableBase) ~/ _leadStride]);
    } else {
      out.writeCharCode(code);
    }
  }
  return out.toString();
}

/// Whether [query] is written entirely in lead consonants, i.e. is a 초성 search.
///
/// **The distinction matters and cannot be skipped.** `한강` is a real word and
/// must match by substring; `ㅎㄱ` is an abbreviation and must match by initials.
/// Running both unconditionally would let `ㅎ` match every book whose title
/// merely *contains* ㅎ as a bare jamo, which is nothing.
///
/// False for an empty query, so an empty field never enters initials mode.
bool isChoseongQuery(String query) {
  final q = normaliseForMatch(query);
  if (q.isEmpty) return false;
  return q.runes.every((c) => kHangulLeads.contains(String.fromCharCode(c)));
}

/// Whether [book] answers [query], across its title and its authors.
///
/// Substring rather than prefix, because a reader searching their own shelves is
/// as likely to remember a word from the middle of a title as its first one.
///
/// **Publisher is not matched, and cannot be:** [Book] does not store one. Worth
/// knowing because the catalogue half of the same field *does* search publishers
/// (`searchBookPlaceholder` advertises it), so the two halves of one query are
/// not searching identical fields. Title and authors are the overlap.
bool bookMatchesQuery(Book book, String query) {
  final q = normaliseForMatch(query);
  if (q.isEmpty) return false;

  final haystacks = [book.title, ...book.authors];
  if (isChoseongQuery(query)) {
    return haystacks.any((h) => hangulInitials(h).contains(q));
  }
  return haystacks.any((h) => normaliseForMatch(h).contains(q));
}

/// The reader's own books that answer [query], across every shelf.
///
/// **In-progress books first, then unread, then finished** — a stable partition
/// and not a sort, and the reason is worth restating here now that the function that
/// used to record it has been deleted: `List.sort` is not stable in Dart, so two books
/// that compare equal would swap places between keystrokes for no reason a reader could
/// account for. Within each group the shelves' own order survives.
///
/// (The deleted function was `withReadingFirst`, which promoted an open book to the head
/// of its own shelf row. The library draws those books on the Reading shelf instead — see
/// `withoutReadingBooks` — but *this* list is a search result rather than a shelf, so it
/// still ranks by status, and this is the last place that partition survives.)
///
/// The order is a judgement about usefulness rather than about the data: what a
/// reader is most likely to act on is the book they are in the middle of, and
/// what they are least likely to need is the one they finished years ago — but
/// the [Book.status] badge on each row is what actually answers the question, so
/// this only decides who is nearest the top.
List<Book> searchOwnLibrary(Iterable<Shelf> shelves, String query) {
  final matches = [
    for (final shelf in shelves)
      for (final book in shelf.books)
        if (bookMatchesQuery(book, query)) book,
  ];
  return [
    ...matches.where((b) => b.status == bookStatusReading),
    ...matches.where(
      (b) => b.status != bookStatusReading && b.status != bookStatusFinished,
    ),
    ...matches.where((b) => b.status == bookStatusFinished),
  ];
}

/// How confident the app is that a catalogue result is a book the reader owns.
///
/// The tiers exist because the two mistakes cost wildly different amounts. A
/// duplicate *shown* costs one redundant cover the reader ignores; a book the
/// reader wanted and never saw costs the whole feature, with no recourse and no
/// explanation — it reads as the catalogue not having it. So only [identical],
/// which is not an approximation, is allowed to hide anything.
enum OwnedVerdict {
  /// No book in the library looks like this one. Draw it plainly.
  none,

  /// Same title and a shared author, but the identifiers differ — so this is
  /// either a genuinely different edition, which is a legitimate thing to add,
  /// or the same edition wearing an identifier one provider got wrong. The app
  /// cannot tell which, so it is **kept and tagged**, never hidden.
  probable,

  /// The same ISBN, once both sides are put through [normalisedIsbn13]. Provably
  /// the same edition as a row already drawn in the reader's own section, so it
  /// is **suppressed** — and needs no "results hidden" disclosure, because the
  /// only thing removed is a duplicate of something visible above.
  identical,
}

/// Whether [result] is already in [library], and how sure we are.
///
/// Checks every book before returning, rather than short-circuiting on the first
/// hit, because a [OwnedVerdict.identical] anywhere in the library outranks a
/// [OwnedVerdict.probable] found earlier — and the earlier one would otherwise
/// leave a provably-duplicate cover on screen.
OwnedVerdict ownedVerdictFor(BookSearchResult result, Iterable<Book> library) {
  final resultIsbn = normalisedIsbn13(result.isbn);
  final resultRawIsbn = result.isbn.trim();
  final resultTitle = normaliseForMatch(result.title);
  final resultAuthors = result.authors.map(normaliseForMatch).toSet();

  var best = OwnedVerdict.none;
  for (final book in library) {
    // Identifiers first. Two normalised ISBN-13s, or — for a result carrying a
    // provider's own id rather than an ISBN — two identical raw strings, which
    // is the same Google volume saved twice.
    final bookIsbn = normalisedIsbn13(book.isbn);
    final byIsbn = resultIsbn != null && bookIsbn != null
        ? resultIsbn == bookIsbn
        : resultRawIsbn.isNotEmpty && resultRawIsbn == book.isbn.trim();
    if (byIsbn) return OwnedVerdict.identical;

    if (resultTitle.isEmpty) continue;
    if (normaliseForMatch(book.title) != resultTitle) continue;
    // Equality, not containment: `Dune` must not swallow `Dune Messiah`.
    //
    // With authors on both sides, one shared name is enough — providers disagree
    // about order, transliteration and how many contributors to list. With
    // authors on *neither* side, or missing from one, the title carries it
    // alone: `books.authors` is `NOT NULL DEFAULT '{}'`, so an empty list means
    // "none listed" and "never backfilled" alike, and treating that as a
    // mismatch would silently stop tagging every row written before the column
    // existed.
    final authorsAgree =
        resultAuthors.isEmpty ||
        book.authors.isEmpty ||
        book.authors.map(normaliseForMatch).any(resultAuthors.contains);
    if (authorsAgree) best = OwnedVerdict.probable;
  }
  return best;
}
