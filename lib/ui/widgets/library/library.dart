import 'dart:math' as Math;
import 'dart:ui';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/controllers/search_book_controller.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_shelf_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/update_shelf_name_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/headers/home_header.dart';
import 'package:bookworm_friends/ui/widgets/library/library_bottom_bar.dart';
import 'package:bookworm_friends/ui/widgets/shelf.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class Library extends GetView<LibraryController> {
  const Library({
    Key? key,
  }) : super(key: key);

  void _onDeleteShelfPressed(String shelf) {
    getDeleteShelfBottomSheet(onDeletePressed: () async {
      Get.back();
      await controller.deleteShelf(shelf);
      LibraryController.to.getLibrary();
    });
  }

  void _onBookDeletePressed(String isbn) {
    getDeleteBookBottomSheet(onDeletePressed: () async {
      Get.back();
      await controller.deleteBook(isbn);
      controller.updateLibraryMode(LibraryMode.library);
      LibraryController.to.getLibrary();
    });
  }

  void _onUpdateShelfNamePressed(String shelf) {
    controller.shelfNameTextController.text = shelf;
    getAddOrUpdateShelfNameBottomSheet(
      onSavePressed: () {
        Get.back();
        controller.updateShelfName(shelf);
      },
    );
  }

  void _onSaveFilterDatePressed() {
    controller.filterYear.value = controller.pickerYear.value;
    controller.filterMonth.value = controller.pickerMonth.value;
    controller.getFinishedBooks();
    Get.back();
  }

  void _onReadBooksFilterPressed(BuildContext context) {
    controller.pickerYear.value = controller.filterYear.value;
    controller.pickerMonth.value = controller.filterMonth.value;
    getSelectDateBottomSheet(onSavePressed: _onSaveFilterDatePressed);
  }

  void _onAddShelfPressed() {
    controller.shelfNameTextController.clear();
    getAddOrUpdateShelfNameBottomSheet(
        onSavePressed: () {
          Get.back();
          controller.addShelf();
        },
        update: false);
  }

  void _onEditLibraryPressed() {
    controller.updateLibraryMode(LibraryMode.editLibrary);
  }

  void _onEditShelfPressed() {
    controller.updateLibraryMode(LibraryMode.editShelf);
  }

  void _onEditShelfCompletePressed() {
    controller.updateLibraryMode(LibraryMode.editLibrary);
  }

  void _onAddBookPressed() {
    SearchBookController.to.reset();
    Get.toNamed('/search');
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryController>(builder: (_) {
      return Stack(
        alignment: Alignment.topCenter,
        // fit: StackFit.loose,
        children: [
          Positioned.fill(
            top: 56,
            child: PageView(
              physics: const NeverScrollableScrollPhysics(),
              controller: _.libraryPageController,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
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
                        child: GetX<LibraryController>(
                          builder: (_) {
                            if (_.libraryMode == LibraryMode.library) {
                              bool _isLibraryEmpty = true;

                              _.library.forEach((shelf, books) {
                                if (books.isNotEmpty) {
                                  _isLibraryEmpty = false;
                                }
                              });

                              return SingleChildScrollView(
                                padding: const EdgeInsets.only(top: 16),
                                physics: const ClampingScrollPhysics(),
                                child: Column(
                                  children: List.generate(
                                    (_isLibraryEmpty && _.library.length == 1)
                                        ? 2
                                        : _.library.length,
                                    (shelf) {
                                      if (_isLibraryEmpty &&
                                          _.library.length == 1) {
                                        if (shelf == 1) {
                                          return Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                    top: 10, bottom: 20),
                                                child: SadCharacter(),
                                              ),
                                              const Text(
                                                '서재가 비었어요..',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: grayColor,
                                                ),
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: const [
                                                  Padding(
                                                    padding: EdgeInsets.only(
                                                        right: 5),
                                                    child: Icon(
                                                      PhosphorIcons.plusLight,
                                                      size: 24,
                                                      color: grayColor,
                                                    ),
                                                  ),
                                                  Text(
                                                    '를 눌러 책을 추가해 볼까요?',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: grayColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          );
                                        }
                                      }
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 26),
                                        child: Column(
                                          children: [
                                            SizedBox(
                                              height: context.height * 0.15,
                                              width: context.width * 0.95,
                                              child: Stack(
                                                alignment: Alignment.bottomLeft,
                                                children: [
                                                  Positioned(
                                                    top: 0,
                                                    child: SizedBox(
                                                      height:
                                                          context.height * 0.15,
                                                      width:
                                                          context.width * 0.95,
                                                      child: (_isLibraryEmpty &&
                                                              shelf == 0 &&
                                                              _.library.length >
                                                                  1)
                                                          ? Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                const Padding(
                                                                  padding: EdgeInsets
                                                                      .only(
                                                                          right:
                                                                              10),
                                                                  child:
                                                                      SadCharacter(
                                                                    height: 100,
                                                                  ),
                                                                ),
                                                                Column(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    const Text(
                                                                      '서재가 비었어요...',
                                                                      style:
                                                                          TextStyle(
                                                                        color:
                                                                            grayColor,
                                                                      ),
                                                                    ),
                                                                    Row(
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .min,
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .center,
                                                                      children: const [
                                                                        Padding(
                                                                          padding:
                                                                              EdgeInsets.only(right: 5),
                                                                          child:
                                                                              Icon(
                                                                            PhosphorIcons.plusLight,
                                                                            size:
                                                                                24,
                                                                            color:
                                                                                grayColor,
                                                                          ),
                                                                        ),
                                                                        Text(
                                                                          '를 눌러 책을 추가해 볼까요?',
                                                                          style:
                                                                              TextStyle(
                                                                            fontSize:
                                                                                14,
                                                                            color:
                                                                                grayColor,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            )
                                                          : ListView.separated(
                                                              scrollDirection:
                                                                  Axis.horizontal,
                                                              physics:
                                                                  const ClampingScrollPhysics(),
                                                              shrinkWrap: true,
                                                              padding:
                                                                  const EdgeInsets
                                                                          .only(
                                                                      left: 15,
                                                                      right:
                                                                          15),
                                                              itemBuilder:
                                                                  ((context,
                                                                      index) {
                                                                return Hero(
                                                                  tag: _
                                                                      .library[_
                                                                          .shelf[
                                                                      shelf]]![index]['isbn'],
                                                                  child: Stack(
                                                                    children: [
                                                                      BookWidget(
                                                                        imageUrl: _
                                                                            .library[_
                                                                                .shelf[
                                                                            shelf]]![index]['thumbnail'],
                                                                        onTap:
                                                                            () {
                                                                          BookDetailsController
                                                                              .to
                                                                              .bookInfo
                                                                              .clear();
                                                                          BookDetailsController
                                                                              .to
                                                                              .bookInfo
                                                                              .addAll(_.library[_.shelf[shelf]]![index]);
                                                                          BookDetailsController
                                                                              .to
                                                                              .shelf
                                                                              .value = _.shelf[shelf];
                                                                          BookDetailsController
                                                                              .to
                                                                              .getBookDetails();
                                                                          BookDetailsController
                                                                              .to
                                                                              .tabController
                                                                              .index = 0;
                                                                          BookDetailsController
                                                                              .to
                                                                              .self
                                                                              .value = true;
                                                                          Get.toNamed(
                                                                              '/details');
                                                                        },
                                                                        onLongPress:
                                                                            _onEditLibraryPressed,
                                                                      ),
                                                                      if (_.library[_.shelf[shelf]]![index]
                                                                              [
                                                                              'status'] ==
                                                                          1)
                                                                        Positioned(
                                                                          top:
                                                                              0,
                                                                          right:
                                                                              8,
                                                                          child:
                                                                              Stack(
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
                                                                  : _
                                                                      .library[_
                                                                              .shelf[
                                                                          shelf]]!
                                                                      .length,
                                                            ),
                                                    ),
                                                  ),
                                                  if (_.shelf.isNotEmpty)
                                                    Positioned(
                                                      bottom: 0,
                                                      right: 0,
                                                      child: ShelfLabel(
                                                        label: _.shelf[shelf],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const Shelf(),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            } else if (_.libraryMode ==
                                LibraryMode.editLibrary) {
                              return SingleChildScrollView(
                                padding: const EdgeInsets.only(top: 16),
                                physics: const ClampingScrollPhysics(),
                                child: Column(
                                  children: List.generate(
                                    _.library.length,
                                    (shelf) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 26),
                                        child: Column(
                                          children: [
                                            SizedBox(
                                              height: context.height * 0.15,
                                              width: context.width * 0.95,
                                              child: Stack(
                                                alignment: Alignment.topLeft,
                                                children: [
                                                  Positioned(
                                                    top: 0,
                                                    child: SizedBox(
                                                      height:
                                                          context.height * 0.15,
                                                      width:
                                                          context.width * 0.95,
                                                      child: ReorderableListView
                                                          .builder(
                                                        clipBehavior: Clip.none,
                                                        scrollDirection:
                                                            Axis.horizontal,
                                                        physics:
                                                            const ClampingScrollPhysics(),
                                                        shrinkWrap: true,
                                                        padding:
                                                            const EdgeInsets
                                                                    .only(
                                                                left: 15,
                                                                right: 15),
                                                        onReorder: (oldIndex,
                                                            newIndex) {
                                                          List _bookList = _
                                                              .library[_.shelf[
                                                                  shelf]]!
                                                              .toList();
                                                          var book = _bookList[
                                                              oldIndex];
                                                          _bookList.removeAt(
                                                              oldIndex);
                                                          if (oldIndex >
                                                              newIndex) {
                                                            _bookList.insert(
                                                                newIndex, book);
                                                          } else {
                                                            _bookList.insert(
                                                                newIndex - 1,
                                                                book);
                                                          }
                                                          _.library[_.shelf[
                                                                  shelf]] =
                                                              _bookList;
                                                        },
                                                        itemBuilder:
                                                            ((context, index) {
                                                          return Container(
                                                            key: Key(_.library[_
                                                                        .shelf[
                                                                    shelf]]![
                                                                index]['isbn']),
                                                            margin:
                                                                const EdgeInsets
                                                                        .symmetric(
                                                                    horizontal:
                                                                        7.5),
                                                            child: Draggable(
                                                              feedback:
                                                                  BookWidget(
                                                                imageUrl: _
                                                                        .library[_
                                                                            .shelf[
                                                                        shelf]]![index]
                                                                    [
                                                                    'thumbnail'],
                                                                editMode: true,
                                                              ),
                                                              affinity:
                                                                  Axis.vertical,
                                                              childWhenDragging:
                                                                  const SizedBox(
                                                                      width:
                                                                          50),
                                                              data: _.library[_
                                                                          .shelf[
                                                                      shelf]]![
                                                                  index],
                                                              onDragStarted:
                                                                  () {
                                                                controller
                                                                        .dragging
                                                                        .value =
                                                                    true;
                                                                controller
                                                                    .emptiedShelf
                                                                    .value = shelf;
                                                              },
                                                              onDragEnd:
                                                                  (details) {
                                                                controller
                                                                        .dragging
                                                                        .value =
                                                                    false;
                                                                controller
                                                                    .emptiedShelf
                                                                    .value = -1;
                                                              },
                                                              child: Hero(
                                                                tag: _.library[_
                                                                            .shelf[
                                                                        shelf]]![
                                                                    index]['isbn'],
                                                                child:
                                                                    BookWidget(
                                                                  imageUrl: _
                                                                      .library[_
                                                                          .shelf[
                                                                      shelf]]![index]['thumbnail'],
                                                                  onTap: () {
                                                                    _onBookDeletePressed(_
                                                                        .library[_
                                                                            .shelf[
                                                                        shelf]]![index]['isbn']);
                                                                  },
                                                                  editMode: _
                                                                          .libraryMode ==
                                                                      LibraryMode
                                                                          .editLibrary,
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                          // : SizedBox(
                                                          //     key: Key(
                                                          //       '$shelf$index',
                                                          //     ),
                                                          //     width: 15);
                                                        }),
                                                        itemCount: Math.max(
                                                            (_
                                                                .library[
                                                                    _.shelf[
                                                                        shelf]]!
                                                                .length),
                                                            0),
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    bottom: 0,
                                                    right: 0,
                                                    child: ShelfLabel(
                                                      label: _.shelf[shelf],
                                                    ),
                                                  ),
                                                  if (_.dragging.value &&
                                                      shelf !=
                                                          _.emptiedShelf.value)
                                                    Positioned(
                                                      bottom: 40,
                                                      right: 30,
                                                      left: 30,
                                                      child: DragTarget(
                                                        builder: ((context,
                                                            candidateData,
                                                            rejectedData) {
                                                          return Container(
                                                            width:
                                                                context.width -
                                                                    60,
                                                            height:
                                                                context.height *
                                                                    0.08,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                      0.8),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          5),
                                                            ),
                                                            alignment: Alignment
                                                                .center,
                                                            child: Text(
                                                              "[${_.shelf[shelf]}] 로 이동",
                                                              style:
                                                                  const TextStyle(
                                                                color:
                                                                    darkPrimaryColor,
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          );
                                                        }),
                                                        onAcceptWithDetails:
                                                            (details) {
                                                          _.library[_
                                                                  .shelf[shelf]]
                                                              ?.add(
                                                                  details.data);
                                                          _.library[_.shelf[_
                                                                  .emptiedShelf
                                                                  .value]]
                                                              ?.remove(
                                                                  details.data);
                                                          details.data;
                                                        },
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const Shelf(),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            } else {
                              return Column(
                                children: [
                                  if (_.shelf.isNotEmpty)
                                    ReorderableListView.builder(
                                      shrinkWrap: true,
                                      physics: const ClampingScrollPhysics(),
                                      padding: EdgeInsets.only(
                                          top: 16,
                                          left: context.width * 0.025,
                                          right: context.width * 0.025),
                                      itemCount: _.shelf.length,
                                      onReorder: (oldIndex, newIndex) {
                                        var _shelf = _.shelf[oldIndex];
                                        _.shelf.removeAt(oldIndex);
                                        if (oldIndex > newIndex) {
                                          _.shelf.insert(newIndex, _shelf);
                                        } else {
                                          _.shelf.insert(newIndex - 1, _shelf);
                                        }
                                      },
                                      proxyDecorator:
                                          (child, index, animation) {
                                        return Material(
                                          type: MaterialType.transparency,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: lightGrayColor,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.3),
                                                  offset: const Offset(0, 3),
                                                  blurRadius: 3,
                                                ),
                                              ],
                                            ),
                                            child: child,
                                          ),
                                        );
                                      },
                                      itemBuilder: (context, shelf) {
                                        return Padding(
                                          key: Key(_.shelf[shelf]),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 7.5),
                                          child: Row(
                                            children: [
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      ShelfLabel(
                                                        label: _.shelf[shelf],
                                                      ),
                                                    ],
                                                  ),
                                                  Shelf(
                                                    width: context.width * 0.7,
                                                  ),
                                                ],
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 10),
                                                child: SizedBox(
                                                  width: 40,
                                                  height: 40,
                                                  child: Material(
                                                    type: MaterialType
                                                        .transparency,
                                                    child: IconButton(
                                                      onPressed: () =>
                                                          _onUpdateShelfNamePressed(
                                                              _.shelf[shelf]),
                                                      splashRadius: 20,
                                                      icon: const Icon(
                                                        PhosphorIcons
                                                            .pencilSimpleLight,
                                                        size: 20,
                                                        color: darkPrimaryColor,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 40,
                                                height: 40,
                                                child: Material(
                                                  type:
                                                      MaterialType.transparency,
                                                  child: IconButton(
                                                    onPressed: () =>
                                                        _onDeleteShelfPressed(
                                                            _.shelf[shelf]),
                                                    splashRadius: 20,
                                                    icon: const Icon(
                                                      PhosphorIcons.trashLight,
                                                      size: 20,
                                                      color: softRedColor,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 20),
                                    child: ElevatedActionButton(
                                      buttonText: '선반 추가',
                                      leading: const Icon(
                                        PhosphorIcons.plusLight,
                                        size: 20,
                                        color: darkPrimaryColor,
                                      ),
                                      textStyle: const TextStyle(
                                        color: darkPrimaryColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      onPressed: _onAddShelfPressed,
                                      backgroundColor: Colors.transparent,
                                      overlayColor: Colors.white,
                                      width: 140,
                                      height: 40,
                                    ),
                                  ),
                                ],
                              );
                            }
                          },
                        ),
                      ),
                      // AnimatedSize(
                      //   duration: const Duration(milliseconds: 300),
                      //   curve: Curves.linear,
                      //   child: Container(
                      //     height: _.libraryMode.value == LibraryMode.library
                      //         ? 192 + 30 + 13
                      //         : 0,
                      //     width: context.width,
                      //     color: lightGrayColor,
                      //   ),
                      // ),
                    ),
                  ],
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
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
                        child: GetX<LibraryController>(
                          builder: (_) {
                            bool isFinishedLibraryEmpty = true;
                            print(_.finishedLibrary.length);
                            _.finishedLibrary.forEach((shelf, books) {
                              if (books.isNotEmpty) {
                                isFinishedLibraryEmpty = false;
                              }
                            });
                            return SingleChildScrollView(
                              padding: const EdgeInsets.only(top: 16),
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                children: _.finishedLibrary.keys.map((shelf) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 26),
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          height: context.height * 0.15,
                                          width: context.width * 0.95,
                                          child: Stack(
                                            alignment: Alignment.bottomLeft,
                                            children: [
                                              Positioned(
                                                top: 0,
                                                child: SizedBox(
                                                  height: context.height * 0.15,
                                                  width: context.width * 0.95,
                                                  child: ListView.separated(
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    physics:
                                                        const ClampingScrollPhysics(),
                                                    shrinkWrap: true,
                                                    padding:
                                                        const EdgeInsets.only(
                                                            left: 15,
                                                            right: 15),
                                                    itemBuilder:
                                                        (context, index) {
                                                      return Hero(
                                                        tag: _
                                                            .finishedLibrary[
                                                                shelf]![index]
                                                            ['isbn'],
                                                        child: BookWidget(
                                                          imageUrl:
                                                              _.finishedLibrary[
                                                                          shelf]![
                                                                      index]
                                                                  ['thumbnail'],
                                                          onTap: () {},
                                                        ),
                                                      );
                                                    },
                                                    separatorBuilder:
                                                        (context, index) =>
                                                            const SizedBox(
                                                                width: 15),
                                                    itemCount: _
                                                        .finishedLibrary[shelf]!
                                                        .length,
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                bottom: 0,
                                                right: 0,
                                                child: ShelfLabel(
                                                  label: shelf,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Shelf(),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 서재 하단 읽은 책 목록
          // Positioned(
          //   bottom: 0,
          //   child: AnimatedSize(
          //     duration: const Duration(milliseconds: 300),
          //     alignment: Alignment.bottomCenter,
          //     curve: Curves.linear,
          //     child: Container(
          //       height: _.libraryMode.value == LibraryMode.library
          //           ? 192 + 30 + 13
          //           : 0,
          //       width: context.width,
          //       decoration: BoxDecoration(
          //         color: Colors.white,
          //         boxShadow: [
          //           BoxShadow(
          //             blurRadius: 4,
          //             offset: const Offset(0, -4),
          //             color: Colors.black.withOpacity(0.15),
          //           ),
          //         ],
          //       ),
          //       padding: const EdgeInsets.only(
          //         left: 25,
          //         right: 25,
          //         top: 20,
          //         bottom: 10,
          //       ),
          //       child: Column(
          //         children: [
          //           Row(
          //             mainAxisAlignment:
          //                 MainAxisAlignment.spaceBetween,
          //             children: [
          //               Row(
          //                 mainAxisAlignment:
          //                     MainAxisAlignment.start,
          //                 children: [
          //                   const Padding(
          //                     padding: EdgeInsets.only(right: 12),
          //                     child: Text(
          //                       '읽은 책',
          //                       style: TextStyle(
          //                         color: darkPrimaryColor,
          //                         fontWeight: FontWeight.bold,
          //                         fontSize: 18,
          //                       ),
          //                     ),
          //                   ),
          //                   Text(
          //                     '${_.finishedBooks.length}',
          //                     style: TextStyle(
          //                       color: AppController.to.themeColor,
          //                       fontWeight: FontWeight.bold,
          //                       fontSize: 18,
          //                     ),
          //                   ),
          //                 ],
          //               ),
          //               TextActionButton(
          //                 buttonText: () {
          //                   late String _filterText;
          //                   if (_.filterYear.value == 0) {
          //                     _filterText = '전체';
          //                   } else {
          //                     _filterText = '${_.filterYear}년';
          //                     if (_.filterMonth.value != 0) {
          //                       _filterText += ' ${_.filterMonth}월';
          //                     }
          //                   }
          //                   return _filterText;
          //                 }(),
          //                 icon: const Padding(
          //                   padding: EdgeInsets.only(left: 6),
          //                   child: Icon(
          //                     PhosphorIcons.caretDown,
          //                     size: 18,
          //                     color: darkPrimaryColor,
          //                   ),
          //                 ),
          //                 isUnderlined: false,
          //                 textColor: darkPrimaryColor,
          //                 fontWeight: FontWeight.w500,
          //                 fontSize: 14,
          //                 onPressed: () =>
          //                     _onReadBooksFilterPressed(context),
          //               ),
          //             ],
          //           ),
          //           () {
          //             if (AuthController.to.isAuthenticated.value &&
          //                 _.finishedBookLoading.value) {
          //               return SizedBox(
          //                 height: 124 + 20 + 13,
          //                 child: Center(
          //                   child: CircularProgressIndicator(
          //                     color: AppController.to.themeColor,
          //                   ),
          //                 ),
          //               );
          //             } else {
          //               if (_.finishedBooks.isNotEmpty) {
          //                 return Padding(
          //                   padding: const EdgeInsets.only(top: 20),
          //                   child: SizedBox(
          //                     width: context.width * 0.95,
          //                     height: _.libraryMode.value ==
          //                             LibraryMode.editLibrary
          //                         ? 0
          //                         : 124 + 13,
          //                     child: () {
          //                       List _opacity = [];

          //                       return ListView.builder(
          //                         scrollDirection: Axis.horizontal,
          //                         shrinkWrap: true,
          //                         itemCount: _.finishedBooks.length,
          //                         itemBuilder: ((context, index) {
          //                           if (index > 0) {
          //                             List _randList =
          //                                 bookOpacityList.toList()
          //                                   ..remove(_opacity[
          //                                       index - 1]);
          //                             _opacity.add(_randList[
          //                                 Math.Random()
          //                                     .nextInt(2)]);
          //                           } else {
          //                             _opacity.add(bookOpacityList[
          //                                 Math.Random()
          //                                     .nextInt(2)]);
          //                           }
          //                           return BookVertical(
          //                             title: _.finishedBooks[index]
          //                                 ['title'],
          //                             opacity: _opacity[index],
          //                             height: _.libraryMode.value ==
          //                                     LibraryMode
          //                                         .editLibrary
          //                                 ? 0
          //                                 : 124,
          //                             complimented:
          //                                 _.finishedBooks[index]
          //                                     ['complimented'],
          //                             onTap: () {
          //                               BookDetailsController
          //                                   .to.bookInfo
          //                                   .clear();
          //                               BookDetailsController
          //                                   .to.bookInfo
          //                                   .addAll(_.finishedBooks[
          //                                       index]);
          //                               BookDetailsController.to
          //                                   .bookInfo['status'] = 2;
          //                               BookDetailsController.to
          //                                   .getBookDetails();
          //                               BookDetailsController
          //                                   .to.self.value = true;
          //                               Get.toNamed('/details');
          //                             },
          //                           );
          //                         }),
          //                       );
          //                     }(),
          //                   ),
          //                 );
          //               } else {
          //                 return const SizedBox(
          //                   height: 124 + 20 + 13,
          //                   child: Center(
          //                     child: Text(
          //                       '읽은 책이 없어요 🥲',
          //                       style: TextStyle(
          //                         color: grayColor,
          //                         fontSize: 14,
          //                       ),
          //                     ),
          //                   ),
          //                 );
          //               }
          //             }
          //           }(),
          //           const Shelf(),
          //         ],
          //       ),
          //     ),
          //   ),
          // ),
          Positioned(
            bottom: 16,
            child: LibraryBottomBar(
              onReadBooksFilterPressed: _onReadBooksFilterPressed,
            ),
          ),
          LibraryHeader(
            onEditPressed: _onEditLibraryPressed,
            onAddPressed: _onAddBookPressed,
            onEditShelfPressed: _onEditShelfPressed,
            onEditShelfCompletePressed: _onEditShelfCompletePressed,
            libraryMode: _.libraryMode,
          ),
          // GetX<LibraryController>(builder: (_) {
          //   return LibraryHeader(
          //     onEditPressed: _onEditLibraryPressed,
          //     onAddPressed: _onAddBookPressed,
          //     onEditShelfPressed: _onEditShelfPressed,
          //     onEditShelfCompletePressed: _onEditShelfCompletePressed,
          //     libraryMode: _.libraryMode,
          //   );
          // }),
        ],
      );
    });
  }
}
