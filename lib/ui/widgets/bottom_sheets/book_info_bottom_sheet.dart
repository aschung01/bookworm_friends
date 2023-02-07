import 'dart:ui';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/controllers/search_book_controller.dart';
import 'package:bookworm_friends/core/services/kakao_service.dart';
import 'package:bookworm_friends/helpers/url_launcher.dart';
import 'package:bookworm_friends/ui/widgets/book_rating.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/buttons/book_progress_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/input_fields/memo_input_field.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class BookInfoBottomSheet extends GetView<SearchBookController> {
  final Function() onSavePressed;
  const BookInfoBottomSheet({
    Key? key,
    required this.onSavePressed,
  }) : super(key: key);

  void _onSharePressed() {
    KakaoService.shareKakaoLink(controller.bookInfo['thumbnail'],
        controller.bookInfo['title'], controller.bookInfo['url']);
  }

  void _onNextPressed() {
    if (AuthController.to.isAuthenticated.value) {
      if (controller.infoViewPage.value == 2) {
        onSavePressed();
      } else {
        controller.infoViewPage.value++;
      }
    } else {
      Get.toNamed('/auth');
    }
  }

  void _onChangeStartReadDatePressed(BuildContext context) async {
    DateTime? _pickedDate = await showDatePicker(
      context: context,
      initialDate: controller.startReadDate.value,
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.day,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppController.to.themeColor, // header background color
              onPrimary: Colors.white, // header text color
              onSurface: darkPrimaryColor, // body text color
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                  primary: AppController.to.themeColor // button text color
                  ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (_pickedDate != null) {
      controller.startReadDate.value = _pickedDate;
    }
  }

  void _onChangeReadPeriodPressed(BuildContext context) async {
    DateTimeRange? _range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppController.to.themeColor, // header background color
              onPrimary: Colors.white, // header text color
              onSurface: darkPrimaryColor, // body text color
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                  primary: AppController.to.themeColor // button text color
                  ),
            ),
          ),
          child: child!,
        );
      },
      // helpText: '독서 기간',
      // fieldStartLabelText: '독서 시작일',
    );

    if (_range != null) {
      controller.startReadDate.value = _range.start;
      controller.finishReadDate.value = _range.end;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Padding(
        padding: const EdgeInsets.only(top: 50),
        child: GetX<SearchBookController>(builder: (_) {
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                child: SizedBox(
                  height: 200 + context.mediaQueryPadding.bottom,
                  width: context.width,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                alignment: _.infoViewPage.value != 1
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  margin: const EdgeInsets.only(top: 100),
                  width: context.width,
                  padding: EdgeInsets.only(
                      top: 10, bottom: context.mediaQueryPadding.bottom + 50),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 10, bottom: 10),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Material(
                            type: MaterialType.transparency,
                            child: IconButton(
                              onPressed: _onSharePressed,
                              splashRadius: 20,
                              icon: const Icon(
                                PhosphorIcons.shareNetworkLight,
                                size: 26,
                                color: darkPrimaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Row(
                      //   mainAxisAlignment: MainAxisAlignment.end,
                      //   children: [
                      //     Text(
                      //       '평균 평점',
                      //       style: TextStyle(
                      //         fontSize: 13,
                      //         color: darkPrimaryColor,
                      //       ),
                      //     ),
                      //     Padding(
                      //       padding: const EdgeInsets.only(left: 10, right: 20),
                      //       child: BookRating(
                      //         rating: 4,
                      //         backgroundColor: lightGrayColor,
                      //       ),
                      //     ),
                      //   ],
                      // ),
                      Padding(
                        padding:
                            const EdgeInsets.only(top: 45, left: 35, right: 35),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: context.width - 70,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _.bookInfo['title'] ?? '',
                                      style: const TextStyle(
                                        color: darkPrimaryColor,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 10, bottom: 10),
                                    child: Row(
                                      children: List.generate(
                                        _.bookInfo['authors'].length,
                                        (index) => Text(
                                          _.bookInfo['authors'][index] +
                                              (_.bookInfo['authors'].length !=
                                                      index + 1
                                                  ? ', '
                                                  : ''),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: darkPrimaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxHeight: context.height * 0.45),
                        child: ListView(
                          physics: const ClampingScrollPhysics(),
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: [
                            () {
                              if (_.infoViewPage.value == 0) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(35, 25, 35, 25),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        padding: const EdgeInsets.only(
                                            top: 10, bottom: 15),
                                        child: Text(
                                          _.bookInfo['contents'] + '...',
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
                                        padding: const EdgeInsets.only(
                                            top: 10, bottom: 15),
                                        child: Text(
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
                                        padding: const EdgeInsets.only(
                                            top: 10, bottom: 15),
                                        child: Text(
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
                                      const Padding(
                                        padding: EdgeInsets.only(top: 10),
                                        child: Text(
                                          '---',
                                          style: TextStyle(
                                            color: darkPrimaryColor,
                                            fontSize: 13,
                                            height: 1.3,
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            top: 10, bottom: 15),
                                        child: Center(
                                          child: TextActionButton(
                                            buttonText: '자세히 보기',
                                            onPressed: () {
                                              UrlLauncher.launchInApp(
                                                  _.bookInfo['url']);
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
                                  ),
                                );
                              } else if (_.infoViewPage.value == 1) {
                                return Padding(
                                  key: Key('1'),
                                  padding: const EdgeInsets.only(
                                      top: 35, left: 35, right: 35, bottom: 30),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '어떤 선반에 담을까요?',
                                        style: TextStyle(
                                          color: darkPrimaryColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 20),
                                        child: Wrap(
                                          spacing: 12,
                                          runSpacing: 12,
                                          children: List.generate(
                                            LibraryController.to.shelf.length,
                                            (index) => ChoiceChip(
                                              label: Text(LibraryController
                                                  .to.shelf[index]),
                                              selected: _.saveBookShelf.value ==
                                                  LibraryController
                                                      .to.shelf[index],
                                              onSelected: (value) {
                                                _.saveBookShelf.value =
                                                    LibraryController
                                                        .to.shelf[index];
                                              },
                                              labelStyle: TextStyle(
                                                fontSize: 14,
                                                color: _.saveBookShelf.value ==
                                                        LibraryController
                                                            .to.shelf[index]
                                                    ? Colors.white
                                                    : darkPrimaryColor,
                                              ),
                                              pressElevation: 3,
                                              selectedColor:
                                                  AppController.to.themeColor,
                                              backgroundColor: lightGrayColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                return Padding(
                                  key: Key('2'),
                                  padding: const EdgeInsets.only(
                                      top: 35, left: 35, right: 35, bottom: 30),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          BookProgressButton(
                                            progress: 0,
                                            selectedProgress: _.saveBookStatus,
                                          ),
                                          Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal:
                                                    context.width * 0.03),
                                            child: BookProgressButton(
                                              progress: 1,
                                              selectedProgress:
                                                  _.saveBookStatus,
                                            ),
                                          ),
                                          BookProgressButton(
                                            progress: 2,
                                            selectedProgress: _.saveBookStatus,
                                          ),
                                        ],
                                      ),
                                      if (_.saveBookStatus.value == 1)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 30),
                                          child: Row(
                                            children: [
                                              const Text(
                                                '독서 시작일',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: darkPrimaryColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 16, right: 12),
                                                child: Text(
                                                  DateFormat('yyyy. MM. dd')
                                                      .format(_
                                                          .startReadDate.value),
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: darkPrimaryColor,
                                                  ),
                                                ),
                                              ),
                                              Material(
                                                type: MaterialType.transparency,
                                                child: IconButton(
                                                    splashRadius: 20,
                                                    onPressed: () =>
                                                        _onChangeStartReadDatePressed(
                                                            context),
                                                    icon: const Icon(
                                                      PhosphorIcons
                                                          .calendarLight,
                                                      color: darkPrimaryColor,
                                                      size: 26,
                                                    )),
                                              )
                                            ],
                                          ),
                                        ),
                                      if (_.saveBookStatus.value == 2)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 30),
                                          child: Row(
                                            children: [
                                              const Text(
                                                '독서 기간',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: darkPrimaryColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 16, right: 12),
                                                child: Text(
                                                  '${DateFormat('yyyy. MM. dd').format(_.startReadDate.value)} ~ ${DateFormat('yyyy. MM. dd').format(_.finishReadDate.value)}',
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: darkPrimaryColor,
                                                  ),
                                                ),
                                              ),
                                              Material(
                                                type: MaterialType.transparency,
                                                child: IconButton(
                                                  splashRadius: 20,
                                                  onPressed: () =>
                                                      _onChangeReadPeriodPressed(
                                                          context),
                                                  icon: const Icon(
                                                    PhosphorIcons.calendarLight,
                                                    color: darkPrimaryColor,
                                                    size: 26,
                                                  ),
                                                ),
                                              )
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }
                            }(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 35,
                top: 0,
                child: BookWidget(
                  imageUrl: _.bookInfo['thumbnail'],
                  height: 200,
                ),
              ),
              Positioned(
                bottom: 0,
                child: Column(
                  children: [
                    ElevatedActionButton(
                      leading: _.infoViewPage.value == 0
                          ? const Icon(
                              PhosphorIcons.plusLight,
                              color: Colors.white,
                              size: 26,
                            )
                          : null,
                      buttonText: () {
                        if (_.infoViewPage.value == 0) {
                          return '내 서재에 추가';
                        } else if (_.infoViewPage.value == 1) {
                          return '다음';
                        } else {
                          return '저장';
                        }
                      }(),
                      width: context.width,
                      height: 50,
                      borderRadius: 0,
                      onPressed: _onNextPressed,
                      activated: () {
                        if (_.infoViewPage.value == 1) {
                          return _.saveBookShelf.value != '';
                        } else {
                          return true;
                        }
                      }(),
                    ),
                    Container(
                      height: context.mediaQueryPadding.bottom,
                      width: context.width,
                      color: Colors.white,
                    )
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

void getBookInfoBottomSheet({
  required Function() onSavePressed,
}) {
  Get.bottomSheet(
    BookInfoBottomSheet(
      onSavePressed: onSavePressed,
    ),
    isScrollControlled: true,
    enableDrag: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    // shape: const RoundedRectangleBorder(
    //   borderRadius: BorderRadius.only(
    //     topLeft: Radius.circular(20),
    //     topRight: Radius.circular(20),
    //   ),
    // ),
  );
}
