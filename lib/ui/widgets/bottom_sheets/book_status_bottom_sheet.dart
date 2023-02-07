import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/ui/widgets/buttons/book_progress_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class BookStatusBottomSheet extends GetView<BookDetailsController> {
  final Function() onSavePressed;
  const BookStatusBottomSheet({
    Key? key,
    required this.onSavePressed,
  }) : super(key: key);

  void _onSharePressed() {}

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
      firstDate: DateTime(DateTime.now().year - 19),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendar,
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
    return Padding(
      padding: const EdgeInsets.only(top: 50),
      child: GetX<BookDetailsController>(
        builder: (_) {
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                child: SizedBox(
                  height: 100 + context.mediaQueryPadding.bottom,
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
                alignment: Alignment.topCenter,
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
                        key: Key('2'),
                        padding: const EdgeInsets.only(
                            top: 35, left: 35, right: 35, bottom: 30),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                BookProgressButton(
                                  progress: 0,
                                  selectedProgress: _.saveBookStatus,
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: context.width * 0.03),
                                  child: BookProgressButton(
                                    progress: 1,
                                    selectedProgress: _.saveBookStatus,
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
                                padding: const EdgeInsets.only(top: 30),
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
                                            .format(_.startReadDate.value),
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
                                            PhosphorIcons.calendarLight,
                                            color: darkPrimaryColor,
                                            size: 26,
                                          )),
                                    )
                                  ],
                                ),
                              ),
                            if (_.saveBookStatus.value == 2)
                              Padding(
                                padding: const EdgeInsets.only(top: 30),
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
                                            _onChangeReadPeriodPressed(context),
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
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                child: Column(
                  children: [
                    ElevatedActionButton(
                      buttonText: '저장',
                      width: context.width,
                      height: 50,
                      borderRadius: 0,
                      onPressed: onSavePressed,
                      activated: () {
                        return true;
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
        },
      ),
    );
  }
}

void getBookStatusBottomSheet({
  required Function() onSavePressed,
}) {
  Get.bottomSheet(
    BookStatusBottomSheet(
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
