import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/src/foundation/key.dart';
import 'package:flutter/src/widgets/framework.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FollowingUserInfoDialog extends GetView<UserController> {
  const FollowingUserInfoDialog({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: lightGrayColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            margin: const EdgeInsets.only(right: 12),
            child: Text(
              controller.userFollowing[controller.userTabIndex.value - 1]
                  ['emoji'],
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: darkPrimaryColor,
                fontSize: 20,
              ),
            ),
          ),
          Text(
            controller.usersLibrary[controller.userTabIndex.value - 1].username,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: darkPrimaryColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: GetX<UserController>(builder: (_) {
        return SizedBox(
          height: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Row(
                children: [
                  const Text(
                    '팔로우',
                    style: TextStyle(
                      color: darkPrimaryColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: _.userInfoLoading.value
                        ? Row(
                            children: const [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: darkPrimaryColor,
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            _.userInfo.isEmpty
                                ? '-'
                                : _.userInfo['count_followers'].toString(),
                            style: const TextStyle(
                              color: darkPrimaryColor,
                              fontSize: 18,
                            ),
                          ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text(
                    '팔로잉',
                    style: TextStyle(
                      color: darkPrimaryColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: _.userInfoLoading.value
                        ? Row(
                            children: const [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: darkPrimaryColor,
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            _.userInfo.isEmpty
                                ? '-'
                                : _.userInfo['count_following'].toString(),
                            style: const TextStyle(
                              color: darkPrimaryColor,
                              fontSize: 18,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

void getFollowingUserInfoDialog() {
  Get.dialog(
    FollowingUserInfoDialog(),
  );
}
