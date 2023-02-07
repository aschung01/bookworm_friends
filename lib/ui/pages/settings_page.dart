import 'dart:math';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/settings_controller.dart';
import 'package:bookworm_friends/helpers/url_launcher.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_user_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/edit_profile_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/edit_username_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/follow_info_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/headers/header.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

const String _termsOfUseUrl =
    'https://bookwormfriends.notion.site/ed87960f6f9b4db8addfd36cc906bc92';

const String _privacyPolicyUrl =
    'https://bookwormfriends.notion.site/a4ffdbd423cd47cca55eac821283f728';

const String _personalInfoUrl = 'https://www.instagram.com/asounhoo1/';

const String _bugReportUrl = 'https://www.instagram.com/p/Ciea-GHJzra/';

const String _feedbackUrl = 'https://www.instagram.com/p/Ciebbsypkso/';

const String _noticeUrl =
    'https://bookwormfriends.notion.site/485dd45c334a42149f2cbb4c8c1a7239';
const String _helpUrl =
    'https://bookwormfriends.notion.site/503f3818b90949008cdcf9b8913d1053';

const String _appStoreId = '1643321634';

class SettingsPage extends GetView<SettingsController> {
  const SettingsPage({Key? key}) : super(key: key);

  void _onBackPressed() {
    Get.back();
  }

  void _onFollowInfoPressed() {
    AuthController.to.getUserInfo();
    controller.getFollowingInfo();
    getFollowInfoBottomSheet();
  }

  void _onUpdateEmojiPressed() {
    Get.back();
    getEmojiBottomSheet(onEmojiPressed: (String emoji) async {
      Get.back();
      await controller.updateEmoji(emoji);
    });
  }

  void _onUpdateUsernamePressed() {
    Get.back();
    controller.usernameTextController.text =
        AuthController.to.userInfo['username'];
    getEditUsernameBottomSheet(onSavePressed: () async {
      Get.back();
      await controller.updateUsername();
    });
  }

  void _onEditProfilePressed() {
    getEditProfileBottomSheet(
        updateEmoji: _onUpdateEmojiPressed,
        updateUsername: _onUpdateUsernamePressed);
  }

  void _onAppReviewPressed() {
    controller.inAppReview.openStoreListing(appStoreId: _appStoreId);
  }

  void _onSignInPressed() {
    Get.toNamed('/auth');
  }

  void _onSignOutPressed() {
    controller.signOut();
    AppController.to.rebuild = true;
    AppController.to.update();
  }

  void _onDeleteAccountPressed() {
    getDeleteUserBottomSheet(onDeletePressed: controller.deleteAccount);
  }

  @override
  Widget build(BuildContext context) {
    Future.delayed(Duration.zero, () {
      AuthController.to.getUserInfoIfEmpty();
      if (AuthController.to.isAuthenticated.value) {
        SettingsController.to.getPrivacy();
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Header(
              onPressed: _onBackPressed,
            ),
            Expanded(
              child: ListView(
                physics: const ClampingScrollPhysics(),
                children: [
                  GetX<AuthController>(
                    builder: (_) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: SizedBox(
                          height: 60,
                          width: context.width - 60,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 30),
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: lightGrayColor,
                                  ),
                                  child: Center(
                                    child: Text(
                                      AuthController.to.userInfo.isEmpty
                                          ? '?'
                                          : AuthController.to.userInfo['emoji'],
                                      style: const TextStyle(
                                        color: darkPrimaryColor,
                                        fontSize: 26,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _.userInfo.isEmpty
                                          ? '???'
                                          : _.userInfo['username'],
                                      style: const TextStyle(
                                        color: darkPrimaryColor,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _onFollowInfoPressed,
                                      child: Row(
                                        children: [
                                          const Text(
                                            '팔로워',
                                            style: TextStyle(
                                              color: darkPrimaryColor,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Flexible(
                                            flex: 1,
                                            fit: FlexFit.tight,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 12),
                                              child: Text(
                                                _.userInfo.isEmpty
                                                    ? '-'
                                                    : _.userInfo[
                                                            'count_followers']
                                                        .toString(),
                                                style: const TextStyle(
                                                  color: darkPrimaryColor,
                                                  fontSize: 20,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const Text(
                                            '팔로잉',
                                            style: TextStyle(
                                              color: darkPrimaryColor,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Flexible(
                                            flex: 1,
                                            fit: FlexFit.tight,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 12),
                                              child: Text(
                                                _.userInfo.isEmpty
                                                    ? '-'
                                                    : _.userInfo[
                                                            'count_following']
                                                        .toString(),
                                                style: const TextStyle(
                                                  color: darkPrimaryColor,
                                                  fontSize: 20,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 20,
                      bottom: 24,
                    ),
                    child: GetX<AuthController>(
                      builder: (_) {
                        if (_.isAuthenticated.value) {
                          return Center(
                            child: ElevatedActionButton(
                              width: min(context.width - 60, 330),
                              height: 36,
                              backgroundColor: lightGrayColor,
                              textStyle: const TextStyle(
                                  color: darkPrimaryColor, fontSize: 14),
                              buttonText: '프로필 수정',
                              onPressed: _onEditProfilePressed,
                            ),
                          );
                        } else {
                          return Center(
                            child: ElevatedActionButton(
                              width: min(context.width - 60, 330),
                              height: 36,
                              borderRadius: 50,
                              textStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                              buttonText: '로그인',
                              onPressed: _onSignInPressed,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const _SettingsLabelItem(labelText: '계정'),
                  _SettingsMenuItem(
                    labelText: '이메일',
                    trailing: Row(
                      children: [
                        () {
                          switch (AuthController.to.userInfo['auth_provider']) {
                            case 0:
                              return const GoogleIcon(
                                width: 18,
                                height: 18,
                              );
                            case 1:
                              return const KakaoIcon(
                                width: 18,
                                height: 18,
                              );
                            case 2:
                              return const AppleBlackIcon(
                                height: 50,
                              );
                            default:
                              return const SizedBox.shrink();
                          }
                        }(),
                        const SizedBox(width: 10),
                        Text(
                          AuthController.to.userInfo['email'] ?? '',
                        ),
                      ],
                    ),
                  ),
                  // _SettingsMenuItem(
                  //   labelText: '푸시 알림',
                  //    trailing: GetX<SettingsController>(builder: (_) {
                  //     return Transform.scale(
                  //       scale: 0.9,
                  //       child: CupertinoSwitch(
                  //         value: _.private.value,
                  //         onChanged: (value) {
                  //           _.private.value = value;
                  //         },
                  //         activeColor: AppController.to.themeColor,
                  //       ),
                  //     );
                  //   }),
                  // ),
                  _SettingsMenuItem(
                    labelText: '프로필 검색 허용',
                    trailing: GetX<SettingsController>(
                      builder: (_) {
                        if (AuthController.to.isAuthenticated.value) {
                          return Transform.scale(
                            scale: 0.9,
                            child: CupertinoSwitch(
                              value: !_.private.value,
                              onChanged: (value) {
                                _.private.value = !value;
                                _.updatePrivacy();
                              },
                              activeColor: AppController.to.themeColor,
                            ),
                          );
                        } else {
                          return const Text(
                            '-',
                            style: TextStyle(
                              fontSize: 20,
                              color: darkPrimaryColor,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _SettingsLabelItem(labelText: '개발자와 소통하기'),
                  _SettingsMenuItem(
                    labelText: '간단하게 리뷰 남기기',
                    trailing: const Icon(
                      PhosphorIcons.caretRightLight,
                      color: darkPrimaryColor,
                      size: 20,
                    ),
                    onTap: _onAppReviewPressed,
                  ),
                  _SettingsMenuItem(
                    labelText: '개발자 소개',
                    trailing: const Icon(
                      PhosphorIcons.caretRightLight,
                      color: darkPrimaryColor,
                      size: 20,
                    ),
                    onTap: () {
                      UrlLauncher.launchInApp(_personalInfoUrl);
                    },
                  ),
                  _SettingsMenuItem(
                    labelText: '개발자 괴롭히기',
                    trailing: const Icon(
                      PhosphorIcons.caretRightLight,
                      color: darkPrimaryColor,
                      size: 20,
                    ),
                    onTap: () {
                      UrlLauncher.launchInApp(_bugReportUrl);
                    },
                  ),
                  _SettingsMenuItem(
                    labelText: '피드백 작성하기',
                    trailing: const Icon(
                      PhosphorIcons.caretRightLight,
                      color: darkPrimaryColor,
                      size: 20,
                    ),
                    onTap: () {
                      UrlLauncher.launchInApp(_feedbackUrl);
                    },
                  ),
                  const SizedBox(height: 12),
                  const _SettingsLabelItem(labelText: '정보'),
                  _SettingsMenuItem(
                    labelText: '공지사항',
                    onTap: () {
                      UrlLauncher.launchInApp(_noticeUrl);
                    },
                  ),
                  _SettingsMenuItem(
                    labelText: '이용 가이드',
                    onTap: () {
                      UrlLauncher.launchInApp(_helpUrl);
                    },
                  ),
                  _SettingsMenuItem(
                    labelText: '이용약관',
                    onTap: () {
                      UrlLauncher.launchInApp(_termsOfUseUrl);
                    },
                  ),
                  _SettingsMenuItem(
                    labelText: '개인정보처리방침',
                    onTap: () {
                      UrlLauncher.launchInApp(_privacyPolicyUrl);
                    },
                  ),
                  _SettingsMenuItem(
                    labelText: '앱 버전',
                    trailing: GetBuilder<SettingsController>(
                      builder: (_) {
                        return Text(
                          _.appVersion + '+' + _.buildNumber,
                        );
                      },
                    ),
                  ),
                  if (AuthController.to.isAuthenticated.value)
                    _SettingsMenuItem(
                      labelText: '로그아웃',
                      onTap: _onSignOutPressed,
                    ),
                  if (AuthController.to.isAuthenticated.value)
                    _SettingsMenuItem(
                      labelText: '회원탈퇴',
                      onTap: _onDeleteAccountPressed,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsLabelItem extends StatelessWidget {
  final String labelText;
  const _SettingsLabelItem({
    Key? key,
    required this.labelText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 16, top: 12),
          child: Text(
            labelText,
            style: const TextStyle(
              color: darkPrimaryColor,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
        const Divider(
          color: lightGrayColor,
          thickness: 1,
          height: 1,
        ),
      ],
    );
  }
}

class _SettingsMenuItem extends StatelessWidget {
  final Function()? onTap;
  final String labelText;
  final Widget trailing;
  final double leftPadding;
  const _SettingsMenuItem({
    Key? key,
    this.onTap = null,
    required this.labelText,
    this.trailing = const SizedBox(),
    this.leftPadding = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: 46,
        width: context.width,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: 30, right: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: Text(
                    labelText,
                    style: const TextStyle(
                      fontSize: 14,
                      color: darkPrimaryColor,
                    ),
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ));
  }
}
