import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/models/user_library_model.dart';
import 'package:bookworm_friends/core/services/user_api_service.dart';
import 'package:bookworm_friends/ui/widgets/library/library.dart';
import 'package:bookworm_friends/ui/widgets/library/user_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:get/get.dart';

class UserController extends GetxController with GetTickerProviderStateMixin {
  static UserController get to => Get.find<UserController>();
  late TabController userTabController;
  TextEditingController searchUserTextController = TextEditingController();
  RxBool isAuthenticated = false.obs;
  FlutterSecureStorage storage = const FlutterSecureStorage();
  RxList userFollowing = [].obs;
  RxMap usersLibrary = {}.obs;
  RxInt userTabIndex = 0.obs;

  RxList searchResult = [].obs;

  // Search - User library page
  RxBool loading = false.obs;
  RxList<String> shelf = <String>[].obs;
  RxMap<String, List> library = <String, List>{}.obs;
  RxList finishedBooks = [].obs;
  RxBool following = false.obs;
  RxString username = '???'.obs;
  RxBool finishedBookLoading = false.obs;
  RxInt pickerYear = DateTime.now().year.obs;
  RxInt pickerMonth = DateTime.now().month.obs;
  RxInt filterYear = DateTime.now().year.obs;
  RxInt filterMonth = 0.obs;
  late FixedExtentScrollController pickerYearScrollController;
  late FixedExtentScrollController pickerMonthScrollController;

  bool rebuild = false;
  RxBool userInfoLoading = false.obs;
  RxMap userInfo = {}.obs;

  @override
  void onInit() {
    super.onInit();
    userTabController = TabController(length: 1, vsync: this);
    pickerYearScrollController = FixedExtentScrollController();
    pickerMonthScrollController = FixedExtentScrollController();
  }

  @override
  void onClose() {
    pickerYearScrollController.dispose();
    pickerMonthScrollController.dispose();
    super.onClose();
  }

  void clearLibrary() {
    library.clear();
    shelf.clear();
  }

  Future<void> searchUsers() async {
    if (searchUserTextController.text.isNotEmpty) {
      var resData =
          await UserApiService.searchUsers(searchUserTextController.text);
      searchResult.clear();
      searchResult.addAll(resData);
    }
  }

  Future<void> getUserLibrary({bool searchPage = false}) async {
    Map resData = {};
    if (!searchPage) {
      resData = await UserApiService.getUserLibrary(
          usersLibrary[userTabIndex.value - 1].username);
    } else {
      resData = await UserApiService.getUserLibrary(username.value);
    }
    // clearLibrary();
    for (var e in resData['library']) {
      library.addAll({
        e['name']: e['books'],
      });
      shelf.add(e['name']);
    }
    following.value = resData['following'];
  }

  Future<void> getUserFinishedBooks({bool searchPage = false}) async {
    finishedBookLoading.value = true;
    List resData = [];
    if (!searchPage) {
      resData = await UserApiService.getUserFinishedBooks(
        usersLibrary[userTabIndex.value - 1].username,
        usersLibrary[userTabIndex.value - 1].filterYear,
        usersLibrary[userTabIndex.value - 1].filterMonth,
      );
      usersLibrary[userTabIndex.value - 1].finishedBooks.clear();
      usersLibrary[userTabIndex.value - 1].finishedBooks.addAll(resData);
      usersLibrary[userTabIndex.value - 1].filterYear = filterYear.value;
      usersLibrary[userTabIndex.value - 1].filterMonth = filterMonth.value;
    } else {
      resData = await UserApiService.getUserFinishedBooks(
        username.value,
        filterYear.value,
        filterMonth.value,
      );
      finishedBooks.clear();
      finishedBooks.addAll(resData);
    }
    finishedBookLoading.value = false;
  }

  Future<void> getUserFollowing() async {
    userFollowing.value = await UserApiService.getUserFollowing();
    userTabController.dispose();
    userTabController =
        TabController(length: userFollowing.length + 1, vsync: this);
    userTabController.animation?.addListener(() {
      userTabIndex.value = userTabController.animation!.value.round();
    });

    userTabIndex.listen(
      (int index) async {
        if (index > 0) {
          if (!usersLibrary.containsKey(index - 1)) {
            loading.value = true;
            Map<String, List<dynamic>> _library = {};
            List<String> _shelf = [];
            List _finishedBooks = [];
            bool _following = false;

            Map _libraryData = await UserApiService.getUserLibrary(
                userFollowing[index - 1]['username']);
            clearLibrary();
            for (var e in _libraryData['library']) {
              _library.addAll({
                e['name']: e['books'],
              });
              _shelf.add(e['name']);
            }
            _following = _libraryData['following'];

            finishedBookLoading.value = true;
            _finishedBooks.addAll(await UserApiService.getUserFinishedBooks(
              userFollowing[index - 1]['username'],
              filterYear.value,
              filterMonth.value,
            ));
            finishedBookLoading.value = false;

            usersLibrary.addAll(
              {
                (index - 1): UserLibraryModel(
                  username: userFollowing[index - 1]['username'],
                  library: _library,
                  shelf: _shelf,
                  following: _following,
                  finishedBooks: _finishedBooks,
                  filterYear: DateTime.now().year,
                ),
              },
            );
            loading.value = false;
          }
        }
      },
    );
  }

  Future<void> getFollowingUserInfo() async {
    userInfoLoading.value = true;
    userInfo.addAll(await UserApiService.getFollowingUserInfo(
        usersLibrary[userTabIndex.value - 1].username));
    userInfoLoading.value = false;
  }

  Future<void> updateUserFollowing({String? followingUsername}) async {
    if (followingUsername != null) {
      await UserApiService.updateUserFollowing(followingUsername);
    } else {
      following.value = !following.value;
      await UserApiService.updateUserFollowing(username.value);
    }

    // userTabController.animateTo(0, duration: Duration.zero);
    userTabController.index = 0;
    await getUserFollowing();
    rebuild = true;

    userFollowing.refresh();
    update();
  }

  Future<void> pokeUser(String username) async {
    EasyLoading.show();
    var success = await UserApiService.pokeUser(username);
    if (success) {
      EasyLoading.showSuccess('친구를 콕 찔렀어요');
    } else {
      EasyLoading.showError('오류가 발생했습니다.\n잠시 후 다시 시도해 주세요.');
    }
    EasyLoading.dismiss();
  }
}
