import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:emojis/emoji.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class EmojiBottomSheet extends GetView<BookDetailsController> {
  final Function(String) onEmojiPressed;
  const EmojiBottomSheet({
    Key? key,
    required this.onEmojiPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Map<EmojiGroup, List> emojis = {};

    for (EmojiGroup group in EmojiGroup.values) {
      emojis.addAll({
        group: Emoji.byGroup(group).toList(),
      });
    }

    return SizedBox(
      height: context.height * 0.45,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(10, 10, 10, context.mediaQueryPadding.bottom),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: darkPrimaryColor,
              ),
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
            ),
            TabBar(
              controller: controller.emojiTabController,
              isScrollable: true,
              indicatorColor: AppController.to.themeColor,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              physics: const ClampingScrollPhysics(),
              labelPadding: const EdgeInsets.symmetric(horizontal: 10),
              tabs: List.generate(emojis.length, (index) {
                return Text(
                  emojis.values.toList()[index][0].char,
                  style: const TextStyle(
                    fontSize: 26,
                  ),
                );
              }),
            ),
            const Divider(
              color: lightGrayColor,
              height: 1,
              thickness: 1,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TabBarView(
                  controller: controller.emojiTabController,
                  children: List.generate(
                    emojis.length,
                    (categoryIndex) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Center(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 6,
                            children: List.generate(
                                emojis.values.toList()[categoryIndex].length,
                                (index) {
                              return GestureDetector(
                                onTap: () {
                                  onEmojiPressed(emojis.values
                                      .toList()[categoryIndex][index]
                                      .char);
                                },
                                child: Text(
                                  emojis.values
                                      .toList()[categoryIndex][index]
                                      .char,
                                  style: const TextStyle(
                                    fontSize: 34,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void getEmojiBottomSheet({
  required Function(String) onEmojiPressed,
}) {
  Get.bottomSheet(
    EmojiBottomSheet(
      onEmojiPressed: onEmojiPressed,
    ),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
    ),
    backgroundColor: Colors.white,
  );
}
