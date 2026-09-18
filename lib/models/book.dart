import 'dart:ui' show Color;

/// Wire format for [Book.coverColor]: six hex digits, with an optional `#`.
///
/// Anchored, so a value with anything either side of the digits is rejected
/// rather than partially parsed.
final RegExp _coverColorHex = RegExp(r'^#?[0-9a-fA-F]{6}$');

/// Parses `books.cover_color` into a [Color].
///
/// Null for three different situations, all of which mean the same thing to the
/// caller: the key is absent (a row written before the column existed), the value
/// is null (never sampled), or the value is not six hex digits.
///
/// **Unparseable is null rather than black.** A bad value should put the book back
/// on the generated-cover fallback, which is a deliberate-looking colour derived
/// from its ISBN, instead of painting its spine a tone no cover ever had. That is
/// the same trade `page_count` makes by clamping an implausible count at the point
/// of use rather than letting the database reject the row.
Color? bookCoverColorFromHex(String? hex) {
  if (hex == null || !_coverColorHex.hasMatch(hex)) return null;
  final digits = hex.startsWith('#') ? hex.substring(1) : hex;
  final rgb = int.parse(digits, radix: 16);
  return Color.fromARGB(255, (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
}

/// Formats a sampled cover colour for storage.
///
/// Alpha is dropped, not encoded: the value is the average of an opaque cover, and
/// a translucent spine is not a state the column needs to represent. Upper case so
/// a row read by hand matches the hex in the design record.
String bookCoverColorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The page a fraction of the way through a book, or null when there is no count
/// to derive one from.
///
/// **The single rounding site, and that is the whole point of it being here.** The
/// band prints this, the percent wheel's rider prints it, and a shelf tooltip may
/// one day print it; if each rounded for itself the same book would show `p.147` in
/// one place and `p.148` in another, which the drawings did before this existed.
///
/// A free function rather than only a getter on [Book] because the wheel needs the
/// page for the percent currently under the reader's thumb, which is not yet stored
/// on any book. Same arithmetic, one copy.
///
/// **Stable across reads, and no longer for the reason it once was.** This used to
/// rest on "the only writer is a 101-stop wheel, so `progress` is always a whole
/// percent". Page mode broke that: it writes `page / pageCount`, which is not a
/// whole percent. Stability now comes from there being exactly one copy of this
/// arithmetic, which was always the load-bearing half.
///
/// The quantisation cost it warned about is also gone where it mattered. In percent
/// mode it still holds — at 320 pages a stop is 3.2 pages, so p.148 is not
/// expressible and a reader aiming at it gets `p.147`, which is why the wheel's
/// rider wears a tilde. In page mode the reader's exact page is stored in
/// [Book.progressPage] and round-trips through here unchanged. See
/// `supabase/migrations/20260918120000_book_progress_page.sql`.
int? bookProgressPage(double? progress, int? pageCount) {
  if (progress == null || pageCount == null) return null;
  return (progress * pageCount).round();
}

class Book {
  final String id;
  final String userId;
  final String shelfId;
  final String isbn;
  final String title;
  final String thumbnail;
  final int status;

  /// Where this book sits on the shelf it belongs to, ascending from 0.
  ///
  /// **Not renamed to `shelf_index`, though the symmetry with [readingShelfIndex] would
  /// read better, and the reason is compatibility rather than taste.** [Book.fromJson]
  /// falls back to `0` when the key is absent, which exists so a row written before a
  /// column did still parses. Rename the column and *every already-installed build* reads
  /// this as absent instead: all books collapse to 0, the sort in `LibraryNotifier`
  /// degenerates into arbitrary order, and `update({'position': i})` starts returning 400.
  /// Adding a column is backward compatible; renaming one is a hard break, so a rename has
  /// to be an expand/contract migration and not a tidy-up.
  ///
  /// A Reading-shelf reorder never writes this. See [readingShelfIndex].
  final int position;

  /// Where this book sits on the Reading shelf, ascending from 0, or null when it has no
  /// place there — which is every book not at `bookStatusReading`.
  ///
  /// **Separate from [position] because the Reading shelf is a view over several shelves.**
  /// `position` means "place within my own shelf", so two open books lifted from different
  /// planks can hold the same one and there is no single row for it to order. Writing
  /// `position` from a Reading-shelf drag would also spend `withoutReadingBooks`' promise
  /// that clearing a book's status puts it back on its plank *in the position it was
  /// authored in* — the documented wart that retiring `withReadingFirst` removed.
  ///
  /// **Named for the shelf it indexes, not `readingPosition`**, which in a reading app
  /// reads as progress through the text rather than as an ordinal among covers.
  ///
  /// Not unique, and may be negative: opening a book writes `min - 1` so it lands at the
  /// head of the shelf in one UPDATE instead of shifting every other row, and the next
  /// reorder renumbers the set to `0…n-1`. Nulls sort last, falling back to shelf order.
  ///
  /// **A stale value here is harmless and is left alone deliberately.** Leaving the Reading
  /// shelf nulls the column in the database but not on the local object, because
  /// [copyWith] cannot clear a nullable field (see the note there) and nothing needs it to:
  /// a book at status 0 or 2 is filtered off the Reading shelf, so the value is invisible,
  /// and re-opening the book overwrites it with a fresh head slot.
  final int? readingShelfIndex;
  final double? rating;
  final DateTime? startDate;
  final DateTime? finishDate;
  final DateTime createdAt;

  /// Authors as the catalogue lists them, first one first.
  ///
  /// Empty means "no author to show" — never null, so a reader does not have to
  /// tell a book with no listed author from one that predates the column. Stored
  /// rather than re-fetched because the Library Card counts authors across a whole
  /// library, and doing that from the catalogue would be one request per book.
  final List<String> authors;

  /// Pages, when the catalogue supplied a credible count. Null means unknown.
  ///
  /// Nullable, unlike [authors], and the difference is load-bearing rather than
  /// stylistic: the app genuinely behaves differently for the two states. A count
  /// sets the book's drawn thickness; null falls back to a hash of the ISBN. The
  /// `authors` column is `NOT NULL DEFAULT '{}'` because nothing distinguishes
  /// "never backfilled" from "no author listed" downstream. Here something does.
  ///
  /// Stored rather than fetched on open, so a book cannot change thickness while
  /// it is on screen.
  final int? pageCount;

  /// Average colour of the cover, once something has decoded it. Null means it
  /// has never been sampled.
  ///
  /// Nullable for the same reason [pageCount] is, and not for the reason
  /// [authors] is not: the two states drive different code. A colour tones the
  /// book's spine in the read pile and its back board on the shelves; null falls
  /// back to a swatch derived from the ISBN, which needs no network and is
  /// therefore available on the first frame.
  ///
  /// **Stored rather than sampled where it is used**, which is the whole point of
  /// the column. `_sampleCoverColor` only has an answer once the image resolves,
  /// so a pile that sampled would paint a colourless row on a cold start and
  /// colour it in as the streams landed — a book visibly changing colour while on
  /// screen, which is exactly the defect the stored [pageCount] exists to avoid.
  final Color? coverColor;

  /// Which shop or reader app the owner's copy lives in, or null when nothing is
  /// known. See `store_links_service.dart` for what each shop can actually reach.
  ///
  /// Nullable for the same reason [pageCount] and [coverColor] are, and not for
  /// the reason [authors] is not: the two states drive different UI. Null shows
  /// the acquire list, with every shop labelled by what a tap arrives at; a value
  /// shows one Open action and retitles the sheet.
  ///
  /// **A hint, not a fact.** It is inferred from the owner tapping a shop, and a
  /// tap is not a purchase — somebody checking Kindle's price and not buying is
  /// recorded identically to somebody buying. That is why the sheet always offers
  /// a way to clear it, and why nothing anywhere treats a value here as proof the
  /// reader owns anything.
  ///
  /// Typed as a [String] rather than a `StoreId`, deliberately. The column has no
  /// CHECK constraint so that a build can ignore a key it does not know, and
  /// parsing at this boundary would throw away the difference between "absent" and
  /// "present but unrecognised" before the UI could apply that rule. Callers pass
  /// this through `storeIdFromKey`, which maps both to null.
  final String? readerApp;

  /// How far through the book the owner is, as a fraction 0..1, or null when
  /// nothing has been recorded.
  ///
  /// **Null is not `0`, and the difference is drawn rather than academic:** null
  /// means "never set" and shows no bar and no ribbon offset, while `0.0` means "at
  /// the very start" and shows an empty bar. An empty track is a claim — it says
  /// the reader began and got nowhere — and every one of the 109 reading books in
  /// production would make that claim on the day this shipped. Nullable for the
  /// reason [pageCount] and [coverColor] are, and not for the reason [authors] is
  /// not: something downstream really does tell the two states apart.
  ///
  /// **A fraction rather than a page number**, because `page_count` is null for
  /// about two reading books in three and the catalogue has no page field to
  /// improve that. A `currentPage` would be unusable for the majority of books and
  /// every surface reading it would need a second design for that majority. The
  /// page is a derived *label* instead — see [approxPage].
  ///
  /// **Unrelated to [position] and to [readingShelfIndex]**, both of which only
  /// sound like this one. `position` is shelf order, `readingShelfIndex` is Reading
  /// shelf order, and this is a place in the text. Three integers-shaped facts with
  /// three meanings is exactly why this is not called `readingPosition`.
  final double? progress;

  /// The page the reader typed, or null if they answered in percent.
  ///
  /// **Provenance, not position.** [progress] is the position, and a page stored as
  /// `page / pageCount` round-trips exactly, so this field is not how the app knows
  /// where the reader is. It exists so `ProgressFieldRow` can print `p.200` to a
  /// reader who said p.200 and `46%` to one who said 46% — their own answer in their
  /// own unit.
  ///
  /// **It cannot be inferred from [progress]**, which is the finding that forced the
  /// column. Percent mode writes `stop / 100`, so `progress * 100` lands on a whole
  /// number; a page entry usually does not. Usually is not good enough. Counted over
  /// every page of a book, a page entry is indistinguishable from a percent for 0.9%
  /// of a 432-page book, 6.25% of a 320-page one, **50% of a 200-page one and 100%
  /// of a 100-page one** — `page / 100` is always a whole percent.
  ///
  /// Null on every book written before the column existed, and on every book whose
  /// position was set in percent, which are treated identically and should be.
  final int? progressPage;

  const Book({
    required this.id,
    required this.userId,
    required this.shelfId,
    required this.isbn,
    required this.title,
    required this.thumbnail,
    required this.status,
    required this.position,
    this.readingShelfIndex,
    this.rating,
    this.startDate,
    this.finishDate,
    required this.createdAt,
    this.authors = const [],
    this.pageCount,
    this.coverColor,
    this.readerApp,
    this.progress,
    this.progressPage,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      shelfId: json['shelf_id'] as String,
      isbn: json['isbn'] as String,
      title: json['title'] as String,
      thumbnail: json['thumbnail'] as String,
      status: json['status'] as int,
      position: json['position'] as int? ?? 0,
      // Absent on rows written before the column existed, and null on every book that is
      // not in progress. Unlike `page_count` there is nothing to normalise: 0 is a real
      // head-of-shelf value and a negative one is produced on purpose.
      readingShelfIndex: (json['reading_shelf_index'] as num?)?.toInt(),
      rating: (json['rating'] as num?)?.toDouble(),
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : null,
      finishDate: json['finish_date'] != null
          ? DateTime.parse(json['finish_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      // Defensive on both counts: a row written before the column existed has no
      // key, and Postgres hands a `text[]` back as `List<dynamic>`.
      authors:
          (json['authors'] as List<dynamic>?)
              ?.map((a) => a as String)
              .toList() ??
          const [],
      // Absent on rows written before the column existed, and Postgres hands an
      // `int4` back as `num` through some codecs. A non-positive value is treated
      // as unknown for the same reason the Google provider normalises it.
      pageCount: switch ((json['page_count'] as num?)?.toInt()) {
        final int p when p > 0 => p,
        _ => null,
      },
      // Absent on rows written before the column existed, and null on any row
      // whose cover has never been decoded. See [bookCoverColorFromHex] for why a
      // malformed value is treated as absent rather than as a colour.
      coverColor: bookCoverColorFromHex(json['cover_color'] as String?),
      // Absent on rows written before the column existed, and null on every book
      // nobody has tapped a shop for. Not validated here — see [readerApp].
      readerApp: json['reader_app'] as String?,
      // Absent on rows written before the column existed, and null on every book
      // nobody has set a position for — treated identically, so an older build's
      // row parses as "nothing recorded" rather than as page one. Postgres hands
      // `real` back as `num` through some codecs, hence the widening. Unlike
      // `page_count` there is nothing to normalise: the column's own CHECK keeps
      // the value inside 0..1, and 0 is a real value here rather than absence.
      progress: (json['progress'] as num?)?.toDouble(),
      // Absent on rows written before the column existed, and null on every book
      // whose position was set in percent — the same thing as far as every reader of
      // this field is concerned. Widened from `num` for the reason `page_count` is.
      // Not normalised against `pageCount`: the column's CHECK keeps it >= 1, and a
      // value past a *later-corrected* count is still the page the reader said.
      progressPage: (json['progress_page'] as num?)?.toInt(),
    );
  }

  /// The page this position lands on, or null when the catalogue gave no count.
  ///
  /// **Approximate, and named for it.** Was `progressPage`, which now belongs to the
  /// page the reader actually typed; this is the one derived by arithmetic, and in
  /// percent mode it is off by up to half a stop — which is why the wheel's rider
  /// prints it behind a tilde. Delegates to [bookProgressPage] so the rounding lives
  /// in exactly one place.
  ///
  /// Prefer [progressPage] when it is non-null: it is what the reader said, where
  /// this is what the arithmetic makes of it.
  int? get approxPage => bookProgressPage(progress, pageCount);

  Book copyWith({
    String? shelfId,
    int? status,
    int? position,
    int? readingShelfIndex,
    double? rating,
    DateTime? startDate,
    DateTime? finishDate,
    List<String>? authors,
    int? pageCount,
    Color? coverColor,
    String? readerApp,
    double? progress,
    int? progressPage,
  }) {
    return Book(
      id: id,
      userId: userId,
      shelfId: shelfId ?? this.shelfId,
      isbn: isbn,
      title: title,
      thumbnail: thumbnail,
      status: status ?? this.status,
      position: position ?? this.position,
      readingShelfIndex: readingShelfIndex ?? this.readingShelfIndex,
      rating: rating ?? this.rating,
      startDate: startDate ?? this.startDate,
      finishDate: finishDate ?? this.finishDate,
      createdAt: createdAt,
      authors: authors ?? this.authors,
      pageCount: pageCount ?? this.pageCount,
      // In the signature, unlike `isbn` or `thumbnail`, because this one really
      // does change after a row is written: the first widget to decode the cover
      // reports the sample back and it is stored. Like every other nullable field
      // here it can be set but not cleared, which is all any caller needs.
      coverColor: coverColor ?? this.coverColor,
      // Set but not cleared, like every other nullable field here. Clearing is a
      // real operation for this one — the sheet offers it — but it goes through a
      // refetch rather than through `copyWith`, because the write and the local
      // object would otherwise disagree about what null means. See
      // [Book.readingShelfIndex] for the same trade made the other way.
      readerApp: readerApp ?? this.readerApp,
      // Set but not cleared, like every other nullable field here. Clearing a
      // position is not an operation any surface offers: the wheel's lowest stop is
      // 0%, which means "at the very start" and is a value, not an erasure.
      progress: progress ?? this.progress,
      // Same, and here the limitation is load-bearing rather than incidental:
      // answering in percent must *clear* this field, and that clearing happens in
      // the UPDATE and comes back through a refetch — never through `copyWith`,
      // which cannot express it. See [readerApp] for the same trade.
      progressPage: progressPage ?? this.progressPage,
    );
  }
}
