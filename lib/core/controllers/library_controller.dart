import 'dart:developer';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/core/services/kakao_service.dart';
import 'package:bookworm_friends/core/services/library_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';

enum LibraryMode {
  library,
  editLibrary,
  editShelf,
}

class LibraryController extends GetxController {
  static LibraryController get to => Get.find<LibraryController>();
  RxList<String> shelf = <String>[].obs;
  RxMap<String, List> library = <String, List>{}.obs;
  RxList finishedBooks = [].obs;
  late TextEditingController shelfNameTextController;
  late FixedExtentScrollController pickerYearScrollController;
  late FixedExtentScrollController pickerMonthScrollController;

  Rx<LibraryMode> libraryMode = LibraryMode.library.obs;
  RxBool dragging = false.obs;
  RxInt emptiedShelf = (-1).obs;
  RxBool finishedBookLoading = false.obs;
  RxInt pickerYear = DateTime.now().year.obs;
  RxInt pickerMonth = DateTime.now().month.obs;
  RxInt filterYear = DateTime.now().year.obs;
  RxInt filterMonth = 0.obs;

  Rx<BoxShadow> shadow = BoxShadow(
    blurRadius: 4,
    offset: const Offset(0, 4),
    color: Colors.black.withOpacity(0.3),
  ).obs;

  @override
  void onInit() async {
    super.onInit();
    if (AuthController.to.isAuthenticated.value) {
      // await getLibrary();
      // await getFinishedBooks();
    } else {
      shelf.addAll(categoryDummy);
      library.addAll(libraryListDummy);
    }
    shelfNameTextController = TextEditingController();
    pickerYearScrollController = FixedExtentScrollController();
    pickerMonthScrollController = FixedExtentScrollController();
  }

  @override
  void onClose() {
    shelfNameTextController.dispose();
    pickerYearScrollController.dispose();
    pickerMonthScrollController.dispose();
  }

  void toggleBookElevation() {
    if (shadow.value ==
        BoxShadow(
          blurRadius: 4,
          offset: const Offset(0, 4),
          color: Colors.black.withOpacity(0.3),
        )) {
      shadow.value = BoxShadow(
        blurRadius: 4,
        offset: const Offset(2, 4),
        color: Colors.black.withOpacity(0.5),
      );
    } else {
      shadow.value = BoxShadow(
        blurRadius: 4,
        offset: const Offset(0, 4),
        color: Colors.black.withOpacity(0.3),
      );
    }
  }

  void clearLibrary() {
    library.clear();
    shelf.clear();
  }

  Future<void> getLibrary() async {
    List resData = await LibraryApiService.getLibrary();
    clearLibrary();
    for (var e in resData) {
      library.addAll({
        e['name']: e['books'],
      });
      shelf.add(e['name']);
    }
    log(library.toString());
  }

  Future<void> getFinishedBooks() async {
    finishedBookLoading.value = true;
    var resData = await LibraryApiService.getFinishedBooks(
        filterYear.value, filterMonth.value);
    finishedBooks.clear();
    finishedBooks.addAll(resData);
    finishedBookLoading.value = false;
  }

  Future<void> addShelf() async {
    if (shelfNameTextController.text.isNotEmpty) {
      EasyLoading.show();
      var success =
          await LibraryApiService.addShelf(shelfNameTextController.text);
      if (success) {
        EasyLoading.showSuccess('선반이 추가되었습니다');
        getLibrary();
      } else {
        EasyLoading.showError('오류가 발생했습니다.\n잠시 후 다시 시도해 주세요');
      }
    }
    shelfNameTextController.clear();
    EasyLoading.dismiss();
  }

  Future<void> updateShelfName(String shelf) async {
    if (shelfNameTextController.text.isNotEmpty) {
      EasyLoading.show();
      var success = await LibraryApiService.updateShelfName(
          shelf, shelfNameTextController.text);
      if (success) {
        EasyLoading.showSuccess('선반 이름이 수정되었습니다');
        getLibrary();
      } else {
        EasyLoading.showError('오류가 발생했습니다.\n잠시 후 다시 시도해 주세요');
      }
    }
    shelfNameTextController.clear();
    EasyLoading.dismiss();
  }

  Future<void> updateLibrary() async {
    await LibraryApiService.updateLibrary(library);
  }

  Future<void> updateShelfOrder() async {
    await LibraryApiService.updateShelfOrder(shelf);
  }

  Future<void> deleteBook(String isbn) async {
    EasyLoading.show();

    var success = await LibraryApiService.deleteBook(isbn);
    if (success) {
      EasyLoading.showSuccess('도서가 서재에서 삭제되었습니다');
    } else {
      EasyLoading.showError('오류가 발생했습니다\n잠시 후 다시 시도해 주세요');
    }
    EasyLoading.dismiss();
  }

  Future<void> deleteShelf(String shelf) async {
    EasyLoading.show();

    var success = await LibraryApiService.deleteShelf(shelf);
    if (success) {
      EasyLoading.showSuccess('선반이 삭제되었습니다');
    } else {
      EasyLoading.showError('오류가 발생했습니다\n잠시 후 다시 시도해 주세요');
    }
    EasyLoading.dismiss();
  }
}
