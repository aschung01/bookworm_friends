/// One person's reaction to one book, with whatever the viewer is allowed to
/// know about who left it.
///
/// The reactor's identity arrives embedded from `profiles` rather than through a
/// second round trip, because a reaction is meaningless without it: an emoji on
/// its own cannot say whose it is, which is why the button used to carry a copy
/// of yours on its face.
///
/// [reactorName], [reactorEmoji] and [reactorAvatarPath] are all nullable
/// together, and for one reason: the `profiles` select policy is
/// `is_profile_visible(id)` — yourself, or a friend — while `book_compliments` is
/// gated on `is_book_visible(book_id)`. The two are independent, so it is entirely
/// possible to be allowed to see a reaction and not allowed to see the person who
/// left it: a friend-of-the-owner reacting to a book you can see, who is not a
/// friend of yours. The embed comes back null and the UI has to say so in words.
///
/// **Mutual friendship makes this more common, not less.** Under the old rule a
/// non-private reactor was visible to everyone, so the null case needed a private
/// profile to occur at all. Now every non-friend is opaque, and a book visible to
/// you can carry reactions from people you have no relationship with.
class BookCompliment {
  final String id;
  final String bookId;
  final String fromUserId;
  final String compliment;
  final DateTime createdAt;

  /// The reactor's display name, or null when RLS hides their profile.
  final String? reactorName;

  /// The reactor's profile emoji, used only when [reactorAvatarPath] is null —
  /// the two are the mutually exclusive modes `AvatarCircle` draws.
  final String? reactorEmoji;

  /// Storage object path of the reactor's photo avatar, if they have one.
  final String? reactorAvatarPath;

  const BookCompliment({
    required this.id,
    required this.bookId,
    required this.fromUserId,
    required this.compliment,
    required this.createdAt,
    this.reactorName,
    this.reactorEmoji,
    this.reactorAvatarPath,
  });

  /// Whether the viewer is allowed to know who this is.
  ///
  /// Keyed on the name rather than on the embed being present, because a profile
  /// row that exists but has no `username` yet (see `Profile.needsOnboarding`)
  /// is just as unnameable as one RLS withheld, and both want the same fallback.
  bool get reactorIsKnown => reactorName != null;

  factory BookCompliment.fromJson(Map<String, dynamic> json) {
    // The alias `reactor` is set in the select; PostgREST returns a single map
    // for a to-one embed, or null when the row is not readable.
    final reactor = json['reactor'] as Map<String, dynamic>?;
    return BookCompliment(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      fromUserId: json['from_user_id'] as String,
      compliment: json['compliment'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      reactorName: reactor?['username'] as String?,
      reactorEmoji: reactor?['emoji'] as String?,
      reactorAvatarPath: reactor?['avatar_path'] as String?,
    );
  }
}
