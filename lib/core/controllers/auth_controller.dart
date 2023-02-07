import 'dart:developer';

import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/core/services/user_api_service.dart';
import 'package:bookworm_friends/helpers/parse_jwt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:get/get.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk_template.dart';

class AuthController extends GetxController {
  static AuthController get to => Get.find<AuthController>();
  RxBool isAuthenticated = false.obs;
  FlutterSecureStorage storage = const FlutterSecureStorage();
  RxMap userInfo = {}.obs;
  bool isKakaoInstalled = false;

  @override
  void onInit() {
    super.onInit();
    _initKakaoTalkInstalled();
  }

  Future<void> checkAuthentication() async {
    var refreshToken = await storage.read(key: 'refresh_token');
    isAuthenticated.value = refreshToken != null;
    if (!isAuthenticated.value) {
      userInfo.clear();
    }
    print('User authenticated: ${isAuthenticated.value}');
  }

  Future<bool> asyncMethod() async {
    await checkAuthentication();
    // Get.offAllNamed('/home');
    if (isAuthenticated.value) {
      // await RegisterInfoController.to.checkUserInfo();
      // if (!RegisterInfoController.to.userInfoExists.value) {
      //   // Get.toNamed('/register_info');
      //   return false;
      // }
    }
    return true;
  }

  void _initKakaoTalkInstalled() async {
    final installed = await isKakaoTalkInstalled();
    print('kakao Install: ' + installed.toString());
    isKakaoInstalled = installed;
    update();
  }

  Future<dynamic> getAccessToken() async {
    var refreshToken = await storage.read(key: 'refresh_token');
    if (refreshToken != null) {
      var accessToken = await storage.read(key: 'access_token');
      if (parseJwt(accessToken!)["exp"] * 1000 <
              DateTime.now().millisecondsSinceEpoch ||
          (accessToken == null)) {
        print('Access token expired');
        // await AmplifyService.getTokensWithRefreshToken(refreshToken);
        var updatedAccessToken = await storage.read(key: 'access_token');
        print('Access token updated');
        return updatedAccessToken;
      } else {
        return accessToken;
      }
    } else {
      print("refresh token doesn't exist");
      Get.offNamed('/auth');
    }
  }

  Future<dynamic> readIdToken() async {
    var idToken = await storage.read(key: 'id_token');
    if (idToken != null) {
      Map<String, dynamic> data = parseJwt(idToken);
      log('Id token data: ${data.toString()}');
      late String cognitoGroup;
      if (data.containsKey('cognito:groups')) {
        cognitoGroup =
            data['cognito:groups'][data['cognito:groups'].length - 1];
      } else {
        cognitoGroup = data['name'].split('_')[0];
        cognitoGroup =
            '${cognitoGroup[0].toUpperCase()}${cognitoGroup.substring(1)}';
      }
      late String authProvider;
      if (data['identities'] != null) {
        print(data['identities'][0]['providerName']);
      }
      switch (cognitoGroup) {
        case 'Kakao':
          authProvider = 'Kakao';
          break;
        case 'ap-northeast-2_MGdU7uQ11_Google':
          authProvider = 'Google';
          break;
        case 'ap-northeast-2_MGdU7uQ11_SignInWithApple':
          authProvider = 'Apple';
          break;
        default:
          authProvider = cognitoGroup;
          break;
      }
      return {
        'email': data['email'],
        'auth_provider': authProvider,
      };
    } else {
      return;
    }
  }

  Future<void> getUserInfoIfEmpty() async {
    if (isAuthenticated.value && userInfo.isEmpty) {
      var data = await UserApiService.getUserInfo();
      if (data != null) {
        userInfo.value = data;
      }
      UserController.to.username.value = userInfo['username'];
    }
  }

  Future<void> getUserInfo() async {
    if (isAuthenticated.value) {
      var data = await UserApiService.getUserInfo();
      if (data != null) {
        userInfo.value = data;
      }
      UserController.to.username.value = userInfo['username'];
    }
  }

  Future<void> registerUserInfo() async {
    if (isAuthenticated.value) {
      await UserApiService.registerUserInfo();
    }
  }
}
