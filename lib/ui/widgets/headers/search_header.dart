
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/ui/widgets/input_fields/search_input_field.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:get/get.dart';

class SearchHeader extends StatelessWidget with PreferredSizeWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool elevate;
  final void Function(String) onFieldSubmitted;
  final void Function() onBackPressed;

  SearchHeader({
    Key? key,
    required this.controller,
    required this.elevate,
    this.hintText = '어떤 책을 찾으시나요?',
    required this.onFieldSubmitted,
    required this.onBackPressed,
    this.focusNode,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: elevate ? 4 : 0,
      leadingWidth: 50,
      shape: elevate
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20)),
            )
          : null,
      leading: Padding(
        padding: const EdgeInsets.only(left: 10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: onBackPressed,
            splashRadius: 20,
            icon: const Icon(
              PhosphorIcons.caretLeftLight,
              color: darkPrimaryColor,
              size: 26,
            ),
          ),
        ),
      ),
      title: SizedBox(
        height: 56,
        width: context.width - 56,
        child: Center(
          child: SearchInputField(
            controller: controller,
            hintText: hintText,
            focusNode: focusNode,
            onFieldSubmitted: onFieldSubmitted,
          ),
        ),
      ),
    );
  }
}
