class BookMemo {
  final String id;
  final String bookId;
  final String userId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BookMemo({
    required this.id,
    required this.bookId,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BookMemo.fromJson(Map<String, dynamic> json) {
    return BookMemo(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
