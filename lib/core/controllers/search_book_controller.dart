import 'dart:developer';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/services/kakao_service.dart';
import 'package:bookworm_friends/core/services/library_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';

class SearchBookController extends GetxController {
  static SearchBookController get to => Get.find<SearchBookController>();

  late TextEditingController searchTextController;
  RxBool loading = false.obs;
  RxInt infoViewPage = 0.obs;
  RxInt searchPage = 1.obs;
  RxList searchResult = [].obs;
  RxMap bookInfo = {}.obs;
  RxString saveBookShelf = ''.obs;
  RxInt saveBookStatus = 0.obs;
  Rx<DateTime> startReadDate = DateTime.now().obs;
  Rx<DateTime> finishReadDate = DateTime.now().obs;

  @override
  void onInit() {
    super.onInit();
    searchTextController = TextEditingController();
  }

  @override
  void onClose() {
    searchTextController.dispose();
  }

  void reset() {
    resetBookSave();
    bookInfo.clear();
    searchResult.clear();
    searchPage.value = 1;
    searchTextController.clear();
  }

  void resetBookSave() {
    infoViewPage.value = 0;
    saveBookShelf.value = '';
    saveBookStatus.value = 0;
    startReadDate.value = DateTime.now();
    finishReadDate.value = DateTime.now();
  }

  Future<void> searchBooks() async {
    if (searchTextController.text.isNotEmpty) {
      var res = await KakaoService.searchBooks(
          searchTextController.text, searchPage.value, 30);
      searchResult.clear();
      searchResult.addAll(res['documents']);
    }
  }

  Future<void> addBookToLibrary() async {
    EasyLoading.show();
    late bool success;
    if (saveBookStatus.value == 0) {
      success = await LibraryApiService.addBookToLibrary(
        saveBookShelf.value,
        bookInfo['isbn'],
        bookInfo['title'],
        bookInfo['thumbnail'],
        saveBookStatus.value,
      );
    } else if (saveBookStatus.value == 1) {
      success = await LibraryApiService.addBookToLibrary(
        saveBookShelf.value,
        bookInfo['isbn'],
        bookInfo['title'],
        bookInfo['thumbnail'],
        saveBookStatus.value,
        startReadDate: startReadDate.value,
      );
    } else if (saveBookStatus.value == 2) {
      success = await LibraryApiService.addBookToLibrary(
        saveBookShelf.value,
        bookInfo['isbn'],
        bookInfo['title'],
        bookInfo['thumbnail'],
        saveBookStatus.value,
        startReadDate: startReadDate.value,
        finishReadDate: finishReadDate.value,
      );
    }
    if (success) {
      EasyLoading.showSuccess('도서가 서재에 추가되었어요🔥');
    } else {
      EasyLoading.showError('오류가 발생했습니다.\n잠시 후 다시 시도해 주세요');
    }
    EasyLoading.dismiss();
  }
}
