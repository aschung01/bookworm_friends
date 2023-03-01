import 'dart:developer';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/helpers/dio_auth_interceptor.dart';
import 'package:bookworm_friends/ui/widgets/bottom_snackbar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk_talk.dart';

const String _logoUrl =
    'notion://www.notion.so/image/https%3A%2F%2Fs3-us-west-2.amazonaws.com%2Fsecure.notion-static.com%2Feb465adb-a0e6-4ee0-966b-92cbdb6cfdab%2FGroup_1000006819.png?table=block&id=a43cd0ea-f3df-4795-b714-b264518c109c&spaceId=d192f59e-856c-4245-970f-24dfa495c236&width=250&userId=88e8da28-7b88-438a-ab50-4df5f9d52d86&cache=v2';

const String _appStoreUrl = '';

class KakaoService {
  static BaseOptions kakaoDioOptions = BaseOptions(
    baseUrl: kakaoEndpointUrl,
  );

  static Dio kakaoDio = Dio(kakaoDioOptions)
    ..interceptors.add(KakaoDioAuthInterceptor());

  static Future<dynamic> searchBooks(
    String query,
    int page,
    int size,
  ) async {
    String path = '/v3/search/book';
    Map<String, dynamic> parameters = {
      'query': query,
      'page': page, // 1~50
      'size': size, // 한 페이지에 보여질 문서 수, 1~50
      // 'target': target, // title, isbn, publisher, person
    };

    try {
      var res = await kakaoDio.get(path, queryParameters: parameters);
      log(res.toString());
      return res.data;
    } catch (e) {
      print(e);
    }
  }

  static loginWithKakao() async {
    try {
      OAuthToken token = await UserApi.instance.loginWithKakaoAccount();
      return token.toJson().map((key, value) => MapEntry(key, value?.toString()));
    } catch (e) {
      print(e);
    }
  }

  static loginWithKakaoTalk() async {
    try {
      OAuthToken token = await UserApi.instance.loginWithKakaoTalk();
      return token.toJson().map((key, value) => MapEntry(key, value?.toString()));
    } catch (e) {
      print(e);
    }
  }

  static void logoutKakaoTalk() async {
    try {
      var code = await UserApi.instance.logout();
      print(code.toString());
    } catch (e) {
      print(e);
    }
  }

  static void unlinkKakaoTalk() async {
    try {
      var code = await UserApi.instance.unlink();
      print(code.toString());
    } catch (e) {
      print(e);
    }
  }

  static Future<void> shareKakaoLink(
      String bookThumbnail, String bookTitle, String bookUrl) async {
    FeedTemplate shareText = FeedTemplate(
      content: Content(
        title: '${AuthController.to.userInfo['username']}님이 책을 공유했어요',
        description: bookTitle,
        imageUrl: Uri.parse(bookThumbnail),
        link: Link(
          webUrl: Uri.parse(bookUrl),
        ),
      ),
      buttons: [
        Button(
          title: '앱 다운받기',
          link: Link(webUrl: Uri.parse(_appStoreUrl)),
        ),
        Button(
          title: '책 보러가기',
          link: Link(webUrl: Uri.parse(bookUrl)),
        ),
      ],
    );

    try {
      if (!await ShareClient.instance.isKakaoTalkSharingAvailable()) {
        Get.showSnackbar(BottomSnackbar(text: '카카오톡이 설치되어 있지 않아 웹 공유를 시도합니다'));
        Uri shareUrl =
            await WebSharerClient.instance.makeDefaultUrl(template: shareText);
        await launchBrowserTab(shareUrl);
      }

      Uri uri = await ShareClient.instance.shareDefault(template: shareText);
      await ShareClient.instance.launchKakaoTalk(uri);
      print('카카오톡 공유 완료');
    } catch (error) {
      print('카카오톡 공유 실패 $error');
    }
  }
}
