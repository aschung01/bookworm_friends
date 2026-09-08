import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// State the shell's floating chrome needs, and which it cannot read any other
/// way.
///
/// The tab bar is hosted **above** the `Navigator` (see `ShellChrome`), because
/// that is the only place a native platform view can be painted in front of a
/// Flutter modal route — which is what makes it float over Add Book the way
/// Flighty's does. Living up there costs it every ambient thing a page takes for
/// granted: it is outside `HomePage`, outside the route, and cannot ask
/// `ModalRoute.of` or `Navigator.of` anything useful. So the page publishes what
/// the chrome needs, and this file is that channel.

/// The route `HomePage` is sitting in, published by the page itself.
///
/// An identity, not a name. The shell is `/home` pushed after a splash in the app,
/// `initialRoute` in `main_shell_preview.dart`, and `home:` (named `/`, which
/// collides with the splash route) under `flutter test` — so matching on
/// `settings.name` would need a different answer per entrypoint. Identity needs
/// none.
final shellHomeRouteProvider = StateProvider<Route<dynamic>?>((ref) => null);

/// Topmost `PageRoute` on the root navigator.
///
/// **Page routes only, deliberately.** A sheet, popup or dialog must not change
/// this: the bar is meant to stay in front of those, which is the entire point of
/// hosting it above the navigator. What it does catch is a pushed *page* — book
/// details, settings, add-friend — which used to hide the bar for free, because a
/// page replaced the whole view and took the bar with it. Above the navigator
/// nothing is free: without this the bar would float on top of every pushed page.
final topPageRouteProvider = StateProvider<Route<dynamic>?>((ref) => null);

/// How many modal-like routes (sheets, popups, dialogs) are above the shell.
///
/// Exists because the bar is now *in front of* those and stays tappable. A tab tap
/// that only switched the sheet behind the Add Book sheet would look like the bar
/// did nothing at all, which is the same lie as a bar that cannot say where you
/// are — so `ShellChrome` dismisses the sheet first. A count rather than a flag
/// because [shellBarVisibleProvider] also needs to tell one sheet from a stack of
/// them: the bar floats over the first and hides for the rest.
final modalsAboveShellProvider = StateProvider<int>((ref) => 0);

/// Whether the floating tab bar should be on screen.
///
/// **The order of the reads matters.** [libraryModeProvider] is `autoDispose`, and
/// this provider is listened to for the whole life of the app — so watching it
/// unconditionally would pin it alive forever, and carry an open edit across a
/// sign-out. The route check runs first and returns early, so it is only ever
/// watched while the shell is genuinely the page on screen.
///
/// It used to read [selectedFriendProvider] here too, and hide the bar for a visit.
/// That is gone: under the current design no tab ever changes what it means, so a
/// bar shown inside a visit cannot misreport where you are — Library is your books
/// read, Card is your card, Friends is your list or the friend one level down it.
/// Selecting either of the first two ends the visit, which is what makes the bar a
/// way *out* rather than a claim about where you are. One fewer `autoDispose` read
/// pinned here as a side effect.
final shellBarVisibleProvider = Provider<bool>((ref) {
  final home = ref.watch(shellHomeRouteProvider);
  // This also covers "HomePage is gone": once its route is popped or replaced it
  // is no longer the top page route, so a stale value can never match. That is
  // why nothing clears [shellHomeRouteProvider] — clearing it would mean writing
  // to a provider from `dispose`, i.e. during an unmount.
  if (home == null || ref.watch(topPageRouteProvider) != home) return false;

  // A focused, dismissible context with its own way out. A tab bar that is visible
  // but cannot say where you are is the thing four rejected design rounds kept
  // working around, and an edit is the one state left where that is true: every
  // tab's sheet is shut and the whole screen is about rearranging.
  if (ref.watch(libraryModeProvider) == LibraryMode.editLibrary) return false;

  // Floating in front of *one* sheet is the design; in front of a stack of them
  // is not. Add Book is an errand you come back from, so the bar stays over it —
  // but a sheet opened from Add Book (Book Info, and the date pickers under that)
  // is a nested, committing context, and the bar cannot honestly serve it: a tab
  // tap only pops one route, so it would leave you on the sheet it came from.
  //
  // It is also the only lever there is against the native bleed. The search
  // variant of `CNTabBar` uses an unclipped native container so the orb can
  // overhang the bar's top edge, which lets its shadow and glass draw through a
  // Flutter sheet above it — the package's own reason for `autoHideOnModal`, and
  // the reason it defaults to true. Over Add Book that bleed is wanted (the bar
  // is meant to be in front). Over a second sheet it is just a dark wedge around
  // the orb, and no Dart-side setting can contain it.
  //
  // Deliberately last, after the `autoDispose` read: the early returns above are
  // ordered to keep that provider from being pinned alive, and a return placed
  // before it would stop watching it mid-sheet instead.
  if (ref.watch(modalsAboveShellProvider) > 1) return false;

  return true;
});

final shellRouteObserverProvider = Provider<ShellRouteObserver>(
  ShellRouteObserver.new,
);

/// Stands in for `CNTabBarRouteObserver`, and has to do two jobs because of it.
///
/// **Why theirs cannot be used.** It bumps a private `_modalDepth` for any route
/// whose runtime type name contains "Sheet" — which `ModalBottomSheetRoute` does —
/// and `CNTabBar` unmounts itself while that is above zero. That is exactly the
/// auto-hide being removed here so the bar can float in front of Add Book, and
/// there is no way to decline it: the notifier is both static and private.
///
/// **What must not be lost with it.** The same observer also drives
/// `anyModalDepth`, which `CNButton` and the other iOS 26 glass widgets use to
/// clip their Liquid Glass halo while a sheet, popup or dialog is up — without it
/// haloes leak outside the platform view's bounds and draw over the sheet. That
/// half *is* public, through `markAnyModalActive` / `markAnyModalInactive`, so it
/// is reproduced here rather than dropped. [_isAnyModal] and
/// [_markInactiveWhenDismissed] mirror the package's own `_isAnyModal` and
/// `_decrementAnyModalWhenDismissed`; if glass haloes start bleeding over sheets,
/// this is the code that drifted from theirs.
///
/// The tab bar itself opts out of that counter with `autoHideOnModal: false`
/// rather than the counter being withheld from everyone — see
/// `ShellTabBar._buildNative`. An earlier version of this class skipped the bump
/// for the Add Book route instead, and it cost exactly what you would expect: the
/// read filter's glass control bled a white rectangle through the middle of the
/// sheet.
class ShellRouteObserver extends NavigatorObserver {
  ShellRouteObserver(this._ref);

  final Ref _ref;

  /// Page routes in push order. Kept rather than leaning on `previousRoute`,
  /// which is `null` at the bottom of the stack and wrong for a removal from the
  /// middle.
  final List<Route<dynamic>> _pages = <Route<dynamic>>[];

  /// Anything that visually covers the page under it. Mirrors the package's
  /// predicate exactly, including the type-name sniffing, so the halo counter
  /// behaves as `CNButton` expects.
  bool _isAnyModal(Route<dynamic> route) {
    if (route is PopupRoute) return true;
    final name = route.runtimeType.toString();
    return name.contains('Sheet') ||
        name.contains('Popup') ||
        name.contains('Dialog');
  }

  /// Modal-like routes currently pushed, published for [modalsAboveShellProvider].
  int _modals = 0;

  /// Publishing is deferred by a microtask because `didPush` for the *first*
  /// route fires while the `Navigator` is building, and Riverpod rejects a write
  /// made during a build. A microtask queued from inside the frame runs once the
  /// frame's synchronous work has finished.
  void _publishTopPage() {
    final next = _pages.isEmpty ? null : _pages.last;
    Future<void>.microtask(() {
      if (_ref.read(topPageRouteProvider) == next) return;
      _ref.read(topPageRouteProvider.notifier).state = next;
    });
  }

  void _publishModals() {
    final next = _modals;
    Future<void>.microtask(() {
      if (_ref.read(modalsAboveShellProvider) == next) return;
      _ref.read(modalsAboveShellProvider.notifier).state = next;
    });
  }

  void _entered(Route<dynamic> route) {
    if (route is PageRoute) {
      _pages.add(route);
      _publishTopPage();
      // Bumped for *every* page, which is what [glassPageDepth] is for: a glass
      // control on the route below a pushed page has to stop being a platform view,
      // and the package's own counter below never learns about a page.
      glassPageDepth.value += 1;
    }
    if (!_isAnyModal(route)) return;
    _modals += 1;
    _publishModals();
    CNTabBarRouteObserver.markAnyModalActive();
  }

  void _left(Route<dynamic> route, {required bool deferHalo}) {
    if (route is PageRoute && _pages.remove(route)) {
      _publishTopPage();
      // Deferred for the same reason the halo is, and it is the same bug: a glass
      // control that becomes a platform view again at the *start* of a pop is live
      // under a page that is still sliding away.
      _whenDismissed(route, _releasePage, defer: deferHalo);
    }
    if (!_isAnyModal(route)) return;
    if (_modals > 0) {
      _modals -= 1;
      _publishModals();
    }
    _whenDismissed(
      route,
      CNTabBarRouteObserver.markAnyModalInactive,
      defer: deferHalo,
    );
  }

  /// Floored at zero rather than trusted to balance. The observer sees `didRemove`
  /// and `didReplace` as well as `didPop`, and a counter that went negative would
  /// leave every glass control on the screen believing it was uncovered forever.
  static void _releasePage() {
    if (glassPageDepth.value > 0) glassPageDepth.value -= 1;
  }

  /// Runs [action] once [route]'s exit animation has finished, or straight away when
  /// there is nothing to wait for.
  ///
  /// Releasing at the start of the close lets glass leak for the frames before the
  /// covering pixels clear — the package's Issue #37. A removal is not animated, so
  /// `defer: false` runs now: a deferred release would never fire.
  void _whenDismissed(
    Route<dynamic> route,
    VoidCallback action, {
    required bool defer,
  }) {
    final animation = route is TransitionRoute ? route.animation : null;
    if (!defer ||
        animation == null ||
        animation.status == AnimationStatus.dismissed) {
      action();
      return;
    }
    late void Function(AnimationStatus) listener;
    listener = (status) {
      if (status != AnimationStatus.dismissed) return;
      animation.removeStatusListener(listener);
      action();
    };
    animation.addStatusListener(listener);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _entered(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _left(route, deferHalo: true);

  /// A removal is not animated, so a deferred release would never fire.
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _left(route, deferHalo: false);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _left(oldRoute, deferHalo: false);
    if (newRoute != null) _entered(newRoute);
  }
}
