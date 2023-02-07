import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/key.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:get/get.dart';

class BookProgressButton extends StatelessWidget {
  final int progress;
  final RxInt selectedProgress;
  const BookProgressButton({
    Key? key,
    required this.progress,
    required this.selectedProgress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: context.width * 0.23,
      height: context.width * 0.23 * 2 / 3,
      child: Obx(() {
        return Material(
          color: selectedProgress.value == progress
              ? AppController.to.themeColor
              : lightGrayColor,
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            onTap: () {
              selectedProgress.value = progress;
            },
            borderRadius: BorderRadius.circular(5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  () {
                    if (progress == selectedProgress.value) {
                      if (progress == 0) {
                        return PhosphorIcons.heartFill;
                      } else if (progress == 1) {
                        return PhosphorIcons.bookmarkSimpleFill;
                      } else {
                        return PhosphorIcons.circleWavyCheckFill;
                      }
                    } else {
                      if (progress == 0) {
                        return PhosphorIcons.heartLight;
                      } else if (progress == 1) {
                        return PhosphorIcons.bookmarkSimpleLight;
                      } else {
                        return PhosphorIcons.circleWavyCheckLight;
                      }
                    }
                  }(),
                  color: selectedProgress.value == progress
                      ? Colors.white
                      : darkPrimaryColor,
                  size: 26,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    () {
                      if (progress == 0) {
                        return '관심 도서';
                      } else if (progress == 1) {
                        return '읽는 중';
                      } else {
                        return '읽은 책';
                      }
                    }(),
                    style: TextStyle(
                      fontSize: 14,
                      color: selectedProgress.value == progress
                          ? Colors.white
                          : darkPrimaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
