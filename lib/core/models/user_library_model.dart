class UserLibraryModel {
  final String username;
  final Map<String, List<dynamic>> library;
  final List<String> shelf;
  List finishedBooks;
  bool following;
  int filterYear;
  int filterMonth;

  UserLibraryModel({
    required this.username,
    required this.library,
    required this.shelf,
    required this.finishedBooks,
    required this.following,
    required this.filterYear,
    this.filterMonth = 0,
  });
}
