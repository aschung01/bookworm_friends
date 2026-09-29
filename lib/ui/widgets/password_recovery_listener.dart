import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';

/// Presents `NewPasswordPage` when a reset link has been exchanged.
///
/// **A listener above the navigator, rather than a check inside a page, because a recovery
/// session is a real session.** `status` stays `authenticated` throughout (see
/// [AuthState.recovering]), so `AuthPage._leaveIfSignedIn` and `SplashPage` route to the
/// library exactly as they would for any sign-in, and the set-password screen arrives *on
/// top of* wherever that was.
///
/// The rejected alternative is worth recording, because it is the obvious one: teach
/// `_leaveIfSignedIn` to refuse to navigate while recovering. It fails on a **cold start** --
/// the link launches the app and `SplashPage`, not `AuthPage`, does the routing -- and on a
/// warm start it appears to work, so the gap only shows up on the path that is hardest to
/// exercise. Making it a status instead would change the answer for all four readers of
/// `AuthStatus.authenticated`.
///
/// Hosted in `MaterialApp.builder` beside [InviteLinkListener] for the same reason: it draws
/// nothing, it has to outlive every route, and it therefore has no `Navigator` in scope and
/// drives the root one through [navigatorKey].
class PasswordRecoveryListener extends ConsumerStatefulWidget {
  const PasswordRecoveryListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// The root navigator. This widget sits above it, so `Navigator.of(context)` here would
  /// find nothing -- the same constraint `InviteLinkListener` works under.
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  @override
  ConsumerState<PasswordRecoveryListener> createState() =>
      _PasswordRecoveryListenerState();
}

class _PasswordRecoveryListenerState
    extends ConsumerState<PasswordRecoveryListener> {
  /// Guards against presenting twice for one recovery.
  ///
  /// `recovering` stays true for as long as the reader is on the screen, and any rebuild
  /// that reads it -- an hourly `tokenRefreshed`, say -- would otherwise stack a second
  /// copy on the first.
  bool _presenting = false;

  @override
  void initState() {
    super.initState();
    // **Checked on mount as well as listened to.** The exchange can finish before this
    // widget exists: `Supabase.initialize` runs before `runApp`, so a link that cold-starts
    // the app may have already emitted `passwordRecovery`, and `ref.listen` never fires for
    // a change that already happened. This is the same reasoning `AuthPage.initState`
    // records, and it is why `recovering` is persisted state rather than an event.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presentIfRecovering(ref.read(authProvider));
    });
  }

  void _presentIfRecovering(AuthState auth) {
    if (_presenting || !auth.recovering) return;

    final navigator = widget.navigatorKey.currentState;
    // No navigator yet. The post-frame callback above is the usual first attempt and runs
    // after the first frame, so this is the cold-start edge; `ref.listen` covers it on the
    // next change, and `recovering` is still set because only saving or dismissing clears
    // it.
    if (navigator == null) return;

    _presenting = true;
    navigator.pushNamed(AppRoutes.newPassword)
    // Reset on the way out, so a second reset link in the same session presents again.
    // Both exits clear the flag themselves -- `updatePassword` on success,
    // `dismissRecovery` on ✕ -- so this only has to reopen the gate.
    .whenComplete(() {
      if (mounted) _presenting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // `listen`, not `watch`: nothing here draws the flag, and watching would rebuild the
    // whole app under the navigator every time a token refreshed.
    ref.listen(authProvider, (previous, next) => _presentIfRecovering(next));
    return widget.child;
  }
}
