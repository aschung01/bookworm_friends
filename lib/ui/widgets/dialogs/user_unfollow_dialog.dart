import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/src/foundation/key.dart';
import 'package:flutter/src/widgets/framework.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserUnfollowDialog extends StatelessWidget {
  final Function() onUnfollowPressed;
  const UserUnfollowDialog({
    Key? key,
    required this.onUnfollowPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        '정말 팔로우를 취소하시겠어요?',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: darkPrimaryColor,
          fontSize: 16,
        ),
      ),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextActionButton(
            buttonText: '돌아가기',
            isUnderlined: false,
            onPressed: () {
              Get.back();
            },
          ),
          const SizedBox(
            width: 30,
          ),
          ElevatedActionButton(
            width: 100,
            height: 40,
            backgroundColor: lightGrayColor,
            textStyle: const TextStyle(
              color: darkPrimaryColor,
              fontSize: 16,
            ),
            buttonText: '언팔로우',
            onPressed: onUnfollowPressed,
          ),
        ],
      ),
    );
  }
}

void getUserUnfollowDialog({
  required Function() onUnfollowPressed,
}) {
  Get.dialog(
    UserUnfollowDialog(
      onUnfollowPressed: onUnfollowPressed,
    ),
  );
}
