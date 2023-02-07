import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/core/controllers/settings_controller.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/input_fields/memo_input_field.dart';
import 'package:bookworm_friends/ui/widgets/input_fields/username_input_field.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class EditUsernameBottomSheet extends GetView<SettingsController> {
  final Function() onSavePressed;
  const EditUsernameBottomSheet({
    Key? key,
    required this.onSavePressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              padding: const EdgeInsets.fromLTRB(25, 25, 25, 0),
              child: Form(
                key: controller.formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: UsernameInputField(
                  controller: controller.usernameTextController,
                  validator: controller.usernameValidator,
                  onChanged: (String text) {
                    controller.onUsernameChanged(text);
                  },
                ),
              ),
            ),
          ),
        ),
        GetX<SettingsController>(
          builder: (_) {
            return Padding(
              padding:
                  EdgeInsets.only(bottom: context.mediaQueryPadding.bottom),
              child: ElevatedActionButton(
                buttonText: '저장',
                width: context.width,
                height: 50,
                borderRadius: 0,
                onPressed: onSavePressed,
                activated: _.usernameTextController.text.isNotEmpty &&
                    _.isUsernameValid.value &&
                    _.isUsernameAvailable.value,
              ),
            );
          },
        ),
      ],
    );
  }
}

void getEditUsernameBottomSheet({
  required Function() onSavePressed,
}) {
  Get.bottomSheet(
    EditUsernameBottomSheet(
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
