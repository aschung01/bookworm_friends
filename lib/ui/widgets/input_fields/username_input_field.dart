import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UsernameInputField extends StatelessWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  final String? Function(String?)? validator;
  const UsernameInputField({
    Key? key,
    required this.controller,
    this.onChanged,
    this.validator,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
        validator: validator,
      onChanged: onChanged,
      scrollPhysics: const ClampingScrollPhysics(),
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.only(
          left: 2,
          bottom: 15,
        ),
        border: InputBorder.none,
        constraints: BoxConstraints(
          minHeight: 120,
        ),
        hintText: '닉네임을 입력하세요',
        hintStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w300,
          height: 1.3,
          color: grayColor,
        ),
        counterStyle: TextStyle(
          fontSize: 10,
          color: grayColor,
        ),
      ),
      maxLines: null,
      maxLength: 500,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: darkPrimaryColor,
      ),
    );
  }
}
