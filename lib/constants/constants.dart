import 'package:flutter/material.dart';

const Color greenThemeColor = Color(0xff09BC8A);
const Color darkPrimaryColor = Color(0xff212529);
const Color softRedColor = Color(0xffD9433A);
const Color cancelRedColor = Color(0xffD9433A);
const Color lightGrayColor = Color(0xffE9ECEF);
const Color grayColor = Color(0xffADB5BD);
const Color backgroundColor = Color(0xffF8F9FA);

List<double> bookOpacityList = [0.4, 0.7, 1.0];

const String kakaoBookSearchBaseUrl = 'https://dapi.kakao.com';
// Provided at build time via --dart-define-from-file (env.json, gitignored).
const String kakaoRestApiKey = String.fromEnvironment('KAKAO_REST_API_KEY');

const String googleBooksBaseUrl = 'https://www.googleapis.com/books/v1';

// Provided at build time via --dart-define / --dart-define-from-file (see
// env.json, which is gitignored). Empty by default: the Google Books provider
// then runs keyless and falls back to Open Library.
const String googleBooksApiKey = String.fromEnvironment('GOOGLE_BOOKS_API_KEY');
