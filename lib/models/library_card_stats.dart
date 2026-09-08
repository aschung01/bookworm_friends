import 'package:bookworm_friends/models/book.dart';

/// How many books one author must have before the Library Card names them.
///
/// Two, and this is the single most load-bearing constant on the card. With a
/// floor of one, "most-read author" is whoever wrote any book you happened to
/// finish — which is not a fact about your reading, it is a fact about the
/// arbitrary ordering of a tie. Measured against the real corpus: of the 53 users
/// with resolvable author data, **40 have a top author with exactly one book**. A
/// floor of one would show all 53 of them a tile that means nothing, so the tile
/// is absent for those 40 instead.
const int kTopAuthorFloor = 2;

/// Everything the Library Card displays, and nothing else.
///
/// Deliberately a plain value type with no formatting and no placeholders: a field
/// is either a real figure or it is absent, and the widget decides how absence is
/// drawn. The alternative — returning `'—'` or `0` for "unknown" — is how a card
/// ends up confidently displaying a zero it does not know.
class LibraryCardStats {
  /// Books finished in the selected window. The hero figure.
  final int booksRead;

  /// Days spent reading: the sum of every *real* span.
  ///
  /// Sum of spans, not the elapsed time from your first book to your last. The
  /// elapsed version grows while you read nothing, so a reader who stopped a year
  /// ago would watch this figure climb — which is the opposite of what a reading
  /// stat should do.
  final int daysReading;

  /// How many books contributed a real span, and therefore what [pace] averages
  /// over.
  ///
  /// Exposed rather than derived inside the widget, because the tile shows it and
  /// the two must not be able to disagree.
  final int paceSampleSize;

  /// The author of the most finished books, or null when nothing clears
  /// [kTopAuthorFloor].
  final String? topAuthor;

  /// How many books [topAuthor] wrote. `0` when there is no top author.
  final int topAuthorCount;

  const LibraryCardStats({
    required this.booksRead,
    required this.daysReading,
    required this.paceSampleSize,
    required this.topAuthor,
    required this.topAuthorCount,
  });

  static const empty = LibraryCardStats(
    booksRead: 0,
    daysReading: 0,
    paceSampleSize: 0,
    topAuthor: null,
    topAuthorCount: 0,
  );

  /// Average days per book, over books that have a real span. Null when none do.
  double? get pace => paceSampleSize == 0 ? null : daysReading / paceSampleSize;

  /// Whether the pace tile has anything true to say.
  bool get hasPace => paceSampleSize > 0;

  /// Whether the author tile has anything true to say.
  bool get hasTopAuthor => topAuthor != null;

  /// Whether the card has any tile at all beyond the hero.
  bool get hasAnyTile => hasPace || hasTopAuthor;
}

/// The number of days a book took, or null when the book cannot say.
///
/// **A same-day pair is unknown, not zero.** `book_info_bottom_sheet.dart` sets
/// both dates to today when a book is flipped straight to finished, so
/// `start == finish` means "logged as read" far more often than it means "read in
/// one sitting". In the migrated corpus 168 of 293 finished books are same-day,
/// and treating those as zero-day reads would make the pace tile read `0d` for 29
/// of the 55 users who have finished anything — including the heaviest reader,
/// whose 28 books are all same-day.
///
/// So the span is only counted when the finish date is strictly later than the
/// start. Books that cannot say are excluded from both the sum and the divisor,
/// and the tile reports how many were left.
int? bookReadingSpanDays(Book book) {
  final start = book.startDate;
  final finish = book.finishDate;
  if (start == null || finish == null) return null;
  final days = finish.difference(start).inDays;
  return days > 0 ? days : null;
}

/// The books the Library Card is about, for a given [year].
///
/// Extracted so the cover row cannot disagree with the hero figure printed above it.
/// [libraryCardStats] applies this same selection to count books; `CardCoverRow` gets
/// the list itself, and one rule serves both. `0` is all time, matching
/// `ReadFilter`'s convention.
///
/// Behaviour is unchanged from the inline filter this replaces — including that it
/// returns [books] itself, not a copy, at `year == 0`.
List<Book> booksInCardYear(List<Book> books, int year) =>
    year == 0 ? books : books.where((b) => b.finishDate?.year == year).toList();

/// Derives the Library Card's figures from a list of finished books.
///
/// A pure function over a list, not a provider that queries. Phase 2 already made
/// `finishedBooksProvider` fetch the whole finished set — and said in its own doc
/// comment why it has to — so the card needs no query of its own, and every figure
/// here is testable against a fixture list with no Supabase in the room.
///
/// [year] filters by finish year; `0` is all time, matching `ReadFilter`'s
/// convention so the Card and the read view cannot disagree about what a year
/// means.
LibraryCardStats libraryCardStats(List<Book> books, {int year = 0}) {
  final selected = booksInCardYear(books, year);

  if (selected.isEmpty) return LibraryCardStats.empty;

  var daysReading = 0;
  var paceSampleSize = 0;
  for (final book in selected) {
    final span = bookReadingSpanDays(book);
    if (span != null) {
      daysReading += span;
      paceSampleSize++;
    }
  }

  // First author only. A multi-author book is credited to whoever is listed
  // first, which is the primary author in Kakao's ordering. Crediting every
  // listed author instead would let one twelve-contributor anthology outvote a
  // novelist you actually read three times.
  final counts = <String, int>{};
  final latestFinish = <String, DateTime>{};
  for (final book in selected) {
    if (book.authors.isEmpty) continue;
    final author = book.authors.first.trim();
    if (author.isEmpty) continue;
    counts[author] = (counts[author] ?? 0) + 1;
    final finish = book.finishDate;
    if (finish != null) {
      final known = latestFinish[author];
      if (known == null || finish.isAfter(known)) latestFinish[author] = finish;
    }
  }

  String? topAuthor;
  var topAuthorCount = 0;
  for (final entry in counts.entries) {
    if (entry.value > topAuthorCount) {
      topAuthor = entry.key;
      topAuthorCount = entry.value;
    } else if (entry.value == topAuthorCount && topAuthor != null) {
      // Ties break on whoever you finished most recently. Without this the winner
      // is decided by map iteration order, which is insertion order here — so the
      // tile would silently depend on the order rows came back from Postgres and
      // could change between two identical loads.
      final challenger = latestFinish[entry.key];
      final holder = latestFinish[topAuthor];
      if (challenger != null &&
          (holder == null || challenger.isAfter(holder))) {
        topAuthor = entry.key;
      }
    }
  }

  final clearsFloor = topAuthorCount >= kTopAuthorFloor;

  return LibraryCardStats(
    booksRead: selected.length,
    daysReading: daysReading,
    paceSampleSize: paceSampleSize,
    topAuthor: clearsFloor ? topAuthor : null,
    topAuthorCount: clearsFloor ? topAuthorCount : 0,
  );
}
