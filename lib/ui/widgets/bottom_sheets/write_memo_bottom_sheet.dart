import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/input_fields/memo_input_field.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class WriteMemoBottomSheet extends GetView<BookDetailsController> {
  final Function() onSavePressed;
  const WriteMemoBottomSheet({
    Key? key,
    required this.onSavePressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 25, 25, 0),
          child: Text(
            DateFormat('yyyy. MM. dd').format(DateTime.now()),
            style: const TextStyle(
              fontSize: 20,
              color: darkPrimaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: context.height -
                context.mediaQueryPadding.bottom -
                context.mediaQueryViewInsets.bottom -
                200,
          ),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(25, 10, 25, 0),
              child: MemoInputField(
                controller: controller.memoTextController,
                onChanged: (s) {
                  controller.update();
                },
              ),
            ),
          ),
        ),
        GetBuilder<BookDetailsController>(builder: (_) {
          return Padding(
            padding: EdgeInsets.only(bottom: context.mediaQueryPadding.bottom),
            child: ElevatedActionButton(
              buttonText: '저장',
              width: context.width,
              height: 50,
              borderRadius: 0,
              onPressed: onSavePressed,
              activated: _.memoTextController.text.isNotEmpty,
            ),
          );
        }),
      ],
    );
  }
}

void getWriteMemoBottomSheet({
  required Function() onSavePressed,
}) {
  Get.bottomSheet(
    WriteMemoBottomSheet(
      onSavePressed: onSavePressed,
    ),
    isScrollControlled: true,
    enableDrag: false,
    isDismissible: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
    ),
  );
}
