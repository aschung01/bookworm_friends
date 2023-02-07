import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class BookStatusBadge extends StatelessWidget {
  final int status;
  const BookStatusBadge({
    Key? key,
    required this.status,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (status == 0) {
      return Row(
        children: [
          Icon(
            PhosphorIcons.heartFill,
            color: AppController.to.themeColor,
            size: 20,
          ),
          const Padding(
            padding: EdgeInsets.only(
              left: 5,
            ),
            child: Text(
              '관심 도서',
              style: TextStyle(
                color: darkPrimaryColor,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    } else if (status == 1) {
      return Row(
        children: [
          Icon(
            PhosphorIcons.bookmarkSimpleFill,
            color: AppController.to.themeColor,
            size: 20,
          ),
          const Padding(
            padding: EdgeInsets.only(
              left: 5,
            ),
            child: Text(
              '읽는 중',
              style: TextStyle(
                color: darkPrimaryColor,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    } else {
      return Row(
        children: [
          Icon(
            PhosphorIcons.circleWavyCheckFill,
            color: AppController.to.themeColor,
            size: 20,
          ),
          const Padding(
            padding: EdgeInsets.only(
              left: 5,
            ),
            child: Text(
              '읽은 책',
              style: TextStyle(
                color: darkPrimaryColor,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }
  }
}
