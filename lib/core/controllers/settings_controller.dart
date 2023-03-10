import 'dart:developer';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/core/services/amplify_service.dart';
import 'package:bookworm_friends/core/services/user_api_service.dart';
import 'package:bookworm_friends/ui/widgets/bottom_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsController extends GetxController
    with GetTickerProviderStateMixin {
  static SettingsController get to => Get.find<SettingsController>();
  final formKey = GlobalKey<FormState>();
  final InAppReview inAppReview = InAppReview.instance;
  TextEditingController usernameTextController = TextEditingController();
  late String appVersion;
  late String buildNumber;
  late TabController followingInfoTabController;
  RxBool loading = false.obs;
  RxBool isUsernameValid = false.obs;
  RxBool isUsernameRegexValid = false.obs;
  RxBool isUsernameAvailable = false.obs;
  RxBool private = true.obs;

  RxMap followingInfo = {}.obs;

  @override
  void onInit() async {
    super.onInit();
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    appVersion = packageInfo.version;
    buildNumber = packageInfo.buildNumber;
    followingInfoTabController = TabController(length: 2, vsync: this);
  }

  @override
  void onClose() {
    super.onClose();
    followingInfoTabController.dispose();
  }

  void reset() {
    loading.value = false;
    usernameTextController.clear();
    isUsernameRegexValid.value = false;
    isUsernameAvailable.value = false;
  }

  String? usernameValidator(String? text) {
    const pattern =
        r'^(?=.{3,20}$)(?![_.])(?!.*[_.]{2})[a-zA-Z0-9???-??????-??????-???._\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]]+(?<![_.])$';
    final regExp = RegExp(pattern);
    if (text == null || text.isEmpty) {
      return '???????????? ??????????????????';
    } else if (text.length < 3) {
      return '3?????? ?????? ??????????????????';
    } else if (text.length > 20) {
      return '20??? ????????? ??????????????????';
    } else if (!regExp.hasMatch(text)) {
      return '????????? ????????? ???????????? ????????????';
    } else {
      if (!isUsernameAvailable.value) {
        if (usernameTextController.text !=
                AuthController.to.userInfo['username'] &&
            !loading.value) {
          return '?????? ???????????? ??????????????????';
        } else {
          return '?????? ???????????? ????????????';
        }
      } else {
        return null;
      }
    }
  }

  void onUsernameChanged(String text) async {
    if (usernameTextController.text.length >= 3 &&
        usernameTextController.text.length <= 20) {
      loading.value = true;
      await checkAvailableUsername();
      loading.value = false;
    }
    if (formKey.currentState != null) {
      bool isValid = formKey.currentState!.validate();
      isUsernameValid.value = isValid;
      print('isUsernameValid: ${isUsernameValid.value}');
    }
  }

  Future<void> checkAvailableUsername() async {
    print(usernameTextController.text);
    isUsernameAvailable.value = await UserApiService.checkUsernameAvailable(
        usernameTextController.text);
    print(
        'Username ${usernameTextController.text} is available : ${isUsernameAvailable.value}');
  }

  Future<void> getFollowingInfo() async {
    loading.value = true;
    followingInfo.clear();
    followingInfo.addAll(await UserApiService.getFollowingInfo());
    loading.value = false;
  }

  Future<void> updateEmoji(String emoji) async {
    EasyLoading.show();
    var success = await UserApiService.updateEmoji(emoji);
    if (success) {
      AuthController.to.getUserInfo();
      reset();
    } else {
      EasyLoading.showError('????????? ??????????????????.\n?????? ??? ?????? ????????? ?????????');
    }
    EasyLoading.dismiss();
  }

  Future<void> updateUsername() async {
    EasyLoading.show();
    await checkAvailableUsername();
    if (formKey.currentState != null) {
      bool isValid = formKey.currentState!.validate();
      isUsernameValid.value = isValid;
    }
    if (isUsernameAvailable.value && isUsernameValid.value) {
      var success =
          await UserApiService.updateUsername(usernameTextController.text);

      if (success) {
        await AuthController.to.getUserInfo();
        EasyLoading.showSuccess('???????????? ?????????????????????');
        reset();
      } else {
        EasyLoading.showError('????????? ??????????????????.\n?????? ??? ?????? ????????? ?????????');
      }
    }
    EasyLoading.dismiss();
    AuthController.to.update();
  }

  Future<void> updatePrivacy() async {
    await UserApiService.updatePrivacy(private.value);
  }

  Future<void> getPrivacy() async {
    private.value = await UserApiService.getPrivacy();
  }

  Future<void> signOut() async {
    Get.back();
    await AmplifyService.signOut();
    await AuthController.to.checkAuthentication();
  }

  Future<void> deleteAccount() async {
    Get.back();
    // var data = await AuthController.to.readIdToken();
    // await AmplifyService.deleteUser(data['email']);
    var success = await UserApiService.deleteAccount();
    if (success) {
      Get.showSnackbar(
        BottomSnackbar(
          text: '?????? ????????? ?????????????????????.\n?????? ?????? ????????? ???????????????',
          align: TextAlign.center,
        ),
      );
    }
    await AuthController.to.checkAuthentication();
  }
}
