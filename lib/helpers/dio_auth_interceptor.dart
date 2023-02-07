import 'dart:developer';

import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/services/amplify_service.dart';
import 'package:bookworm_friends/helpers/parse_jwt.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:get/get.dart';

enum TokenErrorType { tokenNotFound, failedAccessTokenRegeneration }

class DioAuthInterceptor extends Interceptor {
  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    FlutterSecureStorage storage = AuthController.to.storage;
    var refreshToken = await storage.read(key: 'refresh_token');
    if (refreshToken != null) {
      var accessToken = await storage.read(key: 'access_token');
      if (parseJwt(accessToken!)["exp"] * 1000 <
              DateTime.now().millisecondsSinceEpoch ||
          (accessToken == null)) {
        print('Access token expired');
        await AmplifyService.getTokensWithRefreshToken(refreshToken);
        accessToken = await storage.read(key: 'access_token');
        print('Access token updated');
      }
      options.headers['Authorization'] = 'Bearer $accessToken';
      handler.next(options);
    } else {
      print("refresh token doesn't exist");
      options.extra['tokenErrorType'] = TokenErrorType.tokenNotFound;
      DioError _err = DioError(requestOptions: options);
      handler.reject(_err, true);
    }
  }

  @override
  void onResponse(
    dynamic response,
    ResponseInterceptorHandler handler,
  ) =>
      handler.next(response);

  @override
  void onError(
    DioError err,
    ErrorInterceptorHandler handler,
  ) {
    if (err.requestOptions.extra['tokenErrorType'] ==
        TokenErrorType.tokenNotFound) {
      Get.toNamed('/auth');
      return;
    } else if (err.response != null ? err.response!.statusCode == 303 : false) {
      Get.toNamed('/register_info');
      return;
    } else {
      inspect(err);
      handler.next(err);
    }
  }

  // bool _shouldRetry(DioError err) {
  //   return err.type == DioErrorType.other &&
  //       err.error != null &&
  //       err.error is SocketException;
  // }

  // handler.next(err);
}

class KakaoDioAuthInterceptor extends Interceptor {
  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    options.headers['Authorization'] = 'KakaoAK $kakaoRestApiKey';
    handler.next(options);
  }

  @override
  void onResponse(
    dynamic response,
    ResponseInterceptorHandler handler,
  ) =>
      handler.next(response);

  @override
  void onError(
    DioError err,
    ErrorInterceptorHandler handler,
  ) {
    if (err.requestOptions.extra['tokenErrorType'] ==
        TokenErrorType.tokenNotFound) {
      Get.toNamed('/auth');
      return;
    } else if (err.response != null ? err.response!.statusCode == 303 : false) {
      Get.toNamed('/register_info');
      return;
    } else {
      inspect(err);
      handler.next(err);
    }
  }

  // bool _shouldRetry(DioError err) {
  //   return err.type == DioErrorType.other &&
  //       err.error != null &&
  //       err.error is SocketException;
  // }

  // handler.next(err);
}
