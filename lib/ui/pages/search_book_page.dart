import 'dart:developer' as Log;
import 'dart:math';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/controllers/search_book_controller.dart';
import 'package:bookworm_friends/core/services/kakao_service.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_info_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/headers/header.dart';
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart';
import 'package:bookworm_friends/ui/widgets/shelf.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class SearchBookPage extends GetView<SearchBookController> {
  const SearchBookPage({Key? key}) : super(key: key);

  void _onSearchSubmitted(String val) {
    controller.searchBooks();
  }

  void _onBackPressed() {
    Get.back();
  }

  void _onSaveBookPressed() async {
    Get.back();
    await controller.addBookToLibrary();
    LibraryController.to.clearLibrary();
    LibraryController.to.getLibrary();
    LibraryController.to.getFinishedBooks();
    Get.until((route) => Get.currentRoute == '/home');
    controller.resetBookSave();
  }

  void _onBookTap(int index) {
    controller.infoViewPage.value = 0;
    controller.bookInfo.clear();
    controller.bookInfo.addAll(controller.searchResult[index]);
    getBookInfoBottomSheet(onSavePressed: _onSaveBookPressed);
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SearchBookController>(
      builder: (_) {
        return Scaffold(
          backgroundColor:
              _.searchResult.isEmpty ? Colors.white : lightGrayColor,
          appBar: SearchHeader(
            controller: controller.searchTextController,
            elevate: _.searchResult.isNotEmpty,
            onFieldSubmitted: _onSearchSubmitted,
            onBackPressed: _onBackPressed,
          ),
          body: SafeArea(
            child: GetX<SearchBookController>(builder: (_) {
              if (_.searchResult.isEmpty) {
                return Padding(
                  padding: EdgeInsets.only(top: context.height * 0.25),
                  child: SingleChildScrollView(
                    child: Center(
                      child: Column(
                        children: const [
                          Padding(
                            padding: EdgeInsets.only(bottom: 15),
                            child: Icon(
                              PhosphorIcons.booksThin,
                              size: 120,
                              color: grayColor,
                            ),
                          ),
                          Text(
                            '책 제목, 저자, 출판사 등으로\n검색이 가능해요 ☺️',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: grayColor,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              int _numBooksPerLine =
                  ((context.width * 1.6 - 80 + context.height * 0.03) /
                          (0.18 * context.height))
                      // ((context.width - 50 + context.height * 3 / 160) /
                      //         (context.height * 9 / 80))
                      .floor();
              // ( 0.15h / 1.6 )x + ( 0.15h / 1.6 ) * 0.2 * (x-1) <= w - 50
              // (0.15/1.6)h * 1.2x - (0.15/8)h <= w - 50
              // x <= (w - 50 + 3/160 h) / (9/80)h
              print(_numBooksPerLine);
              Log.log(_.searchResult.toList().toString());

              return ListView.separated(
                padding: const EdgeInsets.only(top: 20, bottom: 20),
                physics: const ClampingScrollPhysics(),
                itemBuilder: ((context, line) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 25),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            min(
                                        (_.searchResult.length -
                                            _numBooksPerLine * line),
                                        _numBooksPerLine) *
                                    2 -
                                1,
                            (index) => index % 2 == 0
                                ? BookWidget(
                                    imageUrl: _.searchResult[
                                        _numBooksPerLine * line +
                                            index ~/ 2]['thumbnail'],
                                    onTap: () => _onBookTap(
                                        _numBooksPerLine * line + index ~/ 2),
                                  )
                                : SizedBox(
                                    width: context.height * 0.15 / (5 * 1.6)),
                          ),
                        ),
                      ),
                      const Shelf(),
                    ],
                  );
                }),
                separatorBuilder: ((context, index) => const SizedBox(
                      height: 26,
                    )),
                itemCount: max(_.searchResult.length ~/ _numBooksPerLine, 1),
              );
              // return SingleChildScrollView(
              //   child: Stack(
              //     children: [
              //       Padding(
              //         padding: const EdgeInsets.fromLTRB(25, 20, 25, 20),
              //         child: Wrap(
              //           spacing: 16,
              //           runSpacing: 34,
              //           children: List.generate(
              //             _.searchResult.length,
              //             (index) => BookWidget(
              //               imageUrl: 'http://image.yes24.com/goods/109705390/XL',
              //             ),
              //           ),
              //         ),
              //       ),
              //       Column(
              //         children: List.generate(_.searchResult.length / , (index) => null),
              //       ),
              //     ],
              //   ),
              // );
            }),
          ),
        );
      },
    );
  }
}
