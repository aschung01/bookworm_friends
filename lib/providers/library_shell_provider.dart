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

/// Year the read view is filtered to, where `0` means all time.
///
/// Month-level filtering is gone: the expanded read view groups by month already,
/// so filtering to one month would leave a grid with a single group in it. What
/// remains is one year per library — yours and, separately, the friend you are
/// visiting.
///
/// The friend pair is shared by *every* friend, so paging between them inside a
/// visit keeps the filter. Keying a family on the friend's id would give each their
/// own; still a behaviour change, still not this change.
final readsFilterYearProvider = StateProvider.autoDispose<int>((ref) => 0);

final friendReadsFilterYearProvider = StateProvider.autoDispose<int>(
  (ref) => 0,
);
