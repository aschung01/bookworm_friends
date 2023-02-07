import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:bookworm_friends/amplifyconfiguration.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/helpers/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AmplifyService {
  static Dio dio = Dio();

  static String getSocialLoginUrl(String identityProvider) {
    return 'https://$cognitoPoolUrl.amazoncognito.com/'
        'oauth2/authorize?identity_provider=$identityProvider'
        '&redirect_uri=$redirectUri'
        '&response_type=code&client_id=$cognitoClientId'
        '&scope=email+openid+aws.cognito.signin.user.admin';
  }

  static configureAmplify() async {
    final auth = AmplifyAuthCognito(); // Auth 서비스 생성
    // final analytics = AmplifyAnalyticsPinpoint(); // Analytics 서비스 생성
    final api = AmplifyAPI();
    // final storage = AmplifyStorageS3();
    bool _amplifyConfigured = false;

    if (!_amplifyConfigured) {
      Amplify.addPlugins([
        auth, api,
        // storage
      ]);
      try {
        await Amplify.configure(amplifyconfig);
        _amplifyConfigured = true;
      } on AmplifyAlreadyConfiguredException {
        print(
            "Tried to reconfigure Amplify; this can occur when your app restarts on OS.");
      } on AmplifyException catch (e) {
        if (e.underlyingException!
            .contains('Amplify has already been configured.')) {
          print('ignore');
        } else {
          throw e;
        }
      }
    }

    if (_amplifyConfigured) {
      print('Successfully configured Amplify🎉');
    }
  }

  static Future<bool> getAuthTokensWithAuthCode(String authCode) async {
    const String url = 'https://$cognitoPoolUrl.amazoncognito.com/oauth2/token';
    try {
      print(authCode);
      var response = await dio.post(
        url,
        data: {
          'grant_type': 'authorization_code',
          'client_id': cognitoClientId,
          'redirect_uri': redirectUri,
          'code': authCode,
        },
        options: Options(headers: {
          "Content-Type": 'application/x-www-form-urlencoded',
        }),
      );
      await storeAuthTokens(response.data, 'Social');
      // var _idToken = await AuthController.to.readIdToken();
      // await Amplify.Auth.signIn(username: _idToken['email']);

      return true;
    } catch (e) {
      print('POST call for get auth tokens failed: $e');
      return false;
    }
  }

  static Future<bool> signUserInWithKakaoLogin(String accessToken) async {
    const apiName = 'bookwormFriends';
    const path = '/user/login';
    var body = Uint8List.fromList('{"access_token": "$accessToken"}'.codeUnits);
    try {
      RestOptions options = RestOptions(
        apiName: apiName,
        path: path,
        body: body,
      );
      RestOperation restOperation = Amplify.API.post(restOptions: options);
      RestResponse response = await restOperation.response;
      print('POST call succeeded');
      log(String.fromCharCodes(response.data));
      var resData = jsonDecode(String.fromCharCodes(response.data));
      await storeAuthTokens(resData["AuthenticationResult"], 'Kakao',
          password: resData['password']);
      var _idToken = await AuthController.to.readIdToken();
      AuthController.to.storage.write(key: 'email', value: _idToken['email']);
      // Amplify.Auth.signIn(
      //     username: _idToken['email'], password: resData['password']);
      AuthController.to.isAuthenticated.value = true;
      return true;
    } on RestException catch (e) {
      print('no');
      print('POST call failed: $e');
      return false;
    } catch (e) {
      print('Error: $e');
      inspect(e);
      return false;
    }
  }

  static Future<bool> deleteUser(String email) async {
    var userPool = CognitoUserPool(cognitoPoolId, cognitoClientId);
    var cognitoUser = CognitoUser(email, userPool);
    try {
      var response = await cognitoUser.deleteUser();
      return response;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> signOut() async {
    FlutterSecureStorage storage = AuthController.to.storage;
    try {
      await storage.delete(key: 'auth_provider');
      await storage.delete(key: 'access_token');
      await storage.delete(key: 'id_token');
      await storage.delete(key: 'refresh_token');
      await storage.delete(key: 'username');
      await storage.delete(key: 'activity_level');
      await storage.delete(key: 'created_at');
      Amplify.Auth.signOut();

      const String url = 'https://$cognitoPoolUrl.amazoncognito.com/logout';

      try {
        await UrlLauncher.launchInApp(url +
            '?response_type=code&client_id=$cognitoClientId&logout_uri=$logoutUri');

        var webView = ChromeSafariBrowser();
        await webView.close();
        // closeWebView();
        return true;
      } catch (e) {
        print(e);
        return false;
      }
    } on AuthException catch (e) {
      print(e);
      return false;
    } catch (e) {
      print(e);
      return false;
    }
  }

  static getTokensWithRefreshToken(String refreshToken) async {
    var dio = Dio();
    const String url = 'https://$cognitoPoolUrl.amazoncognito.com/oauth2/token';
    try {
      var response = await dio.post(
        url,
        data: {
          'grant_type': 'refresh_token',
          'client_id': cognitoClientId,
          'refresh_token': refreshToken,
        },
        options: Options(headers: {
          "Content-Type": 'application/x-www-form-urlencoded',
        }),
      );
      await storeRefreshedTokens(
          response.data['access_token'], response.data['id_token']);
    } catch (e) {
      print('POST call for refreshing tokens failed: $e');
    }
  }

  static Future<void> storeRefreshedTokens(
      String accessToken, String idToken) async {
    FlutterSecureStorage storage = AuthController.to.storage;
    await storage.write(key: 'access_token', value: accessToken);
    await storage.write(key: 'id_token', value: idToken);
  }

  static Future<void> storeAuthTokens(
      Map<String, dynamic> tokens, String authProvider,
      {String? email = null, String? password = null}) async {
    FlutterSecureStorage storage = AuthController.to.storage;
    switch (authProvider) {
      case 'Kakao':
        await storage.write(key: "auth_provider", value: authProvider);
        await storage.write(key: "access_token", value: tokens["AccessToken"]);
        await storage.write(key: "id_token", value: tokens["IdToken"]);
        await storage.write(
            key: "refresh_token", value: tokens["RefreshToken"]);
        await storage.write(key: "email", value: email);
        await storage.write(key: "password", value: password);
        var data = await storage.readAll();
        inspect(data);
        break;
      default:
        await storage.write(key: "auth_provider", value: authProvider);
        await storage.write(key: "access_token", value: tokens["access_token"]);
        await storage.write(key: "id_token", value: tokens["id_token"]);
        await storage.write(
            key: "refresh_token", value: tokens["refresh_token"]);
        break;
    }
  }

  // static Future<dynamic> uploadFile(XFile file, int contentType) async {
  //   String _key = DateTime.now().toString();
  //   Map<String, String> _metadata = <String, String>{};
  //   _metadata['name'] = file.name;

  //   S3UploadFileOptions _uploadOptions = S3UploadFileOptions(
  //       contentType: contentType == 1 ? "video/mp4" : null,
  //       accessLevel: StorageAccessLevel.guest,
  //       metadata: _metadata);

  //   try {
  //     UploadFileResult res = await Amplify.Storage.uploadFile(
  //         key: _key, local: File(file.path), options: _uploadOptions);
  //     print(res);
  //     return _key;
  //   } on StorageException catch (e) {
  //     print(e.recoverySuggestion);
  //     print(e.message);
  //   } catch (e) {
  //     print(e);
  //   }
  // }

  static Future<dynamic> getFileUrl(String key) async {
    try {
      GetUrlOptions _options =
          GetUrlOptions(accessLevel: StorageAccessLevel.guest);
      final result = await Amplify.Storage.getUrl(
        key: key,
        options: _options,
      );
      print('Got URL: ${result.url}');

      return result.url;
    } on StorageException catch (e) {
      print('Error getting download URL: $e');
    } catch (e) {
      print(e);
    }
  }

  static Future<dynamic> removeFile(String key) async {
    try {
      final result = await Amplify.Storage.remove(
        key: key,
      );
      print(result);
      return true;
    } on StorageException catch (e) {
      print('Error removing file: $e');
      return false;
    }
  }
}
