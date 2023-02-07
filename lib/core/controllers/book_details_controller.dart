import 'dart:developer';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/services/kakao_service.dart';
import 'package:bookworm_friends/core/services/library_api_service.dart';
import 'package:bookworm_friends/core/services/user_api_service.dart';
import 'package:emojis/emoji.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';

class BookDetailsController extends GetxController
    with GetTickerProviderStateMixin {
  static BookDetailsController get to => Get.find<BookDetailsController>();
  late TabController tabController;
  late TabController emojiTabController;
  late TextEditingController memoTextController;
  late TextEditingController complimentTextController;

  RxBool loading = true.obs;
  RxString shelf = ''.obs;
  RxMap bookInfo = {}.obs;
  RxInt saveBookStatus = 0.obs;
  Rx<DateTime> startReadDate = DateTime.now().obs;
  Rx<DateTime> finishReadDate = DateTime.now().obs;

  RxString username = ''.obs;
  RxString isbn = ''.obs;
  RxBool editMode = false.obs;
  RxBool self = false.obs;

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(length: 2, vsync: this);
    emojiTabController =
        TabController(length: EmojiGroup.values.length, vsync: this);
    tabController.addListener(tabControllerListener);
    memoTextController = TextEditingController();
    complimentTextController = TextEditingController();
  }

  @override
  void onClose() {
    super.onClose();
    tabController.removeListener(tabControllerListener);
    tabController.dispose();
    emojiTabController.dispose();
    memoTextController.dispose();
  }

  void tabControllerListener() {
    update();
    log(tabController.index.toString());
  }

  Future<void> getBookDetails({String? username}) async {
    loading.value = true;
    Map _bookDetails = (await KakaoService.searchBooks(
        bookInfo['isbn'].split(' ')[0], 1, 1))['documents'][0]
      ..remove('status');
    Map _libraryBookDetails = await LibraryApiService.getBookDetails(
        bookInfo['isbn'],
        username: username);
    bookInfo.addAll(_bookDetails);
    bookInfo.addAll(_libraryBookDetails);
    log(bookInfo.toString());
    loading.value = false;
  }

  Future<void> getBookCompliments({String? username}) async {
    var _bookCompliments = await LibraryApiService.getBookCompliments(
        bookInfo['isbn'],
        username: username);
    print(_bookCompliments);
    bookInfo['compliments'] = _bookCompliments;
  }

  Future<void> updateBookStatus() async {
    EasyLoading.show();
    var success = await LibraryApiService.updateBookStatus(
      bookInfo['isbn'],
      saveBookStatus.value,
      startReadDate: saveBookStatus.value != 0 ? startReadDate.value : null,
      finishReadDate: saveBookStatus.value == 2 ? finishReadDate.value : null,
    );
    if (success) {
      EasyLoading.showSuccess('도서 상태가 수정되었습니다');
      LibraryController.to.getLibrary(); 
      LibraryController.to.getFinishedBooks();
      Map _libraryBookDetails =
          await LibraryApiService.getBookDetails(bookInfo['isbn']);
      bookInfo['status'] = saveBookStatus.value;
      bookInfo.addAll(_libraryBookDetails);
      update();
      bookInfo.refresh();
    } else {
      EasyLoading.showError('오류가 발생했습니다.\n잠시 후 다시 시도해 주세요');
    }
    EasyLoading.dismiss();
  }

  Future<void> postMemo() async {
    EasyLoading.show();
    var success = await LibraryApiService.postMemo(
      bookInfo['isbn'],
      memoTextController.text,
    );
    memoTextController.clear();
    if (success) {
      Map _libraryBookDetails =
          await LibraryApiService.getBookDetails(bookInfo['isbn']);
      bookInfo.addAll(_libraryBookDetails);
      update();
      bookInfo.refresh();
    } else {
      EasyLoading.showError('오류가 발생했습니다.\n잠시 후 다시 시도해 주세요');
    }
    EasyLoading.dismiss();
  }

  Future<void> updateMemo(int index) async {
    EasyLoading.show();
    var success = await LibraryApiService.updateMemo(
      bookInfo['memos'][index]['id'],
      memoTextController.text,
    );
    memoTextController.clear();

    if (!success) {
      EasyLoading.showError('오류가 발생했습니다.\n잠시 후 다시 시도해 주세요');
    }
    EasyLoading.dismiss();
  }

  Future<void> deleteMemo(int index) async {
    EasyLoading.show();

    var success =
        await LibraryApiService.deleteMemo(bookInfo['memos'][index]['id']);
    if (!success) {
      EasyLoading.showError('오류가 발생했습니다\n잠시 후 다시 시도해 주세요');
    }
    EasyLoading.dismiss();
  }

  Future<void> postCompliment(String emoji) async {
    EasyLoading.show();
    var success = await LibraryApiService.postCompliment(
        username.value, isbn.value, emoji);
    if (!success) {
      EasyLoading.showError('오류가 발생했습니다\n잠시 후 다시 시도해 주세요');
    }
    EasyLoading.dismiss();
  }
}
