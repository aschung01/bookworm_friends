import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Whether native Liquid Glass controls should be used for this build.
///
/// Both halves matter. [PlatformVersion.shouldUseNativeGlass] only inspects the
/// *host* OS version, so on a macOS 26 machine it is true even when the target
/// platform isn't Apple. The native widgets gate on target platform *and*
/// version internally, so without the target check they are handed SF Symbols
/// they then discard — leaving controls with no icon at all. (This is exactly
/// what happens under `flutter test`, which reports Android.)
bool get useNativeGlass {
  final isApplePlatform =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  return isApplePlatform && PlatformVersion.shouldUseNativeGlass;
}

/// How many **page** routes are currently pushed, published for [ModalCoverBuilder].
///
/// **The counter that has to exist separately from the package's.**
/// `CNTabBarRouteObserver.anyModalDepth` is bumped only for a `PopupRoute` or a route
/// whose type name contains `Sheet`/`Popup`/`Dialog` — `ShellRouteObserver._isAnyModal`
/// mirrors that predicate on purpose, so the halo clip behaves as `CNButton` expects.
/// A pushed *page* matches none of it: `AppRoutes.shareCard` and `AppRoutes.scanBook`
/// are `CupertinoPageRoute`s, and `fullscreenDialog` is a flag rather than part of the
/// type name. So a glass control on the route below stays live and composited under a
/// full-screen page — the same platform-view bleed the modal counter exists to stop,
/// coming through the one door it does not watch. The Card sheet's glass share button
/// pushes exactly such a page.
///
/// **Not the route's own [ModalRoute.secondaryAnimation], which was the first attempt
/// and does not fire for the case that motivated this.** `MaterialRouteTransitionMixin`
/// and its Cupertino counterpart both answer `canTransitionTo` false for a next route
/// with `fullscreenDialog: true` — "don't perform outgoing animation" — so the route
/// underneath keeps `kAlwaysDismissedAnimation` and never learns it was covered.
/// `shareCard` is presented exactly that way.
///
/// A bare [ValueNotifier] rather than a provider, because [ModalCoverBuilder] is a
/// plain widget used in subtrees with no `ProviderScope` above them, and because this
/// mirrors how the package publishes its own depth.
final ValueNotifier<int> glassPageDepth = ValueNotifier<int>(0);

/// Rebuilds [builder] with whether anything has been presented **above the route
/// this widget mounted in** — a modal, or a page.
///
/// Native glass controls have to stop being native while something covers them.
/// A `UiKitView` is composited by iOS rather than painted into Flutter's layer
/// tree, so Flutter content drawn over it has to be lifted into overlay quads —
/// and with a second sheet animating over the first, that split desyncs and the
/// platform view's own rectangle leaks through the sheet's scrim (the package's
/// Issue #53). On the Add Book sheet the ✕ showed it exactly: a grey square
/// where its glass circle should be, for as long as the Book Info sheet was up.
/// Taps aimed at that square still reached the native button, too — Flutter's
/// modal barrier does not block touches to a platform view.
///
/// `CNButton` destroys itself for this already, but only when its own rect
/// overlaps the rect `CNBottomSheet`'s probe publishes, and the Add Book header
/// does not overlap a sheet sitting at the bottom of the screen. The *scrim*
/// covers the whole screen wherever the sheet's body is, so coverage here is
/// depth-based rather than geometric: anything under a newer modal is covered.
///
/// [CNTabBarRouteObserver.anyModalDepth] is the counter `ShellRouteObserver` bumps
/// for every sheet, popup and dialog, and [glassPageDepth] is the one it bumps for
/// every page. Comparing both against the depth at mount time is what stops a control
/// living *inside* the newest sheet — or the newest page — from calling itself covered.
///
/// Both are read the same way in both directions: covered from the moment the thing
/// above starts arriving, and released only once it has finished leaving. The first
/// half is the app's existing choice for modals rather than a new one, and the second
/// is Issue #37 — releasing at the start of a close lets glass leak for the frames
/// before the covering pixels clear. See `ShellRouteObserver`, which owns both.
class ModalCoverBuilder extends StatefulWidget {
  const ModalCoverBuilder({super.key, required this.builder});

  /// Passed true while this widget's route is behind a modal or behind a page.
  final Widget Function(BuildContext context, bool covered) builder;

  @override
  State<ModalCoverBuilder> createState() => _ModalCoverBuilderState();
}

class _ModalCoverBuilderState extends State<ModalCoverBuilder> {
  /// Modal depth at mount, i.e. the depth of the route this widget lives in.
  /// Anything past it is above this widget rather than around it.
  late final int _mountDepth;

  /// The same, for pages. See [glassPageDepth].
  late final int _mountPageDepth;

  bool _covered = false;

  @override
  void initState() {
    super.initState();
    // Both read before the first build, which is early enough: a `NavigatorObserver`
    // is notified from `didPush` *while the Navigator builds*, ahead of the route's
    // own content — the reason `_publishTopPage` defers its write. So by the time a
    // control inside a route mounts, that route is already counted, and "greater than
    // my mount depth" means strictly above me.
    _mountDepth = CNTabBarRouteObserver.anyModalDepth.value;
    _mountPageDepth = glassPageDepth.value;
    CNTabBarRouteObserver.anyModalDepth.addListener(_onDepthChanged);
    glassPageDepth.addListener(_onDepthChanged);
  }

  @override
  void dispose() {
    CNTabBarRouteObserver.anyModalDepth.removeListener(_onDepthChanged);
    glassPageDepth.removeListener(_onDepthChanged);
    super.dispose();
  }

  /// Deferred to a post-frame callback because the counter is bumped from
  /// `NavigatorObserver.didPush`, which for the first route of a navigator fires
  /// while that navigator is building — and a `setState` from there throws.
  void _onDepthChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next =
          CNTabBarRouteObserver.anyModalDepth.value > _mountDepth ||
          glassPageDepth.value > _mountPageDepth;
      if (next == _covered) return;
      setState(() => _covered = next);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _covered);
}
