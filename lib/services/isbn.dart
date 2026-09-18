/// Turning what a barcode reader hands back into an ISBN worth looking up.
///
/// Kept apart from both the scanner and the catalogue because the rules are
/// arithmetic, not UI: they are the one part of the scan path that can be tested
/// without a camera, and the camera is the part no simulator has.
library;

/// The two EAN-13 prefixes assigned to books ("Bookland").
///
/// 978 is the original; 979 was added when 978 filled up, and in practice covers
/// music (979-0) and the newer publisher ranges. Filtering on these is what
/// separates a book from every other EAN-13 a supermarket shelf might have in
/// frame, and it is also what settles the ordinary two-symbol case for a Korean
/// book: the 5-digit 부가기호 printed beside the ISBN is not 13 digits at all.
const Set<String> kBooklandPrefixes = {'978', '979'};

/// Whether [digits] satisfies the EAN-13 check digit.
///
/// Weights alternate 1 and 3 from the left across the first twelve digits; the
/// thirteenth is whatever makes the total a multiple of ten.
///
/// Worth doing even though the reader has already error-corrected: a partially
/// occluded symbol can decode to thirteen plausible digits, and the cost of
/// being wrong is a catalogue lookup that silently misses and a user told their
/// book does not exist. Cheaper to reject it here and keep scanning.
bool isValidEan13(String digits) {
  if (digits.length != 13) return false;
  var sum = 0;
  for (var i = 0; i < 13; i++) {
    final code = digits.codeUnitAt(i);
    if (code < 0x30 || code > 0x39) return false;
    final value = code - 0x30;
    sum += i.isEven ? value : value * 3;
  }
  return sum % 10 == 0;
}

/// The ISBN in [raw], or null if it is not one.
///
/// Accepts the separators a human-readable line under a symbol may carry, since
/// the same function is useful for a typed value. Rejects anything that is not
/// thirteen digits, does not start with a Bookland prefix, or fails its check
/// digit.
String? isbnFromBarcode(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (!isValidEan13(digits)) return null;
  if (!kBooklandPrefixes.contains(digits.substring(0, 3))) return null;
  return digits;
}

/// The EAN-13 check digit for [twelve], which must be twelve digits.
///
/// The inverse of the sum [isValidEan13] checks: same alternating 1/3 weights,
/// solved for the digit that takes the total to a multiple of ten.
int _ean13CheckDigit(String twelve) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final value = twelve.codeUnitAt(i) - 0x30;
    sum += i.isEven ? value : value * 3;
  }
  return (10 - sum % 10) % 10;
}

/// [raw] as thirteen digits, or null if it is not an ISBN at all.
///
/// **Exists because `books.isbn` is not a normalised column, and comparing it to
/// a catalogue result by string is therefore wrong.** A scanned book stores a
/// validated ISBN-13; `GoogleBooksSearchProvider._mapVolume` prefers ISBN-13 but
/// falls back to ISBN-10 and then to the *volume id*; Open Library takes the
/// first ISBN in a list that may hold either length. So the same book can be
/// held under two different strings, and telling "you already own this" from
/// "this is a different edition" needs both sides put in one form first.
///
/// Accepts an ISBN-10 and converts it (prefix 978, recompute the check digit),
/// which is the case that actually matters — Google hands back ten digits often
/// enough that ignoring it would make exact matching miss most of the time.
///
/// **Deliberately does not verify the check digit of a 13-digit input**, unlike
/// [isbnFromBarcode]. That function guards a *decode*, where a bad digit means a
/// misread symbol worth rejecting. This one reads values already stored by
/// providers of varying quality, and refusing to compare two identical strings
/// because a publisher's metadata has a typo in it would be the wrong trade: the
/// caller only wants to know whether these are the same book.
///
/// Returns null for a Google volume id (`zyTCAlFPjgYC`) and for anything else
/// that is not an ISBN, which callers read as "no identifier to compare".
String? normalisedIsbn13(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (trimmed.length == 13) {
    return RegExp(r'^\d{13}$').hasMatch(trimmed) ? trimmed : null;
  }
  if (trimmed.length == 10) {
    // The tenth character of an ISBN-10 is a check digit over a different
    // modulus and can be an X; it is discarded rather than converted, because
    // the 13-digit form recomputes its own.
    if (!RegExp(r'^\d{9}[\dX]$').hasMatch(trimmed)) return null;
    final body = '978${trimmed.substring(0, 9)}';
    return '$body${_ean13CheckDigit(body)}';
  }
  return null;
}

/// Picks the ISBN to use out of everything found in one frame.
///
/// Two symbols in frame is the ordinary case for a Korean book rather than an
/// error — the ISBN and the 5-digit 부가기호 sit side by side — so this resolves
/// rather than reporting a conflict. [isbnFromBarcode] rejects the add-on for
/// free, which settles almost every real frame.
///
/// [distancesFromCentre] optionally supplies, per candidate, how far that
/// symbol's centre sat from the middle of the scan window. It is only consulted
/// for the genuinely rare tie of two separate books in shot; the shorter
/// distance wins, on the reasoning that a user aims at the thing they mean.
/// Without it, the first valid candidate wins.
String? chooseIsbn(
  Iterable<String?> raw, {
  Map<String, double>? distancesFromCentre,
}) {
  final candidates = <String>[];
  for (final value in raw) {
    final isbn = isbnFromBarcode(value);
    if (isbn != null && !candidates.contains(isbn)) candidates.add(isbn);
  }
  if (candidates.isEmpty) return null;
  if (candidates.length == 1 || distancesFromCentre == null) {
    return candidates.first;
  }
  candidates.sort((a, b) {
    final da = distancesFromCentre[a];
    final db = distancesFromCentre[b];
    // A candidate with no measurement sorts last rather than winning by accident.
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });
  return candidates.first;
}

/// Groups an ISBN-13 the way the line under the symbol does.
///
/// Shown on the scanner the moment a symbol locks, before any lookup: thirteen
/// digits appearing is the cheapest possible proof that the thing you pointed at
/// is the thing it read. The grouping is the standard 978-89-546-9991-4 shape and
/// is presentational only — never send this to a provider.
String formatIsbnForDisplay(String isbn) {
  if (isbn.length != 13) return isbn;
  return '${isbn.substring(0, 3)} ${isbn.substring(3, 5)} '
      '${isbn.substring(5, 8)} ${isbn.substring(8, 12)} ${isbn.substring(12)}';
}
