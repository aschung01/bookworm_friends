import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MemoMenuBottomSheet extends StatelessWidget {
  final String memo;
  final Function() onDeletePressed;
  final Function() onUpdatePressed;
  const MemoMenuBottomSheet({
    Key? key,
    required this.memo,
    required this.onDeletePressed,
    required this.onUpdatePressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 25, bottom: 30, left: 25, right: 25),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            memo,
            style: const TextStyle(
              color: darkPrimaryColor,
              fontSize: 16,
            ),
          ),
        ),
        SizeAccentTextButton(
          buttonText: '삭제',
          textColor: cancelRedColor,
          onTap: onDeletePressed,
        ),
        const Divider(color: lightGrayColor, height: 15),
        SizeAccentTextButton(
          buttonText: '수정',
          onTap: onUpdatePressed,
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

void getMemoMenuBottomSheet({
  required String memo,
  required Function() onDeletePressed,
  required Function() onUpdatePressed,
}) {
  Get.bottomSheet(
    MemoMenuBottomSheet(
      memo: memo,
      onDeletePressed: onDeletePressed,
      onUpdatePressed: onUpdatePressed,
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
