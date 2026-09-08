/// The one definition, in Dart, of what a handle may be.
///
/// **The same rule the database states, and the pair is the thing most likely to drift.**
/// `supabase/migrations/20260821100303_add_profile_handle.sql` holds
/// `CHECK (handle ~ '^[a-z0-9_]{3,20}$')` and this file holds the same pattern; the SQL
/// half is asserted by `supabase/tests/handle_test.sql` and the agreement between them by
/// `test/profile_handle_test.dart`, which reads the migration off disk rather than
/// trusting a comment.
///
/// It also has to agree with a *third* place: `cardStripToken` in
/// `shareable_library_card.dart`, which is what stands between a display name and a strip
/// nobody can read. That one is deliberately looser \u2014 case-insensitive, because it
/// uppercases for the strip \u2014 so everything this accepts, it accepts.
library;

/// What a handle looks like, as one string used by both the pattern and the message.
const String kHandlePattern = r'^[a-z0-9_]{3,20}$';

const int kHandleMinLength = 3;
const int kHandleMaxLength = 20;

final RegExp _handle = RegExp(kHandlePattern);

/// Why a handle was refused, or [HandleProblem.none].
///
/// An enum rather than a bool, because "invalid" is not an actionable message on a field
/// with four separate ways to be wrong \u2014 and the editor has to say which one.
enum HandleProblem {
  none,

  /// Empty, which is a different state from too short: the reader has not typed yet.
  empty,
  tooShort,
  tooLong,

  /// Anything outside `a-z`, `0-9` and `_` \u2014 which includes uppercase and, most often,
  /// the reader's own name.
  charset,
}

/// Checks [value] against [kHandlePattern] and says what is wrong with it.
///
/// Does **not** trim or lower-case. A handle is stored exactly as it is checked, because
/// one canonical representation is what makes a plain unique index case-insensitive \u2014 see
/// the migration for why `citext` was dropped. The editor lower-cases as the reader types,
/// so silently accepting `PaperFox` here would hide that from them.
HandleProblem handleProblem(String value) {
  if (value.isEmpty) return HandleProblem.empty;
  if (_handle.hasMatch(value)) return HandleProblem.none;
  if (value.length < kHandleMinLength) return HandleProblem.tooShort;
  if (value.length > kHandleMaxLength) return HandleProblem.tooLong;
  return HandleProblem.charset;
}

/// Whether [value] is a handle the database would accept.
bool isValidHandle(String value) => handleProblem(value) == HandleProblem.none;

/// [input] as a handle field should hold it, as the reader types.
///
/// Lower-cases and turns spaces into underscores, and **drops** everything else rather
/// than transliterating it. That is the same refusal `cardStripToken` makes and for the
/// same reason: a Korean name run through a converter comes out as a remnant that reads as
/// a fault. Dropping leaves the field visibly empty, which tells the reader they have to
/// choose something rather than accept a mangling of their name.
///
/// Not truncated to [kHandleMaxLength]: a field that silently stops accepting characters
/// is indistinguishable from a broken keyboard, so length is reported by [handleProblem]
/// instead.
String normaliseHandleInput(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '_')
    .replaceAll(RegExp(r'[^a-z0-9_]'), '');
