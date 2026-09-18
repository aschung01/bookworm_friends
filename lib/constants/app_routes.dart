// Narrowed to the one type borrowed from Cupertino: an unrestricted import shadows
// `material.dart` entirely here, and this file is otherwise a Material routing table.
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:bookworm_friends/ui/pages/auth_page.dart';
import 'package:bookworm_friends/ui/pages/home_page.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';
import 'package:bookworm_friends/ui/pages/invite_dead_page.dart';
import 'package:bookworm_friends/ui/pages/invite_done_page.dart';
import 'package:bookworm_friends/ui/pages/manage_friend_page.dart';
import 'package:bookworm_friends/ui/pages/scan_book_page.dart';
import 'package:bookworm_friends/ui/pages/settings_page.dart';
import 'package:bookworm_friends/ui/pages/share_card_page.dart';
import 'package:bookworm_friends/ui/pages/splash_page.dart';
import 'package:bookworm_friends/ui/views/book_details_tab_view.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String auth = '/auth';
  static const String home = '/home';
  static const String details = '/details';
  static const String settings = '/settings';

  /// Identity, per-friend notifications, and Remove.
  ///
  /// Reached from a long press on a Friends-sheet row, and from `InviteDonePage`'s
  /// secondary button. **No longer from the visit bar**, whose gear became an overflow
  /// menu offering Remove in place — see `_LibraryBar`. Takes the [Profile] as its
  /// argument.
  static const String manageFriend = '/manage_friend';

  /// The three screens a redemption passes through.
  ///
  /// Spelled in [AppRoutesInvite] beside the pages and re-exported here, because the
  /// three are one flow reached only from each other or from a link handler, and their
  /// argument types live with them. This class stays the routing *table*; it is not
  /// also the place their names are decided.
  ///
  /// **There is no typed-code route, deliberately.** A friendship is created by
  /// following an invite link and by nothing else — see [AppRoutesInvite].
  static const String inviteConsent = AppRoutesInvite.inviteConsent;
  static const String inviteDone = AppRoutesInvite.inviteDone;
  static const String inviteDead = AppRoutesInvite.inviteDead;

  // `searchUsers` and `userLibrary` are gone.
  //
  // Handle search was the entry point that made a request queue necessary, and it is
  // replaced by invite links. `UserLibraryPage` went with it: its only two entry points
  // were a search result and a row in the followers/following sheet, and both are gone.
  // A friend's library is a *visit* inside the shell (`home_page.dart`), which is what
  // the friend-navigation redesign established — the page was the last route that still
  // presented one as a separate screen.

  /// Barcode scanner, opened from the Add Book sheet.
  ///
  /// A page route rather than a stacked sheet, which is also what hides the
  /// floating tab bar for free: `topPageRouteProvider` tracks page routes only, so
  /// a `PageRoute` above the shell is enough and no name matching is involved.
  ///
  /// **Presented upward, and therefore not in [routes].** See [onGenerateRoute].
  static const String scanBook = '/scan_book';

  /// `View and share`: the Library Card previewed before it is sent.
  ///
  /// A page route for the same reason [scanBook] is one — a focused dismissible
  /// context that has to clear the floating tab bar, which `shellBarVisibleProvider`
  /// gives it for free. Takes a [ShareCardArgs]; unlike [details] it is a typed value
  /// rather than a `Map`, because a mistyped key here is a card with no covers and
  /// nothing on screen to say why.
  ///
  /// **Presented upward, and therefore not in [routes].** See [onGenerateRoute].
  static const String shareCard = '/share_card';

  static Map<String, WidgetBuilder> get routes => {
    splash: (_) => const SplashPage(),
    auth: (_) => const AuthPage(),
    home: (_) => const HomePage(),
    manageFriend: (_) => const ManageFriendPage(),
    inviteConsent: (_) => const InviteConsentPage(),
    inviteDone: (_) => const InviteDonePage(),
    inviteDead: (_) => const InviteDeadPage(),
    details: (_) => const BookDetailsTabView(),
    settings: (_) => const SettingsPage(),
  };

  /// Routes that need a transition the [routes] table cannot express.
  ///
  /// `MaterialApp` consults [routes] first and only falls through to here for a name
  /// the table does not hold, so a route wanting its own transition has to be absent
  /// from the table — which is why [shareCard] and [scanBook] are missing from it.
  /// Returning null for everything else hands the name back to the framework's own
  /// unknown-route handling rather than swallowing it.
  ///
  /// **Both of these rise from the bottom instead of sliding in from the trailing
  /// edge.** A horizontal push says "one level deeper into the library", and neither of
  /// these is that. [shareCard] is one card, held out, over the page that produced it.
  /// [scanBook] is a viewfinder: a self-contained errand you come back from, with no ⟨
  /// back to Add Book on it — only an ✕ — which is what a horizontal push had been
  /// promising and the page never had. Upward is the motion iOS reserves for exactly
  /// that, and it is what the camera does in every app that has one.
  ///
  /// **A full-screen cover, not a page sheet — and the difference is the whole point.**
  /// This was first built on `CupertinoSheetRoute`, which also rises from the bottom
  /// and looked like the more native answer. It is the wrong native answer. A
  /// `CupertinoSheetRoute` is `UIModalPresentationPageSheet`, and on iOS 18+ that
  /// presentation brings its entire personality with it: the sheet stops short of the
  /// top, takes rounded corners, and *scales the presenting page down behind it* into
  /// the stacked-card effect. The card then reads as a panel belonging to a shrunken
  /// app rather than as the one thing on screen. Flighty's Passport share — which this
  /// screen is modelled on — is `.fullScreen` with `.coverVertical`: it covers
  /// everything and leaves the app underneath perfectly still. That is this.
  ///
  /// **The scanner wants a cover for a harder reason than looks.** A sheet-hosted
  /// camera was drawn and rejected: the framing room above the scan window collapses
  /// from 250pt to 150 and clips the book the user is pointing at, and a save sheet
  /// over it puts a live camera platform view under *two* Flutter sheets — the z-order
  /// bleed `autoHideOnModal` exists to work around. See `docs/mockups/scan-to-add`,
  /// version `scanner-sheet`. A full-screen cover changes the direction the page
  /// arrives from and nothing else: same 874pt of preview, same one modal over the
  /// shell.
  ///
  /// **`fullscreenDialog` is what buys the stillness, not just the direction.** Both
  /// `CupertinoRouteTransitionMixin.canTransitionFrom` and
  /// `MaterialRouteTransitionMixin.canTransitionTo` test the incoming route for it and
  /// refuse to animate the outgoing one when it is set, so the page below is not
  /// transformed, dimmed or slid — it is simply covered. Two independent gates, which
  /// is what neutralises `CupertinoPageRoute.delegatedTransition` being non-null even
  /// for a fullscreen dialog (an inconsistency with `_PageBasedCupertinoPageRoute`,
  /// which does gate it; the `&&` in `canTransitionTo` is why it cannot bite).
  ///
  /// **[CupertinoPageRoute] rather than `MaterialPageRoute(fullscreenDialog: true)`.**
  /// The Material route takes its transition from the ambient `PageTransitionsTheme`,
  /// and `ZoomPageTransitionsBuilder` — the Android default, and this app sets no
  /// theme of its own — never consults `fullscreenDialog` at all. The same push would
  /// still arrive from the side there. `CupertinoPageRoute` builds its own transition
  /// on every platform, so both behave alike.
  ///
  /// Dismissal is therefore the ✕ alone. A full-screen cover is not drag-dismissible on
  /// iOS — that is a sheet affordance — so the drag handle the sheet version drew has
  /// gone with it rather than being kept as an affordance for a gesture that no longer
  /// exists. The scanner already dismissed this way; what it loses is the back-edge
  /// swipe, which `fullscreenDialog` disables and which was never the affordance the
  /// screen advertised.
  ///
  /// Both are still `PageRoute`s, which is what keeps the floating tab bar's existing
  /// rule working: `topPageRouteProvider` tracks page routes and nothing here needs to
  /// know either route's name. Both are opaque, so there is nothing underneath to keep
  /// tidy.
  ///
  /// [scanBook] is generated as a `Route<ScanOutcome>` — the value the scanner pops to
  /// say how the user left it. The push in `_AddBookSheetState._openScanner` is
  /// deliberately *untyped* all the same; see the note there.
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      shareCard => CupertinoPageRoute<void>(
        settings: settings,
        fullscreenDialog: true,
        builder: (_) => const ShareCardPage(),
      ),
      scanBook => CupertinoPageRoute<ScanOutcome>(
        settings: settings,
        fullscreenDialog: true,
        builder: (_) => const ScanBookPage(),
      ),
      _ => null,
    };
  }
}
