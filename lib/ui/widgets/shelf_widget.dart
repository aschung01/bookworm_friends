import 'package:flutter/material.dart';

class ShelfWidget extends StatelessWidget {
  final double? width;
  const ShelfWidget({super.key, this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      width: width ?? MediaQuery.of(context).size.width * 0.95,
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
