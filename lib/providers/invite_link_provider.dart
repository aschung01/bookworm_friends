import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/services/invite_link_service.dart';

/// The link listener, alive for the whole app.
///
/// Not `autoDispose`: the launch URI is read once at startup and there may be nothing
/// listening yet, so a service that was torn down between reads would drop the token
/// that launched the app.
final inviteLinkServiceProvider = Provider<InviteLinkService>((ref) {
  final service = InviteLinkService();
  ref.onDispose(service.dispose);
  return service;
});

/// The token waiting to be redeemed, or null.
///
/// **This exists because a tapped link and a signed-in session do not arrive
/// together.** `redeem_invite()` returns `not_signed_in` when `auth.uid()` is null, so
/// a link tapped on a fresh install has to survive the whole OAuth round trip before it
/// can be spent. Holding it in a provider is what makes that survivable: the splash
/// page writes it, auth ignores it, and whatever lands after sign-in reads it.
///
/// Losing it is the most likely way to break the invite tier and the hardest to notice
/// — the reader simply arrives on an empty library, with nothing on screen saying an
/// invite ever existed.
final pendingInviteTokenProvider = StateProvider<String?>((ref) => null);
