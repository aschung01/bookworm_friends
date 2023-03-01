import 'dart:developer';
import 'dart:math' as Math;
import 'dart:ui';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/core/models/user_library_model.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/following_user_info_dialog.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/user_unfollow_dialog.dart';
import 'package:bookworm_friends/ui/widgets/shelf.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class UserLibrary extends GetView<UserController> {
  final UserLibraryModel libraryModel;
  final bool loading;
  final double height;
  const UserLibrary({
    Key? key,
    required this.libraryModel,
    required this.height,
    this.loading = false,
  }) : super(key: key);

  void _onUserInfoTap() {
    if (!controller.loading.value) {
      getFollowingUserInfoDialog();
      controller.getFollowingUserInfo();
    }
  }

  void _onSaveFilterDatePressed() {
    controller.filterYear.value = controller.pickerYear.value;
    controller.filterMonth.value = controller.pickerMonth.value;
    controller.getUserFinishedBooks();
    Get.back();
  }

  void _onReadBooksFilterPressed(BuildContext context) {
    controller.pickerYear.value = controller.filterYear.value;
    controller.pickerMonth.value = controller.filterMonth.value;
    getUserSelectDateBottomSheet(onSavePressed: _onSaveFilterDatePressed);
  }

  void _onUpdateFollowingPressed() {
    if (libraryModel.following) {
      getUserUnfollowDialog(
        onUnfollowPressed: () async {
          Get.back();
          Get.toNamed('/loading');
          controller.usersLibrary.clear();
          await controller.updateUserFollowing(
              followingUsername: libraryModel.username);
          Get.back();
          controller.userFollowing.refresh();
        },
      );
    } else {
      controller.updateUserFollowing();
    }
  }

  void _onPokePressed() {
    controller.pokeUser(libraryModel.username);
  }

  @override
  Widget build(BuildContext context) {
    return GetX<UserController>(
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(bottom: context.mediaQueryPadding.bottom),
          child: Stack(
            fit: StackFit.loose,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: 56,
                child: SizedBox(
                  height: height,
                  width: context.width,
                  child: Stack(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Container(
                              width: context.width,
                              decoration: BoxDecoration(
                                color: lightGrayColor,
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: 4,
                                    offset: const Offset(0, -4),
                                    color: Colors.black.withOpacity(0.3),
                                  ),
                                ],
                              ),
                              child: () {
                                bool _isLibraryEmpty = true;

                                libraryModel.library.forEach((shelf, books) {
                                  if (books.isNotEmpty) {
                                    _isLibraryEmpty = false;
                                  }
                                });

                                return SingleChildScrollView(
                                  padding: const EdgeInsets.only(top: 16),
                                  physics: const ClampingScrollPhysics(),
                                  child: Column(
                                    children: List.generate(
                                      libraryModel.library.length,
                                      (shelfNum) {
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 26),
                                          child: Column(
                                            children: [
                                              SizedBox(
                                                height: context.height * 0.15,
                                                width: context.width * 0.95,
                                                child: Stack(
                                                  alignment:
                                                      Alignment.bottomLeft,
                                                  children: [
                                                    Positioned(
                                                      top: 0,
                                                      child: SizedBox(
                                                        height: context.height *
                                                            0.15,
                                                        width: context.width *
                                                            0.95,
                                                        child:
                                                            (_isLibraryEmpty &&
                                                                    shelfNum ==
                                                                        0)
                                                                ? Row(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .center,
                                                                    children: [
                                                                      const Padding(
                                                                        padding:
                                                                            EdgeInsets.only(right: 10),
                                                                        child:
                                                                            SadCharacter(
                                                                          height:
                                                                              100,
                                                                        ),
                                                                      ),
                                                                      Column(
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.center,
                                                                        children: [
                                                                          const Text(
                                                                            '서재가 비었어요...',
                                                                            style:
                                                                                TextStyle(
                                                                              color: grayColor,
                                                                              fontWeight: FontWeight.bold,
                                                                            ),
                                                                          ),
                                                                          if (libraryModel
                                                                              .following)
                                                                            Padding(
                                                                              padding: const EdgeInsets.only(top: 10),
                                                                              child: ElevatedActionButton(
                                                                                buttonText: '콕 찌르기',
                                                                                width: 80,
                                                                                height: 30,
                                                                                backgroundColor: grayColor,
                                                                                textStyle: const TextStyle(
                                                                                  color: Colors.white,
                                                                                ),
                                                                                onPressed: _onPokePressed,
                                                                              ),
                                                                            )
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  )
                                                                : ListView
                                                                    .separated(
                                                                    scrollDirection:
                                                                        Axis.horizontal,
                                                                    physics:
                                                                        const ClampingScrollPhysics(),
                                                                    shrinkWrap:
                                                                        true,
                                                                    padding: const EdgeInsets
                                                                            .only(
                                                                        left:
                                                                            15,
                                                                        right:
                                                                            15),
                                                                    itemBuilder:
                                                                        ((context,
                                                                            index) {
                                                                      return Hero(
                                                                        tag: libraryModel
                                                                            .library[libraryModel
                                                                                .shelf[
                                                                            shelfNum]]![index]['isbn'],
                                                                        child:
                                                                            Stack(
                                                                          children: [
                                                                            BookWidget(
                                                                              imageUrl: libraryModel.library[libraryModel.shelf[shelfNum]]![index]['thumbnail'],
                                                                              onTap: () {
                                                                                BookDetailsController.to.bookInfo.clear();
                                                                                BookDetailsController.to.bookInfo.addAll(libraryModel.library[libraryModel.shelf[shelfNum]]![index]);
                                                                                BookDetailsController.to.shelf.value = libraryModel.shelf[shelfNum];
                                                                                BookDetailsController.to.getBookDetails(username: libraryModel.username);
                                                                                BookDetailsController.to.tabController.index = 0;
                                                                                BookDetailsController.to.self.value = false;
                                                                                Get.toNamed('/details');
                                                                              },
                                                                            ),
                                                                            if (libraryModel.library[libraryModel.shelf[shelfNum]]![index]['status'] ==
                                                                                1)
                                                                              Positioned(
                                                                                top: 0,
                                                                                right: 8,
                                                                                child: Stack(
                                                                                  children: <Widget>[
                                                                                    Transform.translate(
                                                                                      offset: const Offset(0, 4),
                                                                                      child: ImageFiltered(
                                                                                        imageFilter: ImageFilter.blur(sigmaY: 4, sigmaX: 4),
                                                                                        child: Container(
                                                                                          decoration: BoxDecoration(
                                                                                            border: Border.all(
                                                                                              color: Colors.transparent,
                                                                                              width: 0,
                                                                                            ),
                                                                                          ),
                                                                                          child: const Opacity(
                                                                                            opacity: 0.5,
                                                                                            child: ColorFiltered(
                                                                                              colorFilter: ColorFilter.mode(Colors.black, BlendMode.srcATop),
                                                                                              child: BookmarkIcon(),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    const BookmarkIcon(),
                                                                                  ],
                                                                                ),
                                                                              ),
                                                                          ],
                                                                        ),
                                                                      );
                                                                    }),
                                                                    separatorBuilder: (context,
                                                                            index) =>
                                                                        const SizedBox(
                                                                            width:
                                                                                15),
                                                                    itemCount: _isLibraryEmpty
                                                                        ? 0
                                                                        : libraryModel
                                                                            .library[libraryModel.shelf[shelfNum]]!
                                                                            .length,
                                                                  ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                );
                              }(),
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.linear,
                            child: Container(
                              height: 192 + 30 + 13,
                              width: context.width,
                              color: lightGrayColor,
                            ),
                          ),
                        ],
                      ),
                      // 서재 하단 읽은 책 목록
                      Positioned(
                        bottom: 0,
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          alignment: Alignment.bottomCenter,
                          curve: Curves.linear,
                          child: Container(
                            height: 192 + 30 + 13,
                            width: context.width,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 4,
                                  offset: const Offset(0, -4),
                                  color: Colors.black.withOpacity(0.15),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.only(
                              left: 25,
                              right: 25,
                              top: 20,
                              bottom: 10,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(right: 12),
                                          child: Text(
                                            '읽은 책',
                                            style: TextStyle(
                                              color: darkPrimaryColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${libraryModel.finishedBooks.length}',
                                          style: TextStyle(
                                            color: AppController.to.themeColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                    TextActionButton(
                                      buttonText: () {
                                        late String _filterText;
                                        if (_.filterYear.value == 0) {
                                          _filterText = '전체';
                                        } else {
                                          _filterText = '${_.filterYear}년';
                                          if (_.filterMonth.value != 0) {
                                            _filterText += ' ${_.filterMonth}월';
                                          }
                                        }
                                        return _filterText;
                                      }(),
                                      icon: const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Icon(
                                          PhosphorIcons.caretDown,
                                          size: 18,
                                          color: darkPrimaryColor,
                                        ),
                                      ),
                                      isUnderlined: false,
                                      textColor: darkPrimaryColor,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                      onPressed: () =>
                                          _onReadBooksFilterPressed(context),
                                    ),
                                  ],
                                ),
                                () {
                                  if (_.finishedBookLoading.value) {
                                    return SizedBox(
                                      height: 124 + 20 + 13,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: AppController.to.themeColor,
                                        ),
                                      ),
                                    );
                                  } else {
                                    if (libraryModel.finishedBooks.isNotEmpty) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 20),
                                        child: SizedBox(
                                          width: context.width * 0.95,
                                          height: 124 + 13,
                                          child: () {
                                            List _opacity = [];

                                            return ListView.builder(
                                              scrollDirection: Axis.horizontal,
                                              shrinkWrap: true,
                                              itemCount: libraryModel
                                                  .finishedBooks.length,
                                              itemBuilder: ((context, index) {
                                                if (index > 0) {
                                                  List _randList =
                                                      bookOpacityList.toList()
                                                        ..remove(_opacity[
                                                            index - 1]);
                                                  _opacity.add(_randList[
                                                      Math.Random()
                                                          .nextInt(2)]);
                                                } else {
                                                  _opacity.add(bookOpacityList[
                                                      Math.Random()
                                                          .nextInt(2)]);
                                                }
                                                return BookVertical(
                                                  title: libraryModel
                                                          .finishedBooks[index]
                                                      ['title'],
                                                  opacity: _opacity[index],
                                                  height: 124,
                                                  complimented: libraryModel
                                                          .finishedBooks[index]
                                                      ['complimented'],
                                                  onTap: () {
                                                    BookDetailsController
                                                        .to.bookInfo
                                                        .clear();
                                                    BookDetailsController
                                                        .to.bookInfo
                                                        .addAll(libraryModel
                                                                .finishedBooks[
                                                            index]);
                                                    BookDetailsController.to
                                                        .bookInfo['status'] = 2;
                                                    BookDetailsController
                                                            .to.username.value =
                                                        libraryModel.username;
                                                    BookDetailsController
                                                        .to
                                                        .isbn
                                                        .value = libraryModel
                                                            .finishedBooks[
                                                        index]['isbn'];
                                                    BookDetailsController.to
                                                        .getBookDetails(
                                                            username:
                                                                libraryModel
                                                                    .username);
                                                    BookDetailsController
                                                        .to.self.value = false;
                                                    Get.toNamed('/details');
                                                  },
                                                );
                                              }),
                                            );
                                          }(),
                                        ),
                                      );
                                    } else {
                                      return const SizedBox(
                                        height: 124 + 20 + 13,
                                        child: Center(
                                          child: Text(
                                            '읽은 책이 없어요 🥲',
                                            style: TextStyle(
                                              color: grayColor,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                }(),
                                const Shelf(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 서재 상단 바
              Positioned(
                top: 0,
                child: SizedBox(
                  height: 56,
                  width: context.width,
                  child: Material(
                    color: Colors.white,
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(
                          left: 15, right: 15, bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: _onUserInfoTap,
                            child: Text.rich(
                              TextSpan(
                                text: libraryModel.username,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: darkPrimaryColor,
                                ),
                                children: const [
                                  TextSpan(
                                    text: ' 님의 서재',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: darkPrimaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (!loading)
                            libraryModel.following
                                ? ElevatedActionButton(
                                    width: 100,
                                    height: 30,
                                    backgroundColor: lightGrayColor,
                                    textStyle: const TextStyle(
                                      color: darkPrimaryColor,
                                      fontSize: 14,
                                    ),
                                    buttonText: '팔로우 취소',
                                    onPressed: _onUpdateFollowingPressed,
                                  )
                                : ElevatedActionButton(
                                    width: 80,
                                    height: 30,
                                    backgroundColor: darkPrimaryColor,
                                    textStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    buttonText: '팔로우',
                                    onPressed: _onUpdateFollowingPressed,
                                  ),
                          if (loading)
                            const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: darkPrimaryColor,
                                strokeWidth: 2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
