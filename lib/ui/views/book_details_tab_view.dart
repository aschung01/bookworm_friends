import 'dart:math';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/core/services/kakao_service.dart';
import 'package:bookworm_friends/helpers/utils.dart';
import 'package:bookworm_friends/ui/pages/book_info_tab_page.dart';
import 'package:bookworm_friends/ui/pages/book_memo_tab_page.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/write_memo_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/compliment_block.dart';
import 'package:bookworm_friends/ui/widgets/headers/header.dart';
import 'package:bookworm_friends/ui/widgets/loading_blocks.dart';
import 'package:bookworm_friends/ui/widgets/shelf.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class BookDetailsTabView extends GetView<BookDetailsController> {
  const BookDetailsTabView({Key? key}) : super(key: key);

  void _onBackPressed() {
    Get.back();
  }

  void _onSharePressed() {
    KakaoService.shareKakaoLink(controller.bookInfo['thumbnail'],
        controller.bookInfo['title'], controller.bookInfo['url']);
  }

  void _onDeleteBookPressed() {
    getDeleteBookBottomSheet(
      onDeletePressed: () async {
        Get.back();
        await LibraryController.to
            .deleteBook(BookDetailsController.to.bookInfo['isbn']);
        if (BookDetailsController.to.bookInfo['status'] != 2) {
          LibraryController.to.getLibrary();
        } else {
          LibraryController.to.getFinishedBooks();
        }
        Get.until((route) => Get.currentRoute == '/home');
      },
    );
  }

  void _onSaveStatusPressed() {
    Get.back();
    controller.updateBookStatus();
  }

  void _onEditStatusPressed() {
    if (controller.bookInfo['start_date'] != null) {
      controller.startReadDate.value =
          DateTime.parse(controller.bookInfo['start_date']);
    } else {
      controller.startReadDate.value = DateTime.now();
    }
    if (controller.bookInfo['finish_date'] != null) {
      controller.finishReadDate.value =
          DateTime.parse(controller.bookInfo['finish_date']);
    } else {
      controller.finishReadDate.value = DateTime.now();
    }
    controller.saveBookStatus.value = controller.bookInfo['status'];
    getBookStatusBottomSheet(onSavePressed: _onSaveStatusPressed);
  }

  void _onSaveMemoPressed() {
    Get.back();
    controller.postMemo();
  }

  void _onWriteMemoPressed() {
    controller.memoTextController.clear();
    getWriteMemoBottomSheet(onSavePressed: _onSaveMemoPressed);
  }

  void _onComplimentPressed() {
    getEmojiBottomSheet(onEmojiPressed: (String emoji) async {
      Get.back();
      await controller.postCompliment(emoji);
      controller.getBookCompliments(username: controller.username.value);
      UserController.to.getUserFinishedBooks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightGrayColor,
      appBar: Header(
        onPressed: _onBackPressed,
        actions: controller.self.value
            ? [
                IconButton(
                  onPressed: _onDeleteBookPressed,
                  splashRadius: 20,
                  icon: const Icon(
                    PhosphorIcons.trashLight,
                    color: darkPrimaryColor,
                    size: 26,
                  ),
                ),
                IconButton(
                  onPressed: _onEditStatusPressed,
                  splashRadius: 20,
                  icon: const Icon(
                    PhosphorIcons.pencilSimpleLight,
                    color: darkPrimaryColor,
                    size: 26,
                  ),
                ),
                IconButton(
                  onPressed: _onSharePressed,
                  splashRadius: 20,
                  icon: const Icon(
                    PhosphorIcons.shareNetworkLight,
                    color: darkPrimaryColor,
                    size: 26,
                  ),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        bottom: false,
        child: GetBuilder<BookDetailsController>(
          builder: (_) {
            return Column(
              children: [
                Expanded(
                  child: NestedScrollView(
                    physics: const ClampingScrollPhysics(),
                    headerSliverBuilder:
                        (BuildContext context, bool innerBoxIsScrolled) {
                      return <Widget>[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(
                                top: 20, left: 15, right: 15),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 20,
                                  ),
                                  child: IntrinsicHeight(
                                    child: GetX<BookDetailsController>(
                                        builder: (_) {
                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Hero(
                                            tag: _.bookInfo['isbn']
                                                .split(' ')[0],
                                            child: !_.bookInfo
                                                    .containsKey('thumbnail')
                                                ? LoadingBlock(
                                                    height: 200,
                                                    width: 200 / 1.6,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            0),
                                                  )
                                                : BookWidget(
                                                    height: 200,
                                                    imageUrl:
                                                        _.bookInfo['thumbnail'],
                                                  ),
                                          ),
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  if (!_.self.value)
                                                    () {
                                                      if (!_.loading.value) {
                                                        if (_.bookInfo[
                                                                'compliments']
                                                            .any((e) =>
                                                                e['username'] ==
                                                                AuthController
                                                                        .to
                                                                        .userInfo[
                                                                    'username'])) {
                                                          return ElevatedActionButton(
                                                            width: 96,
                                                            height: 36,
                                                            borderRadius: 5,
                                                            buttonText: '내 칭찬',
                                                            backgroundColor:
                                                                Colors.white,
                                                            textStyle:
                                                                TextStyle(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: AppController
                                                                  .to
                                                                  .themeColor,
                                                            ),
                                                            leading: Text(
                                                              _.bookInfo['compliments'].singleWhere((e) =>
                                                                  e['username'] ==
                                                                  AuthController
                                                                          .to
                                                                          .userInfo[
                                                                      'username'])['compliment'],
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 24,
                                                                color:
                                                                    darkPrimaryColor,
                                                              ),
                                                            ),
                                                            onPressed:
                                                                _onComplimentPressed,
                                                            overlayColor:
                                                                AppController.to
                                                                    .themeColor
                                                                    .withOpacity(
                                                                        0.2),
                                                          );
                                                        } else {
                                                          return ElevatedActionButton(
                                                            width: 120,
                                                            height: 36,
                                                            borderRadius: 5,
                                                            textStyle:
                                                                const TextStyle(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                            leading: Icon(
                                                              PhosphorIcons
                                                                  .confettiFill,
                                                              color: _.bookInfo[
                                                                          'status'] ==
                                                                      2
                                                                  ? Colors.white
                                                                  : grayColor,
                                                              size: 26,
                                                            ),
                                                            buttonText: '칭찬하기',
                                                            onPressed:
                                                                _onComplimentPressed,
                                                            activated: _.bookInfo[
                                                                    'status'] ==
                                                                2,
                                                            disabledStyleOutline:
                                                                true,
                                                          );
                                                        }
                                                      } else {
                                                        return SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child:
                                                              CircularProgressIndicator(
                                                            color: AppController
                                                                .to.themeColor,
                                                            strokeWidth: 3,
                                                          ),
                                                        );
                                                      }
                                                    }(),
                                                  if (!_.loading.value)
                                                    if (_
                                                        .bookInfo['compliments']
                                                        .isNotEmpty)
                                                      ComplimentBlock(
                                                          compliments: _
                                                                  .bookInfo[
                                                              'compliments'])
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  BookStatusBadge(
                                                      status:
                                                          _.bookInfo['status']),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 10),
                                                    child: ShelfLabel(
                                                      label: _.loading.value
                                                          ? ''
                                                          : _.bookInfo['shelf'],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: Shelf(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverOverlapAbsorber(
                          handle:
                              NestedScrollView.sliverOverlapAbsorberHandleFor(
                                  context),
                          sliver: SliverPersistentHeader(
                            pinned: true,
                            delegate: SliverAppBarDelegate(
                              PreferredSize(
                                preferredSize: _.bookInfo['status'] != 0
                                    ? const Size.fromHeight(
                                        130 + kTextTabBarHeight)
                                    : const Size.fromHeight(
                                        86 + kTextTabBarHeight),
                                child: Material(
                                  color: Colors.white,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      GetX<BookDetailsController>(
                                          builder: (__) {
                                        return SizedBox(
                                          height: _.bookInfo['status'] != 0
                                              ? 130
                                              : 86,
                                          width: context.width,
                                          child: DecoratedBox(
                                            decoration: const BoxDecoration(
                                              color: lightGrayColor,
                                              borderRadius: BorderRadius.only(
                                                bottomLeft: Radius.circular(30),
                                                bottomRight:
                                                    Radius.circular(30),
                                              ),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      30, 8, 30, 0),
                                              child: __.loading.value
                                                  ? Column(
                                                      children: [
                                                        const LoadingTitle(),
                                                        if (_.bookInfo[
                                                                'status'] !=
                                                            0)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                        .only(
                                                                    top: 16),
                                                            child: LoadingBlock(
                                                              width: context
                                                                      .width -
                                                                  60,
                                                              height: 30,
                                                            ),
                                                          ),
                                                      ],
                                                    )
                                                  : Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            SizedBox(
                                                              width: context
                                                                      .width -
                                                                  60,
                                                              height: 24,
                                                              child:
                                                                  SingleChildScrollView(
                                                                scrollDirection:
                                                                    Axis.horizontal,
                                                                physics:
                                                                    const ClampingScrollPhysics(),
                                                                child: Text(
                                                                  _.bookInfo[
                                                                          'title'] ??
                                                                      '',
                                                                  style:
                                                                      const TextStyle(
                                                                    color:
                                                                        darkPrimaryColor,
                                                                    fontSize:
                                                                        20,
                                                                    height: 1,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                          .only(
                                                                      top: 10),
                                                              child: SizedBox(
                                                                width: context
                                                                        .width -
                                                                    60,
                                                                height: 24,
                                                                child:
                                                                    SingleChildScrollView(
                                                                  scrollDirection:
                                                                      Axis.horizontal,
                                                                  physics:
                                                                      const ClampingScrollPhysics(),
                                                                  child: Text(
                                                                    () {
                                                                      String
                                                                          _authors =
                                                                          '';
                                                                      for (int i =
                                                                              0;
                                                                          i < _.bookInfo['authors'].length;
                                                                          i++) {
                                                                        _authors += _.bookInfo['authors'][i] +
                                                                            (_.bookInfo['authors'].length != i + 1
                                                                                ? ', '
                                                                                : '');
                                                                      }
                                                                      return _authors;
                                                                    }(),
                                                                    style:
                                                                        const TextStyle(
                                                                      fontSize:
                                                                          13,
                                                                      color:
                                                                          darkPrimaryColor,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            if (_.bookInfo[
                                                                    'status'] !=
                                                                0)
                                                              Expanded(
                                                                child:
                                                                    Container(
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: Colors
                                                                        .white,
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            10),
                                                                  ),
                                                                  width: context
                                                                          .width -
                                                                      60,
                                                                  // height: 36,

                                                                  padding:
                                                                      const EdgeInsets
                                                                          .symmetric(
                                                                    horizontal:
                                                                        10,
                                                                  ),
                                                                  margin: const EdgeInsets
                                                                          .only(
                                                                      top: 12,
                                                                      bottom:
                                                                          12),
                                                                  child: Row(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .spaceBetween,
                                                                    children: [
                                                                      Row(
                                                                        mainAxisSize:
                                                                            MainAxisSize.min,
                                                                        children: [
                                                                          const Text(
                                                                            '독서 기간',
                                                                            style:
                                                                                TextStyle(
                                                                              color: darkPrimaryColor,
                                                                              fontSize: 14,
                                                                              fontWeight: FontWeight.bold,
                                                                            ),
                                                                          ),
                                                                          Padding(
                                                                            padding:
                                                                                const EdgeInsets.only(left: 10),
                                                                            child:
                                                                                Text(
                                                                              " ${formatDateRawString(_.bookInfo['start_date'])} ~ ${_.bookInfo['finish_date'] == null ? '' : formatDateRawString(_.bookInfo['finish_date'])}",
                                                                              style: const TextStyle(
                                                                                color: darkPrimaryColor,
                                                                                fontSize: 14,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      Text(
                                                                        () {
                                                                          if (_.bookInfo['finish_date'] !=
                                                                              null) {
                                                                            return '${DateTime.parse(_.bookInfo['finish_date']).difference(DateTime.parse(_.bookInfo['start_date'])).inDays}일';
                                                                          } else {
                                                                            return '${DateTime.now().difference(DateTime.parse(_.bookInfo['start_date'])).inDays}일';
                                                                          }
                                                                        }(),
                                                                        textAlign:
                                                                            TextAlign.end,
                                                                        style:
                                                                            TextStyle(
                                                                          color: AppController
                                                                              .to
                                                                              .themeColor,
                                                                          fontSize:
                                                                              14,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                        // Row(
                                                        //   mainAxisAlignment:
                                                        //       MainAxisAlignment.end,
                                                        //   children: [
                                                        //     Padding(
                                                        //       padding: const EdgeInsets.only(
                                                        //           right: 10),
                                                        //       child: Text(
                                                        //         '평균 평점',
                                                        //         style: TextStyle(
                                                        //           fontSize: 13,
                                                        //           color: darkPrimaryColor,
                                                        //         ),
                                                        //       ),
                                                        //     ),
                                                        //     BookRating(
                                                        //       rating: 4,
                                                        //     ),
                                                        //   ],
                                                        // ),
                                                      ],
                                                    ),
                                            ),
                                          ),
                                        );
                                      }),
                                      TabBar(
                                        controller: _.tabController,
                                        indicatorWeight: 2,
                                        indicatorColor: darkPrimaryColor,
                                        indicatorSize:
                                            TabBarIndicatorSize.label,
                                        labelColor: darkPrimaryColor,
                                        unselectedLabelColor: darkPrimaryColor,
                                        labelStyle: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        unselectedLabelStyle: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                        ),
                                        tabs: const <Widget>[
                                          Tab(child: Text('책 정보')),
                                          Tab(child: Text('메모')),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ];
                    },
                    body: Builder(
                      builder: (context) {
                        return Stack(
                          children: [
                            DecoratedBox(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                              ),
                              child: CustomScrollView(
                                physics: const ClampingScrollPhysics(),
                                slivers: [
                                  SliverOverlapInjector(
                                    handle: NestedScrollView
                                        .sliverOverlapAbsorberHandleFor(
                                            context),
                                  ),
                                  SliverList(
                                    delegate: SliverChildListDelegate(
                                      [
                                        SizedBox(
                                          width: context.width,
                                          height: context.height,
                                          child: TabBarView(
                                            controller: _.tabController,
                                            children: const [
                                              BookInfoTabPage(),
                                              BookMemoTabPage(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_.self.value)
                              AnimatedBuilder(
                                  animation: _.tabController.animation!,
                                  builder: (context, widget) {
                                    double distanceToMemoTab =
                                        _.tabController.animation!.value;

                                    return Positioned(
                                      bottom: 20 + (1 - distanceToMemoTab) * 13,
                                      right: 20 + (1 - distanceToMemoTab) * 13,
                                      child: SizedBox(
                                        width: distanceToMemoTab * 60,
                                        height: distanceToMemoTab * 60,
                                        child: FloatingActionButton(
                                          onPressed: _onWriteMemoPressed,
                                          backgroundColor: backgroundColor,
                                          child: Icon(
                                            PhosphorIcons.pencilSimpleFill,
                                            color: AppController.to.themeColor,
                                            size: distanceToMemoTab * 26,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(
                  height: context.mediaQueryPadding.bottom,
                  width: context.width,
                  child: const Material(
                    color: Colors.white,
                  ),
                )
              ],
            );
          },
        ),
      ),
    );
  }
}

class SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  SliverAppBarDelegate(this.child);

  final PreferredSizeWidget child;

  @override
  double get minExtent => child.preferredSize.height;
  @override
  double get maxExtent => child.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
