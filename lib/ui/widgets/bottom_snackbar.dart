import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BottomSnackbar extends GetSnackBar {
  final String text;
  final TextAlign align;

  BottomSnackbar({
    Key? key,
    required this.text,
    this.align = TextAlign.start,
  }) : super(
          key: key,
          messageText: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
            ),
            textAlign: align,
          ),
          borderRadius: 10,
          margin: const EdgeInsets.only(left: 10, right: 10, bottom: 10),
          duration: const Duration(seconds: 2),
          isDismissible: false,
          backgroundColor: darkPrimaryColor.withOpacity(0.8),
        );
}