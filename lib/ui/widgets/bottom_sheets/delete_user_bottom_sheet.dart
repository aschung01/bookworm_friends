import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DeleteUserBottomSheet extends StatelessWidget {
  final Function() onDeletePressed;
  const DeleteUserBottomSheet({
    Key? key,
    required this.onDeletePressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 25, bottom: 20, left: 25, right: 25),
      children: [
        SizeAccentTextButton(
          buttonText: '회원 탈퇴',
          textColor: cancelRedColor,
          onTap: onDeletePressed,
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

void getDeleteUserBottomSheet({
  required Function() onDeletePressed,
}) {
  Get.bottomSheet(
    DeleteUserBottomSheet(
      onDeletePressed: onDeletePressed,
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
