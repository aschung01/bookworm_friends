class Book {
  final String id;
  final String userId;
  final String shelfId;
  final String isbn;
  final String title;
  final String thumbnail;
  final int status;
  final int position;
  final double? rating;
  final DateTime? startDate;
  final DateTime? finishDate;
  final DateTime createdAt;

  const Book({
    required this.id,
    required this.userId,
    required this.shelfId,
    required this.isbn,
    required this.title,
    required this.thumbnail,
    required this.status,
    required this.position,
    this.rating,
    this.startDate,
    this.finishDate,
    required this.createdAt,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      shelfId: json['shelf_id'] as String,
      isbn: json['isbn'] as String,
      title: json['title'] as String,
      thumbnail: json['thumbnail'] as String,
      status: json['status'] as int,
      position: json['position'] as int? ?? 0,
      rating: (json['rating'] as num?)?.toDouble(),
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : null,
      finishDate: json['finish_date'] != null
          ? DateTime.parse(json['finish_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
