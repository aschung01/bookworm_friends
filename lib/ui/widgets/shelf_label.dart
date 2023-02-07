import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';

class ShelfLabel extends StatelessWidget {
  final String label;
  const ShelfLabel({
    Key? key,
    required this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(3),
          topRight: Radius.circular(3),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: darkPrimaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
