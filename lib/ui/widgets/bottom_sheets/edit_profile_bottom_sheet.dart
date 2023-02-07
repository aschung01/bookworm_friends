import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class EditProfileBottomSheet extends StatelessWidget {
  final Function() updateEmoji;
  final Function() updateUsername;
  const EditProfileBottomSheet({
    Key? key,
    required this.updateEmoji,
    required this.updateUsername,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 25, bottom: 30, left: 25, right: 25),
      children: [
        SizeAccentTextButton(
          buttonText: '프로필 아이콘 변경',
          textColor: darkPrimaryColor,
          onTap: updateEmoji,
        ),
        const Divider(color: lightGrayColor, height: 15),
        SizeAccentTextButton(
          buttonText: '닉네임 변경',
          textColor: darkPrimaryColor,
          onTap: updateUsername,
        ),
        const Divider(color: lightGrayColor, height: 15),
        SizeAccentTextButton(
          buttonText: '취소',
          onTap: () {
            Get.back();
          },
        ),
      ],
    );
  }
}

void getEditProfileBottomSheet({
  required Function() updateEmoji,
  required Function() updateUsername,
}) {
  Get.bottomSheet(
    EditProfileBottomSheet(
      updateEmoji: updateEmoji,
      updateUsername: updateUsername,
    ),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
    ),
    backgroundColor: Colors.white,
  );
}
