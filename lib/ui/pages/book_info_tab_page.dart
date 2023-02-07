import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/helpers/url_launcher.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/loading_blocks.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BookInfoTabPage extends StatelessWidget {
  const BookInfoTabPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(35, 25, 25, 20),
      child: GetX<BookDetailsController>(
        builder: (_) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '책 소개',
                style: TextStyle(
                  color: darkPrimaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 15),
                child: _.loading.value
                    ? const LoadingBlock(height: 60)
                    : Text(
                        _.bookInfo['contents'],
                        style: const TextStyle(
                          color: darkPrimaryColor,
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
              ),
              const Text(
                '출판사',
                style: TextStyle(
                  color: darkPrimaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 15),
                child: _.loading.value
                    ? const LoadingBlock(height: 16)
                    : Text(
                        _.bookInfo['publisher'],
                        style: const TextStyle(
                          color: darkPrimaryColor,
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
              ),
              const Text(
                'ISBN',
                style: TextStyle(
                  color: darkPrimaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 15),
                child: _.loading.value
                    ? const LoadingBlock(height: 16)
                    : Text(
                        _.bookInfo['isbn'],
                        style: const TextStyle(
                          color: darkPrimaryColor,
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
              ),
              const Text(
                '페이지 수',
                style: TextStyle(
                  color: darkPrimaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 15),
                child: Text(
                  '-',
                  style: TextStyle(
                    color: darkPrimaryColor,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 15),
                child: Center(
                  child: TextActionButton(
                    buttonText: '자세히 보기',
                    onPressed: () {
                      UrlLauncher.launchInApp(_.bookInfo['url']);
                    },
                    textColor: darkPrimaryColor,
                    fontSize: 13,
                    // height: 30,
                    // isUnderlined: false,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
