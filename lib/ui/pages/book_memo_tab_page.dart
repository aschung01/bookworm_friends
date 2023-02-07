import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/core/services/library_api_service.dart';
import 'package:bookworm_friends/helpers/utils.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/memo_menu_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/write_memo_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/loading_blocks.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class BookMemoTabPage extends GetView<BookDetailsController> {
  const BookMemoTabPage({Key? key}) : super(key: key);

  void _onDeleteMemoPressed(int index) async {
    Get.back();
    await controller.deleteMemo(index);
    Map _libraryBookDetails =
        await LibraryApiService.getBookDetails(controller.bookInfo['isbn']);
    controller.bookInfo.addAll(_libraryBookDetails);
  }

  void _onSaveMemoUpdatePressed(int index) async {
    Get.back();
    await controller.updateMemo(index);
    Map _libraryBookDetails =
        await LibraryApiService.getBookDetails(controller.bookInfo['isbn']);
    controller.bookInfo.addAll(_libraryBookDetails);
  }

  void _onUpdateMemoPressed(int index) {
    Get.back();
    controller.memoTextController.text =
        controller.bookInfo['memos'][index]['content'];
    getWriteMemoBottomSheet(
      onSavePressed: () => _onSaveMemoUpdatePressed(index),
    );
  }

  void _onMemoTap(int index) {
    getMemoMenuBottomSheet(
      memo: controller.bookInfo['memos'][index]['content'],
      onDeletePressed: () => _onDeleteMemoPressed(index),
      onUpdatePressed: () => _onUpdateMemoPressed(index),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: GetX<BookDetailsController>(
        builder: (_) {
          if (_.loading.value) {
            return Column(
              children: List.generate(
                3 * 2 - 1,
                (index) => index % 2 == 0
                    ? LoadingBlock(width: context.width - 60, height: 40)
                    : const SizedBox(height: 20),
              ),
            );
          } else {
            if (_.bookInfo['memos'].isEmpty) {
              return const Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 100),
                  child: Text(
                    '메모가 없습니다',
                    style: TextStyle(
                      color: darkPrimaryColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            } else {
              return Column(
                children: List.generate(
                  _.bookInfo['memos'].length,
                  (index) => MemoWidget(
                    data: _.bookInfo['memos'][index],
                    onTap: _.self.value ? () => _onMemoTap(index) : null,
                  ),
                ),
              );
            }
          }
        },
      ),
    );
  }
}

class MemoWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Function()? onTap;
  const MemoWidget({
    Key? key,
    required this.data,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.width - 60,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 5),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 10, 10, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: context.width - 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDateRawString(data['created_at']),
                        style: const TextStyle(
                          color: darkPrimaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            data['content'],
                            style: const TextStyle(
                              color: darkPrimaryColor,
                              fontSize: 13,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  PhosphorIcons.dotsThreeVertical,
                  size: 24,
                  color: darkPrimaryColor,
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
