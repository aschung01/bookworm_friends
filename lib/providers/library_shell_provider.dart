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
/// Edit mode wiggles the covers, turns every one of them into a long-press drag
/// that can reorder its own shelf or move to another, swaps the bar for
/// manage-shelves and a confirm check, hides the floating tab bar, and takes
/// whichever sheet is on screen off the bottom of it — the shelves it was standing
/// on are ones a drag has to be able to reach. See `HomePage._hiddenWhileEditing`.
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
/// **The only thing that decides whose library you are looking at.** It used to
/// share that job with a `PageView`'s index — your library was page 0 and each
/// followed friend a page after it, so a lateral drag and this provider could
/// each move the other. Both the pager and the `FriendRail` above it are gone;
/// the shell reads this and nothing else, which is what makes the persistent
/// background an actual fact of the tree rather than a convention the pager
/// happened to honour.
///
/// **Locked to the Friends tab.** A visit is only ever entered from the Friends
/// sheet, and selecting Library or Card clears this — see `ShellChrome._selectTab`,
/// which is the one place that behaviour lives. So `selectedFriend != null`
/// implies [libraryTabProvider] is [LibraryTab.friends]. That invariant is the
/// whole navigation design in one line: all three tabs always mean *yours*, and
/// everything about a friend is one level down the Friends tab.
final selectedFriendProvider = StateProvider.autoDispose<Profile?>(
  (ref) => null,
);

/// Which level the Friends tab's sheet is showing.
///
/// [list] is everyone you follow — the switcher. [friend] is the books read by
/// whoever [selectedFriendProvider] names.
enum FriendsSheetLevel { list, friend }

/// **Not derivable from [selectedFriendProvider], which is why it exists.**
///
/// Coming back up to the list deliberately leaves her library behind the sheet:
/// you are still visiting, you are just looking at the switcher again. So whose
/// library and which level are two independent bits, and collapsing them into one
/// would make the way back up an exit — which is the `FriendRail`-era behaviour this
/// replaced.
///
/// **What moves it:** tapping a row in the Friends sheet goes down to [friend], and
/// tapping the **Friends tab** goes back up to [list] — including when Friends is
/// already the selected tab, which is the entire friend switcher. There is no
/// control inside the sheet for it. `ShellChrome._selectTab` owns both halves and
/// records why a reselect can be relied on.
final friendsSheetLevelProvider = StateProvider.autoDispose<FriendsSheetLevel>(
  (ref) => FriendsSheetLevel.list,
);

/// Year the read view is filtered to, where `0` means all time.
///
/// Month-level filtering is gone: the expanded read view groups by month already,
/// so filtering to one month would leave a grid with a single group in it. What
/// remains is one year per library — yours and, separately, the friend you are
/// visiting.
///
/// The friend pair is shared by *every* friend, so switching between them inside a
/// visit keeps the filter. Keying a family on the friend's id would give each their
/// own; still a behaviour change, still not this change. It is easier to notice now
/// that a switch is a tap in a list rather than a slide, which is what
/// `friend_navigation_test.dart` pins deliberately rather than leaving to be
/// rediscovered as a bug.
///
/// Defaults to the current year rather than all time: opening *your own* sheet is
/// most often about what was just finished, and `readFilterYears` always offers the
/// current year as an option once there is at least one finished book, so the
/// default lands on a capsule that is really there.
final readsFilterYearProvider = StateProvider.autoDispose<int>(
  (ref) => DateTime.now().year,
);

/// The same, for the friend you are visiting — and **all time, not the current
/// year.**
///
/// The two defaults differ because the two libraries are known differently. Yours is
/// the one you have been adding to, so "this year" is very likely where your newest
/// finish is. Hers is one you are opening for the first time, and her reading calendar
/// is not yours: a reader whose last finish was 2024 has a whole library behind a
/// default nobody chose, and what her read view says on arrival is `Books read 0` over
/// an empty pile. `readFilterYears` offers every year up to the current one whether or
/// not a book sits in it, which is right for a rail and wrong for a default — the rail
/// is there to be *tried*, and a default is there to be *correct*.
///
/// So a visit opens on everything she has read, and narrowing to a year is hers to
/// offer and yours to ask for. That is also the only reading of "her read view looks
/// exactly like your own" that survives contact with someone else's history: the same
/// control, the same options, opened on the books rather than on the calendar.
///
/// Shared by every friend, like the year itself — see the note above on why switching
/// friends keeps it. It resets to all time when the last visit is over, since this is
/// `autoDispose` and nothing outside a visit watches it.
final friendReadsFilterYearProvider = StateProvider.autoDispose<int>(
  (ref) => 0,
);

/// Year the Library Card is filtered to, where `0` means all time.
///
/// Its own state rather than sharing [readsFilterYearProvider]. The two controls
/// look identical and mean the same thing, which is the argument for sharing them —
/// but they sit on different tabs, and a reader who narrows the Library tab to 2024
/// and then taps over to Card has not asked for their card to be about 2024. A filter
/// that changes behind a tab switch is the kind of thing nobody reports and everybody
/// notices.
final cardFilterYearProvider = StateProvider.autoDispose<int>((ref) => 0);
