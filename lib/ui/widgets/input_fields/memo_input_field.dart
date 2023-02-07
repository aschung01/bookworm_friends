import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MemoInputField extends StatelessWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  const MemoInputField({
    Key? key,
    required this.controller,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
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
        hintText: '메모를 입력하세요',
        hintStyle: TextStyle(
          fontSize: 13,
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
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: darkPrimaryColor,
      ),
    );
  }
}
