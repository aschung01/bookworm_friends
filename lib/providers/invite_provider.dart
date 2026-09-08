import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/invite.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';

/// Creating and redeeming invite links.
///
/// Both calls are RPCs rather than table writes, because neither `friend_invites` nor
/// `friendships` has an INSERT policy. That is deliberate: a client that could insert
/// directly could friend someone without an invite, or mint a token with a distant
/// expiry and an unlimited use count. The functions are `SECURITY DEFINER` and are the
/// only writers.
///
/// See `supabase/migrations/20260828120300_invite_rpcs.sql`.
final inviteActionsProvider = Provider((ref) => InviteActions(ref));

class InviteActions {
  final Ref ref;
  InviteActions(this.ref);

  /// Mints a link. 48 hours, 10 uses — both written into the row at creation, so a
  /// later change of policy does not retroactively expire links already in circulation.
  ///
  /// Errors are **not** swallowed here, unlike [UserActions.pokeUser]. A poke that
  /// silently fails costs nothing; an invite sheet that shows no code, or a stale one,
  /// sends someone off to share a link that will not work. The caller shows the error.
  Future<Invite> create() async {
    final data = await supabase.rpc<Map<String, dynamic>>('create_invite');
    return Invite.fromJson(data);
  }

  /// Redeems a token and, on success, creates the friendship.
  ///
  /// Returns the reason rather than throwing on refusal: expired, revoked, exhausted
  /// and already-friends are all ordinary outcomes with their own copy, not exceptions.
  /// A thrown error here means the network or the session failed, which is a different
  /// screen entirely.
  ///
  /// Invalidates the friends list only when a friendship now exists — which includes
  /// `alreadyFriends`, since the local list may simply be stale.
  Future<InviteRedemption> redeem(String token) async {
    final data = await supabase.rpc<Map<String, dynamic>>(
      'redeem_invite',
      params: {'invite_token': token.trim().toUpperCase()},
    );

    final redemption = InviteRedemption.fromJson(data);

    if (redemption.result.isFriendNow) {
      ref.invalidate(friendsProvider);
      final me = ref.read(currentUserIdProvider);
      if (me != null) ref.invalidate(friendCountProvider(me));
    }

    return redemption;
  }

  /// Kills a link early. Returns false when the token is not yours or was already
  /// revoked, which the server decides — the client does not read the row to find out.
  Future<bool> revoke(String token) async {
    return await supabase.rpc<bool>(
      'revoke_invite',
      params: {'invite_token': token},
    );
  }
}
