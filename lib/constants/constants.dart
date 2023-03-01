import 'package:flutter/material.dart';

const String endpointUrl =
    // 'http://ec2-54-180-99-73.ap-northeast-2.compute.amazonaws.com';
    'http://9ffa-123-214-62-216.ngrok.io';
const String kakaoEndpointUrl = 'https://dapi.kakao.com';

const String kakaoRestApiKey = 'ab7c0da780466d764fbee0e55e65900c';
const String kakaoNativeAppKey = '321c930aad76d3c1da409ed33bd05895';

const String cognitoClientId = '71vfkcgaaekbqmmcli2jbncg60';
const String cognitoPoolId = 'ap-northeast-2_MGdU7uQ11';
const String cognitoPoolUrl = 'bookworm-friends.auth.ap-northeast-2';
const String redirectUri = 'bookworm-friends://home';
const String logoutUri = 'bookworm-friends://auth';

const Color kakaoLoginColor = Color(0xffFEE500);

const Color greenThemeColor = Color(0xff09BC8A);

const Color darkPrimaryColor = Color(0xff212529);
const Color softRedColor = Color(0xffD9433A);
const Color cancelRedColor = Color(0xffD9433A);
const Color lightGrayColor = Color(0xffE9ECEF);
const Color mainGrayColor = Color(0xff8a9197);
const Color grayColor = Color(0xffADB5BD);
const Color backgroundColor = Color(0xffF5F6F8);

List<double> bookOpacityList = [0.4, 0.7, 1.0];

List<String> categoryDummy = [
  '일반',
];

Map<String, List> libraryListDummy = {
  '일반': [],
};

String dummyImage = 'http://image.yes24.com/goods/109705390/XL';
