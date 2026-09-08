class Profile {
  final String id;
  final String? username;

  /// The Latin identity the exported card's machine-readable strip prints.
  ///
  /// **A second identity, not a replacement for [username].** The two do different jobs:
  /// [username] is the display name, shown everywhere in the app and printed on the card
  /// as `Holder` in its own script, and it remains the key for `poke_user()` and user
  /// search. This is `^[a-z0-9_]{3,20}$` and exists because the card's strip is a
  /// fixed-width **Latin-only** grid — measured against the live database, 126 of 136
  /// display names contain non-ASCII and exactly **two** are already strip-safe.
  ///
  /// `NOT NULL` in the schema and generated at signup, so the "no handle" state does not
  /// exist and no share is ever gated on setting one. Nullable here only because a row
  /// read from a database that has not had the migration applied has no column to read.
  final String? handle;

  final String? emoji;

  /// Storage object path of the photo avatar, `{id}/{random}.{ext}`, or null
  /// when this profile wears its [emoji].
  ///
  /// A path rather than a URL: the `avatars` bucket is private and read through
  /// the authenticated object endpoint, so the URL is derived at render time
  /// (see `avatarImageProvider`) and the stored value stays independent of the
  /// bucket and project it happens to live in.
  final String? avatarPath;

  final String? fcmToken;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profile({
    required this.id,
    this.username,
    this.handle,
    this.emoji,
    this.avatarPath,
    this.fcmToken,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String?,
      handle: json['handle'] as String?,
      emoji: json['emoji'] as String?,
      avatarPath: json['avatar_path'] as String?,
      fcmToken: json['fcm_token'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get needsOnboarding => username == null;
}
