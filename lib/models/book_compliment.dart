class BookCompliment {
  final String id;
  final String bookId;
  final String fromUserId;
  final String compliment;
  final DateTime createdAt;

  const BookCompliment({
    required this.id,
    required this.bookId,
    required this.fromUserId,
    required this.compliment,
    required this.createdAt,
  });

  factory BookCompliment.fromJson(Map<String, dynamic> json) {
    return BookCompliment(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      fromUserId: json['from_user_id'] as String,
      compliment: json['compliment'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
