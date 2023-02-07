import 'dart:developer';

import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/services/api_service.dart';
import 'package:bookworm_friends/helpers/transformers.dart';

class UserApiService extends ApiService {
  static Future<bool> checkUsernameAvailable(String username) async {
    String path = '/users/check_username';
    Map<String, dynamic> parameters = {
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

  static Future<bool> checkUserInfo() async {
    String path = '/users/check_user_info';
    try {
      var res = await ApiService.get(path, null);
      return res.data;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<dynamic> getUserInfo() async {
    String path = '/users/user_info';
    var res = await ApiService.get(path, null);
    if (res != null) {
      if (res.data != null) {
        return res.data;
      } else {
        return res;
      }
    }
  }

  static Future<dynamic> getFollowingInfo() async {
    String path = '/users/following_info';
    var res = await ApiService.get(path, null);
    if (res != null) {
      if (res.data != null) {
        return res.data;
      } else {
        return res;
      }
    }
  }

  static Future<dynamic> getUserFollowing() async {
    String path = '/users/user_following';
    var res = await ApiService.get(path, null);
    if (res != null) {
      if (res.data != null) {
        return res.data;
      } else {
        return res;
      }
    }
  }

  static Future<dynamic> searchUsers(String query) async {
    String path = '/users/search_users';

    Map<String, dynamic> parameters = {
      'query': query,
    };

    var res = await ApiService.get(path, parameters);
    if (res != null) {
      if (res.data != null) {
        return res.data;
      } else {
        return res;
      }
    }
  }

  static Future<dynamic> getUserLibrary(String username) async {
    String path = '/users/library';

    Map<String, dynamic> parameters = {
      'username': username,
    };

    var res = await ApiService.get(path, parameters);
    if (res != null) {
      if (res.data != null) {
        return res.data;
      } else {
        return res;
      }
    }
  }

  static Future<dynamic> getUserFinishedBooks(
      String username, int filterYear, int filterMonth) async {
    String path = '/users/finished_books';

    Map<String, dynamic> parameters = {
      'username': username,
      'filter_year': filterYear,
      'filter_month': filterMonth,
    };

    var res = await ApiService.get(path, parameters);
    if (res != null) {
      if (res.data != null) {
        return res.data;
      } else {
        return res;
      }
    }
  }

  static Future<dynamic> getFollowingUserInfo(String username) async {
    String path = '/users/following_user_info';

    Map<String, dynamic> parameters = {
      'username': username,
    };

    var res = await ApiService.get(path, parameters);
    if (res != null) {
      if (res.data != null) {
        return res.data;
      } else {
        return res;
      }
    }
  }

  static Future<dynamic> getPrivacy() async {
    String path = '/users/privacy';

    try {
      var res = await ApiService.get(path, null);
      return res.data;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<dynamic> updateUserFollowing(String username) async {
    String path = '/users/follow';

    Map<String, dynamic> data = {
      'username': username,
    };

    var res = await ApiService.post(path, data);
    if (res != null) {
      if (res.data != null) {
        return res.data;
      } else {
        return res;
      }
    }
  }

  static Future<dynamic> registerUserInfo() async {
    String path = '/users/register_user_info';

    Map<String, dynamic> _idTokenData = await AuthController.to.readIdToken();

    inspect(_idTokenData);

    Map<String, dynamic> data = {
      'email': _idTokenData['email'],
      'auth_provider': authProviderStrToInt[_idTokenData['auth_provider']],
    };

    try {
      var res = await ApiService.post(path, data);
      print(res);
      return res.statusCode == 201;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<dynamic> updateEmoji(String emoji) async {
    String path = '/users/update_emoji';

    Map<String, dynamic> data = {
      'emoji': emoji,
    };

    try {
      var res = await ApiService.post(path, data);
      print(res);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<dynamic> updateUsername(String username) async {
    String path = '/users/update_username';

    Map<String, dynamic> data = {
      'username': username,
    };

    try {
      var res = await ApiService.post(path, data);
      print(res);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<dynamic> updatePrivacy(bool private) async {
    String path = '/users/privacy';

    Map<String, dynamic> data = {
      'private': private,
    };

    try {
      var res = await ApiService.post(path, data);
      print(res);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> postFcmToken(String token) async {
    String path = '/users/fcm_token';

    Map<String, dynamic> data = {
      'token': token,
    };

    try {
      var res = await ApiService.post(path, data);
      print(res);
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> deleteAccount() async {
    String path = '/users/delete_account';

    try {
      var res = await ApiService.post(path, null);
      print(res);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> pokeUser(String username) async {
    String path = '/users/poke';

    Map<String, dynamic> data = {
      'username': username,
    };

    try {
      var res = await ApiService.post(path, data);
      print(res);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }
}
