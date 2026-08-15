import 'package:bookworm_friends/models/book.dart';

class Shelf {
  final String id;
  final String userId;
  final String name;
  final int position;
  final DateTime createdAt;
  final List<Book> books;

  const Shelf({
    required this.id,
    required this.userId,
    required this.name,
    required this.position,
    required this.createdAt,
    this.books = const [],
  });

  factory Shelf.fromJson(Map<String, dynamic> json) {
    return Shelf(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      position: json['position'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      books:
          (json['books'] as List<dynamic>?)
              ?.map((b) => Book.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Shelf copyWith({String? name, int? position, List<Book>? books}) {
    return Shelf(
      id: id,
      userId: userId,
      name: name ?? this.name,
      position: position ?? this.position,
      createdAt: createdAt,
      books: books ?? this.books,
    );
  }
}
