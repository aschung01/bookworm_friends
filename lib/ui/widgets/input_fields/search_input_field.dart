import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:flutter/material.dart';

class SearchInputField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final void Function(String) onFieldSubmitted;
  const SearchInputField({
    Key? key,
    required this.controller,
    this.hintText = '어떤 책을 찾으시나요?',
    required this.onFieldSubmitted,
    this.focusNode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      focusNode: focusNode,
      controller: controller,
      textAlignVertical: TextAlignVertical.center,
      decoration:  InputDecoration(
        contentPadding:const EdgeInsets.only(
          left: 0,
          bottom: 14,
        ),
        border: InputBorder.none,
        hintText: hintText,
        hintStyle:const TextStyle(
          fontSize: 14,
          color: grayColor,
        ),
      ),
      cursorColor: AppController.to.themeColor,
      cursorHeight: 24,
      onFieldSubmitted: onFieldSubmitted,
      maxLines: 1,
      style: const TextStyle(
        fontSize: 14,
        color: darkPrimaryColor,
      ),
    );
  }
}
