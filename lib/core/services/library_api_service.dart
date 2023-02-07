import 'dart:developer';

import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/services/api_service.dart';
import 'package:bookworm_friends/helpers/transformers.dart';
import 'package:intl/intl.dart';

class LibraryApiService extends ApiService {
  static Future<dynamic> getLibrary() async {
    String path = '/library/';

    try {
      var res = await ApiService.get(path, null);
      return res.data;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<dynamic> getFinishedBooks(
      int filterYear, int filterMonth) async {
    String path = '/library/finished_books';

    Map<String, dynamic> parameters = {
      'filter_year': filterYear,
      'filter_month': filterMonth,
    };

    try {
      var res = await ApiService.get(path, parameters);
      return res.data;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<dynamic> getBookDetails(String isbn, {String? username}) async {
    String path = '/library/book_details';

    Map<String, dynamic> parameters = {
      'isbn': isbn,
      'username': username,
    };

    try {
      var res = await ApiService.get(path, parameters);
      return res.data;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<dynamic> getBookCompliments(String isbn,
      {String? username}) async {
    String path = '/library/book_compliments';

    Map<String, dynamic> parameters = {
      'isbn': isbn,
      'username': username,
    };

    try {
      var res = await ApiService.get(path, parameters);
      return res.data;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> addBookToLibrary(
      String shelf, String isbn, String title, String thumbnail, int status,
      {DateTime? startReadDate, DateTime? finishReadDate}) async {
    String path = '/library/add_book';

    Map<String, dynamic> data = {
      'shelf': shelf,
      'isbn': isbn,
      'title': title,
      'thumbnail': thumbnail,
      'status': status,
      'start_date': startReadDate == null
          ? null
          : DateFormat('yyyy-MM-dd').format(startReadDate),
      'finish_date': finishReadDate == null
          ? null
          : DateFormat('yyyy-MM-dd').format(finishReadDate),
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 201;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> updateBookStatus(String isbn, int status,
      {DateTime? startReadDate, DateTime? finishReadDate}) async {
    String path = '/library/update_book/status';

    Map<String, dynamic> data = {
      'isbn': isbn,
      'status': status,
      'start_date': startReadDate == null
          ? null
          : DateFormat('yyyy-MM-dd').format(startReadDate),
      'finish_date': finishReadDate == null
          ? null
          : DateFormat('yyyy-MM-dd').format(finishReadDate),
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> addShelf(String shelf) async {
    String path = '/library/add_shelf';

    Map<String, dynamic> data = {
      'shelf': shelf,
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 201;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> postMemo(String isbn, String content) async {
    String path = '/library/memo';

    Map<String, dynamic> data = {
      'isbn': isbn,
      'content': content,
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 201;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> updateShelfName(String shelf, String newName) async {
    String path = '/library/update_shelf/name';

    Map<String, dynamic> data = {
      'shelf': shelf,
      'new_name': newName,
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> updateLibrary(Map<String, dynamic> library) async {
    String path = '/library/update_library';

    Map<String, dynamic> data = library;

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> updateShelfOrder(List shelfOrder) async {
    String path = '/library/update_shelf/order';

    Map<String, dynamic> data = {
      'ordered_shelf': shelfOrder,
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> updateMemo(int id, String content) async {
    String path = '/library/update_memo';

    Map<String, dynamic> data = {
      'id': id,
      'content': content,
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> deleteBook(String isbn) async {
    String path = '/library/delete_book';

    Map<String, dynamic> data = {
      'isbn': isbn,
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> deleteShelf(String shelf) async {
    String path = '/library/delete_shelf';

    Map<String, dynamic> data = {
      'shelf': shelf,
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> deleteMemo(int id) async {
    String path = '/library/delete_memo';

    Map<String, dynamic> data = {
      'id': id,
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> postCompliment(
      String username, String isbn, String compliment) async {
    String path = '/library/compliment';

    Map<String, dynamic> data = {
      'username': username,
      'isbn': isbn,
      'compliment': compliment,
    };

    try {
      var res = await ApiService.post(path, data);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }
}
