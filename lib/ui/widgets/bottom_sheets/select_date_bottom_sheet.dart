import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SelectDateBottomSheet extends GetView<LibraryController> {
  final Function() onSavePressed;
  final bool update;
  const SelectDateBottomSheet({
    Key? key,
    required this.onSavePressed,
    this.update = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 20, 15, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '탐색 필터',
                  style: TextStyle(
                    color: darkPrimaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextActionButton(
                  buttonText: '완료',
                  textColor: AppController.to.themeColor,
                  fontSize: 14,
                  onPressed: onSavePressed,
                  isUnderlined: false,
                ),
              ],
            ),
          ),
          Row(
            children: [
              GetX<LibraryController>(
                builder: (_) {
                  List<Widget> _children = List<int>.generate(
                    20,
                    (i) {
                      if (i == 0) {
                        return i;
                      } else {
                        return DateTime.now().year + 1 - i;
                      }
                    },
                  ).map((e) {
                    if (e == 0) {
                      return Center(
                        child: Text(
                          '전체',
                          style: TextStyle(
                            color: (e == _.pickerYear.value)
                                ? AppController.to.themeColor
                                : darkPrimaryColor,
                            fontSize: (e == _.pickerYear.value) ? 26 : 20,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      );
                    } else if (e == _.pickerYear.value) {
                      return Center(
                        child: Text.rich(
                          TextSpan(
                            text: (e).toString(),
                            style: TextStyle(
                              color: AppController.to.themeColor,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                            children: [
                              TextSpan(
                                text: ' 년',
                                style: TextStyle(
                                  color: AppController.to.themeColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      return Center(
                        child: Text(
                          e.toString(),
                          style: const TextStyle(
                            color: darkPrimaryColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      );
                    }
                  }).toList();

                  _.pickerYearScrollController = FixedExtentScrollController(
                      initialItem: _.pickerYear.value == 0
                          ? 0
                          : (DateTime.now().year + 1 - _.pickerYear.value));

                  return Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 0),
                    child: SizedBox(
                      height: 200,
                      width: context.width * 0.5,
                      child: CupertinoPicker(
                        scrollController: _.pickerYearScrollController,
                        itemExtent: 80,
                        selectionOverlay: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: AppController.to.themeColor,
                                width: 0.5,
                              ),
                              bottom: BorderSide(
                                color: AppController.to.themeColor,
                                width: 0.5,
                              ),
                            ),
                          ),
                        ),
                        onSelectedItemChanged: (int y) {
                          if (y == 0) {
                            _.pickerYear.value = 0;
                            _.pickerMonth.value = 0;
                          } else {
                            _.pickerYear.value = DateTime.now().year + 1 - y;
                          }
                        },
                        children: _children,
                      ),
                    ),
                  );
                },
              ),
              GetX<LibraryController>(
                builder: (_) {
                  late List<Widget> _children;
                  if (_.pickerYear.value == 0) {
                    _children = [
                      Center(
                        child: Text(
                          '--',
                          style: TextStyle(
                            color: AppController.to.themeColor,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      )
                    ];
                  } else {
                    _children = List<int>.generate(
                      13,
                      (i) => i,
                    ).map((e) {
                      if (e == 0) {
                        return Center(
                          child: Text(
                            '전체',
                            style: TextStyle(
                              color: (e == _.pickerMonth.value)
                                  ? AppController.to.themeColor
                                  : darkPrimaryColor,
                              fontSize: (e == _.pickerMonth.value) ? 26 : 20,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        );
                      } else if (e == _.pickerMonth.value) {
                        return Center(
                          child: Text.rich(
                            TextSpan(
                              text: (e).toString(),
                              style: TextStyle(
                                color: AppController.to.themeColor,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                height: 1.0,
                              ),
                              children: [
                                TextSpan(
                                  text: ' 월',
                                  style: TextStyle(
                                    color: AppController.to.themeColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      } else {
                        return Center(
                          child: Text(
                            e.toString(),
                            style: const TextStyle(
                              color: darkPrimaryColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        );
                      }
                    }).toList();
                  }

                  _.pickerMonthScrollController = FixedExtentScrollController(
                      initialItem: _.pickerMonth.value);

                  return Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 0),
                    child: SizedBox(
                      height: 200,
                      width: context.width * 0.5,
                      child: CupertinoPicker(
                        scrollController: _.pickerMonthScrollController,
                        itemExtent: 80,
                        selectionOverlay: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: AppController.to.themeColor,
                                width: 0.5,
                              ),
                              bottom: BorderSide(
                                color: AppController.to.themeColor,
                                width: 0.5,
                              ),
                            ),
                          ),
                        ),
                        onSelectedItemChanged: (int m) {
                          _.pickerMonth.value = m;
                        },
                        children: _children,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(
            height: 30,
          ),
        ],
      ),
    );
  }
}

void getSelectDateBottomSheet({
  required Function() onSavePressed,
  bool update = true,
}) {
  Get.bottomSheet(
    SelectDateBottomSheet(
      onSavePressed: onSavePressed,
      update: update,
    ),
    isScrollControlled: true,
    ignoreSafeArea: false,
    enableDrag: false,
    isDismissible: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
    ),
  );
}

class UserSelectDateBottomSheet extends GetView<UserController> {
  final Function() onSavePressed;
  final bool update;
  const UserSelectDateBottomSheet({
    Key? key,
    required this.onSavePressed,
    this.update = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 20, 15, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '탐색 필터',
                  style: TextStyle(
                    color: darkPrimaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextActionButton(
                  buttonText: '완료',
                  textColor: AppController.to.themeColor,
                  fontSize: 14,
                  onPressed: onSavePressed,
                  isUnderlined: false,
                ),
              ],
            ),
          ),
          Row(
            children: [
              GetX<UserController>(
                builder: (_) {
                  List<Widget> _children = List<int>.generate(
                    20,
                    (i) {
                      if (i == 0) {
                        return i;
                      } else {
                        return DateTime.now().year + 1 - i;
                      }
                    },
                  ).map((e) {
                    if (e == 0) {
                      return Center(
                        child: Text(
                          '전체',
                          style: TextStyle(
                            color: (e == _.pickerYear.value)
                                ? AppController.to.themeColor
                                : darkPrimaryColor,
                            fontSize: (e == _.pickerYear.value) ? 26 : 20,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      );
                    } else if (e == _.pickerYear.value) {
                      return Center(
                        child: Text.rich(
                          TextSpan(
                            text: (e).toString(),
                            style: TextStyle(
                              color: AppController.to.themeColor,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                            children: [
                              TextSpan(
                                text: ' 년',
                                style: TextStyle(
                                  color: AppController.to.themeColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      return Center(
                        child: Text(
                          e.toString(),
                          style: const TextStyle(
                            color: darkPrimaryColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      );
                    }
                  }).toList();

                  _.pickerYearScrollController = FixedExtentScrollController(
                      initialItem: _.pickerYear.value == 0
                          ? 0
                          : (DateTime.now().year + 1 - _.pickerYear.value));

                  return Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 0),
                    child: SizedBox(
                      height: 200,
                      width: context.width * 0.5,
                      child: CupertinoPicker(
                        scrollController: _.pickerYearScrollController,
                        itemExtent: 80,
                        selectionOverlay: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: AppController.to.themeColor,
                                width: 0.5,
                              ),
                              bottom: BorderSide(
                                color: AppController.to.themeColor,
                                width: 0.5,
                              ),
                            ),
                          ),
                        ),
                        onSelectedItemChanged: (int y) {
                          if (y == 0) {
                            _.pickerYear.value = 0;
                            _.pickerMonth.value = 0;
                          } else {
                            _.pickerYear.value = DateTime.now().year + 1 - y;
                          }
                        },
                        children: _children,
                      ),
                    ),
                  );
                },
              ),
              GetX<UserController>(
                builder: (_) {
                  late List<Widget> _children;
                  if (_.pickerYear.value == 0) {
                    _children = [
                      Center(
                        child: Text(
                          '--',
                          style: TextStyle(
                            color: AppController.to.themeColor,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      )
                    ];
                  } else {
                    _children = List<int>.generate(
                      13,
                      (i) => i,
                    ).map((e) {
                      if (e == 0) {
                        return Center(
                          child: Text(
                            '전체',
                            style: TextStyle(
                              color: (e == _.pickerMonth.value)
                                  ? AppController.to.themeColor
                                  : darkPrimaryColor,
                              fontSize: (e == _.pickerMonth.value) ? 26 : 20,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        );
                      } else if (e == _.pickerMonth.value) {
                        return Center(
                          child: Text.rich(
                            TextSpan(
                              text: (e).toString(),
                              style: TextStyle(
                                color: AppController.to.themeColor,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                height: 1.0,
                              ),
                              children: [
                                TextSpan(
                                  text: ' 월',
                                  style: TextStyle(
                                    color: AppController.to.themeColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      } else {
                        return Center(
                          child: Text(
                            e.toString(),
                            style: const TextStyle(
                              color: darkPrimaryColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        );
                      }
                    }).toList();
                  }

                  _.pickerMonthScrollController = FixedExtentScrollController(
                      initialItem: _.pickerMonth.value);

                  return Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 0),
                    child: SizedBox(
                      height: 200,
                      width: context.width * 0.5,
                      child: CupertinoPicker(
                        scrollController: _.pickerMonthScrollController,
                        itemExtent: 80,
                        selectionOverlay: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: AppController.to.themeColor,
                                width: 0.5,
                              ),
                              bottom: BorderSide(
                                color: AppController.to.themeColor,
                                width: 0.5,
                              ),
                            ),
                          ),
                        ),
                        onSelectedItemChanged: (int m) {
                          _.pickerMonth.value = m;
                        },
                        children: _children,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(
            height: 30,
          ),
        ],
      ),
    );
  }
}

void getUserSelectDateBottomSheet({
  required Function() onSavePressed,
  bool update = true,
}) {
  Get.bottomSheet(
    UserSelectDateBottomSheet(
      onSavePressed: onSavePressed,
      update: update,
    ),
    isScrollControlled: true,
    ignoreSafeArea: false,
    enableDrag: false,
    isDismissible: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
    ),
  );
}
