import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ShelfNameInputField extends StatelessWidget {
  final TextEditingController controller;
  final bool update;
  final Function(String)? onChanged;
  const ShelfNameInputField({
    Key? key,
    required this.controller,
    this.update = false,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      scrollPhysics: const ClampingScrollPhysics(),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.only(
          left: 2,
          bottom: 15,
        ),
        border: InputBorder.none,
        constraints: const BoxConstraints(
          minHeight: 120,
        ),
        hintText: update ? '선반에 새로운 이름을 지어주세요' : '새 선반의 이름을 입력하세요',
        hintStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          height: 1.3,
          color: grayColor,
        ),
        counterStyle: const TextStyle(
          fontSize: 10,
          color: grayColor,
        ),
      ),
      maxLines: null,
      maxLength: 500,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        height: 1.3,
        color: darkPrimaryColor,
      ),
    );
  }
}
