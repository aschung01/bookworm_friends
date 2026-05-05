class Profile {
  final String id;
  final String? username;
  final String? emoji;
  final bool isPrivate;
  final String? fcmToken;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profile({
    required this.id,
    this.username,
    this.emoji,
    this.isPrivate = false,
    this.fcmToken,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String?,
      emoji: json['emoji'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      fcmToken: json['fcm_token'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get needsOnboarding => username == null;
}
