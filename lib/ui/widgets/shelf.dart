import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Shelf extends StatelessWidget {
  final double? width;
  const Shelf({Key? key, this.width,}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      width: width ?? context.width * 0.95,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 2),
            blurRadius: 2,
            color: Colors.black.withOpacity(0.25),
          ),
        ],
      ),
    );
  }
}
