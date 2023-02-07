import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/input_fields/memo_input_field.dart';
import 'package:bookworm_friends/ui/widgets/input_fields/shelf_name_input_field.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UpdateShelfNameBottomSheet extends GetView<LibraryController> {
  final Function() onSavePressed;
  final bool update;
  const UpdateShelfNameBottomSheet({
    Key? key,
    required this.onSavePressed,
    this.update = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: ConstrainedBox(
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
                  child: ShelfNameInputField(
                    controller: controller.shelfNameTextController,
                    update: update,
                    onChanged: (p0) {
                      controller.update();
                    },
                  ),
                ),
              ),
            ),
          ),
          GetBuilder<LibraryController>(builder: (_) {
            return ElevatedActionButton(
              buttonText: '저장',
              width: context.width,
              height: 50,
              borderRadius: 0,
              onPressed: onSavePressed,
              activated: _.shelfNameTextController.text.isNotEmpty,
            );
          }),
        ],
      ),
    );
  }
}

void getAddOrUpdateShelfNameBottomSheet({
  required Function() onSavePressed,
  bool update = true,
}) {
  Get.bottomSheet(
    UpdateShelfNameBottomSheet(
      onSavePressed: onSavePressed,
      update: update,
    ),
    isScrollControlled: true,
    ignoreSafeArea: false,
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
