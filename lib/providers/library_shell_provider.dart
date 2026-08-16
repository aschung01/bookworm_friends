import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/models/profile.dart';

/// State shared by the library shell: which library you are looking at, whether
/// you are rearranging it, and how the "Books read" pile is filtered.
///
/// These were declared privately inside `home_page.dart`, which is the reason
/// that file could not be broken up: every widget in it reads one of them, so
/// extracting any widget meant either exporting the state or dragging the widget
/// back in. They are here so the shell's pieces can live in separate files.

/// Whether the library is being browsed or rearranged.
///
/// Edit mode wiggles the covers, allows drag-reorder between shelves, swaps the
/// bar for manage-shelves and Done, and springs the read-books sheet shut.
enum LibraryMode { library, editLibrary }

final libraryModeProvider = StateProvider.autoDispose<LibraryMode>(
  (ref) => LibraryMode.library,
);

/// Which of the floating tab bar's three tabs is selected.
///
/// A tab switch swaps only the *sheet's contents*. The library behind it is the
/// one persistent background of the whole shell and is never rebuilt, never
/// replaced and never drawn twice — that is the axiom the shell is designed
/// around, and routing tabs through state rather than through a navigator is
/// what keeps it true.
enum LibraryTab { library, friends, card }

final libraryTabProvider = StateProvider.autoDispose<LibraryTab>(
  (ref) => LibraryTab.library,
);

/// The friend whose library is on screen, or `null` for your own.
///
/// Also drives the horizontal pager: your library is page 0 and each followed
/// friend is a page after it.
final selectedFriendProvider = StateProvider.autoDispose<Profile?>(
  (ref) => null,
);

/// Year and month the "Books read" pile is filtered to, where `0` means "all".
///
/// Kept as two separate providers, and as a separate pair per library, because
/// that is exactly what the pre-shell code did and this move is meant to change
/// no behaviour. Two things to know before tidying them:
///
///  * The friend pair is shared by *every* friend, so switching friends inside a
///    visit keeps the filter. Keying a family on the friend's id would give each
///    friend their own filter instead — defensible, but a behaviour change.
///  * `user_library_page.dart` has a third private pair of its own, so a friend's
///    library filters independently depending on whether you reached it through
///    the pager or through that route. Worth resolving when the shell decides
///    whether that page survives, not before.
final readsFilterYearProvider = StateProvider.autoDispose<int>((ref) => 0);
final readsFilterMonthProvider = StateProvider.autoDispose<int>((ref) => 0);

final friendReadsFilterYearProvider = StateProvider.autoDispose<int>(
  (ref) => 0,
);
final friendReadsFilterMonthProvider = StateProvider.autoDispose<int>(
  (ref) => 0,
);
