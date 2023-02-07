import 'dart:math' as Math;

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_details_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ComplimentBlock extends StatelessWidget {
  final List compliments;
  const ComplimentBlock({
    Key? key,
    required this.compliments,
  }) : super(key: key);

  void _onTap() {
    getComplimentDetailsBottomSheet(data: compliments);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
      ),
      height: 36,
      margin: const EdgeInsets.only(top: 10),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _onTap,
          borderRadius: BorderRadius.circular(5),
          splashColor: Colors.transparent,
          highlightColor: AppController.to.themeColor.withOpacity(0.2),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
            child: Row(
              children: List.generate(Math.min(compliments.length, 3) * 2 - 1,
                  (index) {
                if (index % 2 == 0) {
                  if (index ~/ 2 < 2) {
                    return Text(
                      compliments[index ~/ 2]['compliment'],
                      style: const TextStyle(
                        fontSize: 24,
                      ),
                    );
                  } else {
                    return Text(
                      '+${compliments.length - 2}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: darkPrimaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }
                } else {
                  return const SizedBox(width: 3);
                }
              }),
            ),
          ),
        ),
      ),
    );
  }
}
