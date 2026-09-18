import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/shell_chrome_provider.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/add_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';

/// Hosts the shell's floating tab bar **above the `Navigator`**, as
/// `MaterialApp.builder`.
///
/// Why up here rather than inside `HomePage`, where it started: a native platform
/// view can only be drawn in front of Flutter content that is painted *before* it.
/// Inside the page, the bar was painted first and every route — including the Add
/// Book sheet — landed on top, which is also why `CNTabBarRouteObserver` destroyed
/// the bar for sheet routes instead of letting Flutter composite a modal over a
/// `UITabBar`. Layered over the navigator the order inverts: the bar is painted
/// last, so it floats in front of the sheet, which is the arrangement Flighty uses
/// and the one Flutter's compositor is happiest with.
///
/// Verified on an iPhone 17 Pro / iOS 26.4 simulator before this was built, with a
/// standalone spike: the glass renders cleanly over a modal sheet (it samples the
/// sheet behind it, as Liquid Glass should), taps reach the bar while the modal
/// owns the screen, and the sheet still dismisses from its own barrier.
///
/// What it costs: everything ambient. Up here there is no route, no `HomePage`,
/// and no `Navigator` in scope — hence [navigatorKey] for presenting Add Book, and
/// `shellChrome_provider.dart` for knowing whether to appear at all.
class ShellChrome extends ConsumerWidget {
  const ShellChrome({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// The app's root navigator. Used only to get a context *inside* the navigator
  /// to present Add Book from — this widget's own context sits above it, so
  /// `Navigator.of(context)` here would find nothing.
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  Future<void> _openAddBook(WidgetRef ref) async {
    // A second tap on Search while its sheet is already up would otherwise stack a
    // second copy of it on top of the first. The bar stays live and tappable in
    // front of its own sheet by design, so nothing else stops that.
    if (ref.read(modalsAboveShellProvider) > 0) return;

    // A context from inside the navigator, which Add Book needs twice over: to
    // find a `Navigator` to push onto, and for the unstripped `MediaQuery` its
    // top inset is measured from.
    final context = navigatorKey.currentContext;
    if (context == null) return;
    await showAddBookBottomSheet(context);
  }

  /// Switching tabs dismisses whatever sheet is over the shell first, resets the
  /// Friends tab to its list, and ends a visit unless the tab you picked is the one a
  /// visit lives on.
  ///
  /// **The dismissal.** The bar is in front of sheets now and stays tappable, so a
  /// switch that only happened *behind* Add Book would look like the bar did nothing
  /// — the same dishonesty as a bar that cannot say where you are, which is what the
  /// design still hides it for during an edit.
  ///
  /// **The way back up a level.** A tap on Friends always shows the Friends *list*,
  /// including — and especially — when Friends is the tab you are already on. That is
  /// the whole of the friend switcher: inside a visit, at the level showing her read
  /// books, tapping Friends brings the list back over her library so the next friend
  /// is one more tap away, and nothing about the visit ends. It is the gesture iOS
  /// already trains (a tap on the current tab means "top of this tab"), and it is why
  /// the sheet needs no back control of its own.
  ///
  /// **This depends on a reselect being reported at all, and it is on both paths.**
  /// The Flutter fallback's segments call `onChanged` unconditionally, and
  /// `CNTabBar` forwards every native `valueChanged` — `tab_bar.dart` says so in as
  /// many words: "Always fire onTap, even for reselects (Issue #13 fix)". If a
  /// package bump ever silences reselects, the friend switcher goes with it.
  ///
  /// **The exit.** All three tabs mean *yours*: Library is your books read, Card is
  /// your card, Friends is your list — or, one level down, the friend you tapped. So
  /// picking Library or Card is a statement about you, and the only reading of it
  /// that is not a lie is that the visit is over. This is the one place that
  /// behaviour lives; `HomePage._endVisit` writes the same two providers for the
  /// bar's ✕ and for the system back.
  void _selectTab(WidgetRef ref, LibraryTab next) {
    if (ref.read(modalsAboveShellProvider) > 0) {
      navigatorKey.currentState?.pop();
    }
    // Unconditional: every tab tap puts the Friends sheet back on its list. For
    // Library and Card that is bookkeeping to go with the visit ending; for Friends
    // it *is* the interaction.
    ref.read(friendsSheetLevelProvider.notifier).state = FriendsSheetLevel.list;
    if (next != LibraryTab.friends) {
      ref.read(selectedFriendProvider.notifier).state = null;
    }
    ref.read(libraryTabProvider.notifier).state = next;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(shellBarVisibleProvider);
    final geometry = ShellTabBar.geometryOf(context);
    // The `Stack` is unconditional, and only the bar comes and goes. Returning
    // `child` bare while the bar is hidden would change the shape of the tree at
    // this slot, which deactivates and re-inflates everything under it — the
    // navigator survives that only because it holds a `GlobalKey`, and the
    // platform views inside whatever sheets are open get dragged through a
    // detach/attach for nothing. Visibility now flips on a route push, an edit, a
    // visit *and* a stacked sheet, so the churn is not worth the one `Stack`.
    //
    // Not building `ShellTabBar` at all (rather than hiding it) is still the
    // point: no widget means no `CNTabBar`, so there is no native view left alive
    // behind the page or sheet that replaced it.
    return Stack(
      children: [
        child,
        if (visible)
          Positioned(
            left: geometry.sideInset,
            right: geometry.sideInset,
            bottom: geometry.bottomOffset,
            child: ShellTabBar(
              current: ref.watch(libraryTabProvider),
              onChanged: (next) => _selectTab(ref, next),
              onAddBook: () => _openAddBook(ref),
            ),
          ),
      ],
    );
  }
}
