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

class Book {
  final String id;
  final String userId;
  final String shelfId;
  final String isbn;
  final String title;
  final String thumbnail;
  final int status;
  final int position;
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

  const Book({
    required this.id,
    required this.userId,
    required this.shelfId,
    required this.isbn,
    required this.title,
    required this.thumbnail,
    required this.status,
    required this.position,
    this.rating,
    this.startDate,
    this.finishDate,
    required this.createdAt,
    this.authors = const [],
    this.pageCount,
    this.coverColor,
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
    );
  }

  Book copyWith({
    String? shelfId,
    int? status,
    int? position,
    double? rating,
    DateTime? startDate,
    DateTime? finishDate,
    List<String>? authors,
    int? pageCount,
    Color? coverColor,
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
    );
  }
}
