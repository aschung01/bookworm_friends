import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DeleteBookBottomSheet extends StatelessWidget {
  final Function() onDeletePressed;
  const DeleteBookBottomSheet({
    Key? key,
    required this.onDeletePressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 25, bottom: 30, left: 25, right: 25),
      children: [
        const Text(
          '이 책을 서재에서 삭제할까요?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: darkPrimaryColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(
            top: 8,
            bottom: 15,
          ),
          child: Text(
            '책과 관련된 메모, 독서 기간 기록이 모두 삭제됩니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: darkPrimaryColor,
              fontSize: 14,
            ),
          ),
        ),
        SizeAccentTextButton(
          buttonText: '도서 삭제',
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

void getDeleteBookBottomSheet({
  required Function() onDeletePressed,
}) {
  Get.bottomSheet(
    DeleteBookBottomSheet(
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
