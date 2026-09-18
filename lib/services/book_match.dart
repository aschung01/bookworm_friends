/// Deciding whether a catalogue record is confidently the book we asked about.
///
/// **Why this is its own file.** It began as private helpers inside
/// `apple_books_lookup.dart`, then `overdrive_lookup.dart` needed the identical
/// judgement against a different catalogue. Two copies of a matcher this
/// subtle — see [sameBook] on why `startsWith` is wrong — is two things to keep
/// in step, and the one that drifts is the one that starts sending readers to the
/// wrong book.
///
/// Both callers feed values straight out of decoded JSON, which is why everything
/// here takes `Object?` rather than `String`: a field that is absent, null or a
/// number is an ordinary response, not a programming error, and it must fold to
/// "cannot be confirmed" rather than throw.
library;

/// Whether a catalogue record is confidently the book that was asked for.
///
/// Title **and** author must both agree; either alone is not enough. Author alone
/// matches every other book by the same writer, and title alone matches every
/// summary, study guide and abridgement that quotes the title — which is not a
/// hypothetical, but the observed behaviour of both live catalogues. Apple returns
/// *"… - Summary and Analysis"* by *Summary Life*; OverDrive returns
/// *"A Joosr Guide to... The Hard Thing about Hard Things"*.
///
/// A record with no author listed **cannot be confirmed at all** and is rejected,
/// even when its title matches perfectly. OverDrive's study-guide entries often
/// carry a null creator, and that is precisely the case where a title-only match
/// would be acted upon.
bool sameBook({
  required Object? candidateTitle,
  required Object? candidateAuthor,
  required String title,
  required String author,
}) {
  final gotTitle = _mainTitle(candidateTitle);
  final wantTitle = _mainTitle(title);
  if (gotTitle.isEmpty || wantTitle.isEmpty) return false;
  if (gotTitle != wantTitle) return false;

  // Catalogues append credentials and co-authors ("Bessel van der Kolk, M.D."),
  // so containment either way is the right test — but an unlisted author leaves
  // nothing to test against.
  final gotAuthor = _fold(candidateAuthor);
  final wantAuthor = _fold(author);
  if (gotAuthor.isEmpty || wantAuthor.isEmpty) return false;
  return gotAuthor.contains(wantAuthor) || wantAuthor.contains(gotAuthor);
}

/// A title reduced to its comparable core.
///
/// **Equality, not `startsWith`, and that is the whole subtlety.** An earlier
/// version accepted any candidate whose folded title began with the query's, to
/// let an edition carrying a subtitle match a bare title. It also accepted
/// *Dune Messiah* for *Dune* — a different book by the same author, so the author
/// check cannot catch it either. Sending a reader to the sequel under a row saying
/// "Opens this book" is precisely the class of failure this file guards.
///
/// So the structure is used rather than thrown away: a subtitle after a colon and
/// a trailing edition marker in brackets are both dropped *before* folding, and
/// what remains must match exactly. `Dune: Book One` reduces to `dune` and matches;
/// `Dune Messiah` reduces to `dunemessiah` and does not.
String _mainTitle(Object? value) {
  if (value is! String) return '';
  // Editions are marked in brackets ("(Enhanced Edition)", "(Unabridged)") where
  // publisher metadata usually does not. `(Unabridged)` in particular is how
  // OverDrive marks a great many audiobooks.
  var s = value.replaceAll(RegExp(r'\s*\([^()]*\)\s*$'), '');
  final colon = s.indexOf(':');
  if (colon > 0) s = s.substring(0, colon);
  return _fold(s);
}

/// Case- and punctuation-insensitive form for comparing titles and names.
///
/// Publishers and catalogues disagree constantly about punctuation and spacing,
/// and none of that disagreement means a different book.
String _fold(Object? value) {
  if (value is! String) return '';
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '')
      .trim();
}
