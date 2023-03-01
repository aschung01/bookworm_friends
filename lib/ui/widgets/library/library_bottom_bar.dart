import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class LibraryBottomBar extends StatelessWidget {
  final Function(BuildContext) onReadBooksFilterPressed;
  const LibraryBottomBar({
    super.key,
    required this.onReadBooksFilterPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryController>(
      builder: (_) {
        return AnimatedContainer(
          duration: const Duration(
            milliseconds: 200,
          ),
          curve: Curves.linear,
          onEnd: () {
            _.updateBarOpened();
          },
          padding: const EdgeInsets.symmetric(
            horizontal: 15,
          ),
          width: _.libraryTab == LibraryTab.liked ? 200 : context.width - 30,
          height: _.libraryTab == LibraryTab.liked ? 40 : 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: _.libraryTab == LibraryTab.liked
                ? const BorderRadius.all(Radius.circular(20))
                : const BorderRadius.all(Radius.circular(10)),
            boxShadow: [
              BoxShadow(
                blurRadius: 8,
                offset: const Offset(0, 4),
                color: darkPrimaryColor.withOpacity(0.15),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment:
                (_.barOpened && _.libraryTab == LibraryTab.finished)
                    ? MainAxisAlignment.spaceBetween
                    : MainAxisAlignment.center,
            children: [
              if (_.barOpened && _.libraryTab == LibraryTab.finished)
                GetX<LibraryController>(
                  builder: (_) {
                    return SizedBox(
                      width: 100,
                      child: Text.rich(
                        TextSpan(
                          text: '${_.finishedLibrary.length}',
                          style: const TextStyle(
                            color: darkPrimaryColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          children: const [
                            TextSpan(
                              text: '권',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      _.updateLibraryTab(LibraryTab.liked);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: _.libraryTab == LibraryTab.liked
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: _.libraryTab == LibraryTab.liked
                            ? const BorderRadius.all(Radius.circular(20))
                            : const BorderRadius.all(Radius.circular(10)),
                      ),
                      child: Center(
                        child: Text(
                          '관심',
                          style: TextStyle(
                            color: _.libraryTab == LibraryTab.liked
                                ? darkPrimaryColor
                                : mainGrayColor,
                            fontSize: 16,
                            fontWeight: _.libraryTab == LibraryTab.liked
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(
                    color: lightGrayColor,
                    width: 24,
                    thickness: 2,
                    indent: 5,
                    endIndent: 5,
                  ),
                  GestureDetector(
                    onTap: () {
                      _.updateLibraryTab(LibraryTab.finished);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: _.libraryTab == LibraryTab.finished
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: _.libraryTab == LibraryTab.finished
                            ? const BorderRadius.all(Radius.circular(20))
                            : const BorderRadius.all(Radius.circular(10)),
                      ),
                      child: Center(
                        child: Text(
                          '읽음',
                          style: TextStyle(
                            color: _.libraryTab == LibraryTab.finished
                                ? darkPrimaryColor
                                : mainGrayColor,
                            fontSize: 16,
                            fontWeight: _.libraryTab == LibraryTab.finished
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_.barOpened && _.libraryTab == LibraryTab.finished)
                GetX<LibraryController>(
                  builder: (_) {
                    return TextActionButton(
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
                      onPressed: () => onReadBooksFilterPressed(context),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
