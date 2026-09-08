import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/invite_link_provider.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';

/// Routes an invite link that arrives **while the app is already running**.
///
/// **This is the case the first version missed entirely.** `pendingInviteTokenProvider`
/// was written by `InviteLinkService` and read only by `SplashPage` and `AuthPage` —
/// both of which run once, at startup. So a link tapped during a cold start worked, and
/// a link tapped while the app was in the background did nothing at all: iOS
/// foregrounded the app, the token landed in the provider, and no screen was watching.
/// The reader saw their library and no sign an invite had arrived.
///
/// That is also the way the flow is most often exercised in practice — the app is
/// usually already running when a message is tapped — so the common path was the broken
/// one.
///
/// Hosted in `MaterialApp.builder` beside [ShellChrome], because it needs to outlive
/// every route: a link can arrive on any screen. Like that widget it has no `Navigator`
/// in scope and drives the root one through [navigatorKey].
class InviteLinkListener extends ConsumerWidget {
  const InviteLinkListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// The root navigator. This widget sits above it, so `Navigator.of(context)` here
  /// would find nothing — the same constraint `ShellChrome` works under.
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **`listen`, not `watch`.** A token is an event, not state to render: watching it
    // would rebuild the whole app under the navigator for a value nothing here draws.
    //
    // It also cannot fire for the value that is already there when this first builds,
    // which is exactly right. A cold start has the token in the provider *before*
    // `runApp` (see `main.dart`), and `SplashPage` owns that case — it has to, because
    // consent must be pushed onto the library rather than replacing it, and at that
    // point the library does not exist yet. So the two do not collide by construction:
    // this only ever sees a token that arrived later.
    ref.listen<String?>(pendingInviteTokenProvider, (previous, next) {
      if (next == null) return;

      // Signed out. Leave the token where it is: `redeem_invite()` answers
      // `not_signed_in` without a session, and spending it here would burn the link
      // for nothing. `AuthPage` picks it up on the far side of sign-in.
      if (ref.read(authProvider).status != AuthStatus.authenticated) return;

      final navigator = navigatorKey.currentState;
      if (navigator == null) return;

      // Cleared before the push, so a rebuild cannot present the same token twice.
      ref.read(pendingInviteTokenProvider.notifier).state = null;

      // **Pushed onto whatever is on screen, not over the whole stack.** A link can
      // arrive while the reader is in a book, in settings, or in a sheet; dismissing
      // consent should put them back exactly where they were. Replacing the stack
      // would make an invite destroy whatever they were in the middle of.
      //
      // The inviter is null here, as on every in-app path: the token carries no name
      // and this app cannot read `friend_invites` to resolve one — it is owner-scoped
      // by design. The consent copy falls back to "Someone".
      navigator.pushNamed(
        AppRoutes.inviteConsent,
        arguments: InviteConsentArgs(token: next),
      );
    });

    return child;
  }
}
