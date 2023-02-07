import 'dart:ui';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class BookWidget extends StatelessWidget {
  final double? height;
  final String imageUrl;
  final Function()? onTap;
  final Function()? onLongPress;
  final bool editMode;
  const BookWidget({
    Key? key,
    this.height,
    required this.imageUrl,
    this.editMode = false,
    this.onTap,
    this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!editMode) {
        return DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              LibraryController.to.shadow.value,
            ],
          ),
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              fit: StackFit.loose,
              clipBehavior: Clip.none,
              children: [
                imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        height: height ?? context.height * 0.15,
                        fit: BoxFit.fitHeight,
                        filterQuality: FilterQuality.high,
                      )
                    : Container(
                        height: height ?? context.height * 0.15,
                        width: (height ?? context.height * 0.15) / 1.6,
                        color: lightGrayColor,
                        alignment: Alignment.center,
                        child: const Text(
                          '이미지가 없습니다',
                          style: TextStyle(
                            color: darkPrimaryColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        );
      } else {
        return DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              LibraryController.to.shadow.value,
            ],
          ),
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              fit: StackFit.loose,
              clipBehavior: Clip.none,
              children: [
                imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        height: height ?? context.height * 0.15,
                        fit: BoxFit.fitHeight,
                        filterQuality: FilterQuality.high,
                      )
                    : Container(
                        height: height ?? context.height * 0.15,
                        width: (height ?? context.height * 0.15) / 1.6,
                        color: lightGrayColor,
                        alignment: Alignment.center,
                        child: const Text(
                          '이미지가 없습니다',
                          style: TextStyle(
                            color: darkPrimaryColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                Positioned(
                  top: -10,
                  left: -10,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                            blurRadius: 2,
                            offset: const Offset(0, 2),
                            color: Colors.black.withOpacity(0.5)),
                      ],
                    ),
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    child: IconButton(
                      onPressed: onTap,
                      iconSize: 15,
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        PhosphorIcons.trashLight,
                        color: darkPrimaryColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });
  }
}
