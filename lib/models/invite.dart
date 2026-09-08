/// An invite link, and the outcome of trying to redeem one.
///
/// Mirrors `friend_invites` and the `invite_redemption` composite returned by
/// `redeem_invite()` (`supabase/migrations/20260828120300_invite_rpcs.sql`).
library;

/// Why a redemption did or did not happen.
///
/// **An enum rather than a boolean, and that is a design decision rather than a
/// convenience.** Three of these failures mean *ask for a new link* and one means *you
/// already used this*; a screen that cannot tell them apart has to say "this link
/// didn't work" and leave the reader to guess which. The drawings give expired, revoked
/// and exhausted their own copy for exactly this reason.
enum InviteRedemptionResult {
  /// A friendship was created.
  ok,

  /// No invite with that token. A mistyped code, most likely — the alphabet excludes
  /// `O`, `I`, `0` and `1` precisely to make this rarer.
  notFound,

  /// Past `expires_at`. 48 hours from creation.
  expired,

  /// The inviter revoked it. Distinct from [expired] because it was deliberate, and
  /// the copy should not imply the link simply aged out.
  revoked,

  /// `used_count` has reached `max_uses`.
  exhausted,

  /// The inviter tapped their own link. The most likely accident, and not an error
  /// worth alarming anyone about.
  self,

  /// Already friends. **Not a failure** — but not a success screen either, because
  /// there is no new friendship to celebrate.
  alreadyFriends,

  /// No session. The typed-code screen can be reached before sign-in completes.
  notSignedIn;

  /// Parses the Postgres enum. Unknown values map to [notFound] rather than throwing:
  /// a redemption is not worth crashing over, and every unknown outcome is a
  /// non-redemption.
  static InviteRedemptionResult fromWire(String? value) => switch (value) {
    'ok' => ok,
    'expired' => expired,
    'revoked' => revoked,
    'exhausted' => exhausted,
    'self' => self,
    'already_friends' => alreadyFriends,
    'not_signed_in' => notSignedIn,
    _ => notFound,
  };

  /// Whether a friendship now exists between the two people — true for [ok] and for
  /// [alreadyFriends], which is the distinction the success screen needs and the
  /// friends list does not.
  bool get isFriendNow => this == ok || this == alreadyFriends;
}

/// The outcome of a redemption, plus the inviter when there is one.
///
/// The inviter's id travels back with the result because the consent screen has to name
/// them before the reader decides, and the redeemer cannot read `friend_invites`
/// themselves — the table is owner-scoped, deliberately, so that a token cannot be used
/// to probe who is inviting whom.
class InviteRedemption {
  final InviteRedemptionResult result;
  final String? inviterId;

  const InviteRedemption(this.result, this.inviterId);

  factory InviteRedemption.fromJson(Map<String, dynamic> json) =>
      InviteRedemption(
        InviteRedemptionResult.fromWire(json['result'] as String?),
        json['inviter_id'] as String?,
      );
}

/// An invite you created.
class Invite {
  final String token;
  final DateTime expiresAt;
  final int maxUses;
  final int usedCount;
  final DateTime? revokedAt;

  const Invite({
    required this.token,
    required this.expiresAt,
    required this.maxUses,
    required this.usedCount,
    this.revokedAt,
  });

  factory Invite.fromJson(Map<String, dynamic> json) => Invite(
    token: json['token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
    maxUses: json['max_uses'] as int,
    usedCount: json['used_count'] as int,
    revokedAt: json['revoked_at'] == null
        ? null
        : DateTime.parse(json['revoked_at'] as String),
  );

  /// Whether this link would still work if tapped right now.
  ///
  /// Advisory only — the server decides, inside a row lock, and its answer is the one
  /// that counts. This exists so the invite sheet can show a spent link as spent
  /// without a round trip.
  bool get isLive =>
      revokedAt == null &&
      usedCount < maxUses &&
      expiresAt.isAfter(DateTime.now());

  int get usesLeft => (maxUses - usedCount).clamp(0, maxUses);
}
