import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class HomeHeader extends StatelessWidget implements PreferredSizeWidget {
  final Function() onSearchUserPressed;
  final Function() onMenuPressed;
  final LibraryMode libraryMode;
  const HomeHeader({
    Key? key,
    required this.onSearchUserPressed,
    required this.onMenuPressed,
    required this.libraryMode,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: false,
        elevation: 0,
        title: SizedBox(
          height: 56,
          width: context.width,
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  isScrollable: true,
                  physics: const ClampingScrollPhysics(),
                  controller: UserController.to.userTabController,
                  indicatorColor: Colors.transparent,
                  labelPadding: const EdgeInsets.only(right: 10),
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: MaterialStateProperty.resolveWith<Color?>(
                    (Set<MaterialState> states) {
                      return states.contains(MaterialState.focused)
                          ? null
                          : Colors.transparent;
                    },
                  ),
                  tabs: List.generate(
                    UserController.to.userFollowing.length + 1,
                    (index) {
                      if (index == 0) {
                        return Container(
                          width: 40,
                          height: 40,
                          decoration:
                              index == UserController.to.userTabIndex.value
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: lightGrayColor,
                                      border: Border.all(
                                        color: AppController.to.themeColor,
                                        width: 1.5,
                                      ),
                                    )
                                  : const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: lightGrayColor,
                                    ),
                          child: Center(
                            child: Text(
                              AuthController.to.userInfo.isEmpty
                                  ? '?'
                                  : AuthController.to.userInfo['emoji'],
                              style: const TextStyle(
                                color: darkPrimaryColor,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        );
                      } else {
                        return Container(
                          width: 40,
                          height: 40,
                          decoration:
                              index == UserController.to.userTabIndex.value
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: lightGrayColor,
                                      border: Border.all(
                                        color: AppController.to.themeColor,
                                        width: 1.5,
                                      ),
                                    )
                                  : const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: lightGrayColor,
                                    ),
                          child: Center(
                            child: Text(
                              UserController.to.userFollowing[index - 1]
                                  ['emoji'],
                              style: const TextStyle(
                                color: darkPrimaryColor,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
              // SizedBox(
              //   width: 40,
              //   height: 40,
              //   child: Material(
              //     type: MaterialType.circle,
              //     color: lightGrayColor,
              //     child: IconButton(
              //       onPressed: onSearchUserPressed,
              //       splashRadius: 20,
              //       icon: const Icon(
              //         PhosphorIcons.magnifyingGlassLight,
              //         size: 24,
              //         color: darkPrimaryColor,
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 15),
            child: SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                onPressed: onMenuPressed,
                splashRadius: 20,
                icon: const Icon(
                  PhosphorIcons.listLight,
                  color: darkPrimaryColor,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class LibraryHeader extends StatelessWidget {
  final Function() onEditPressed;
  final Function() onAddPressed;
  final LibraryMode libraryMode;
  final Function() onEditShelfPressed;
  final Function() onEditShelfCompletePressed;

  const LibraryHeader({
    Key? key,
    required this.onEditPressed,
    required this.onAddPressed,
    required this.libraryMode,
    required this.onEditShelfPressed,
    required this.onEditShelfCompletePressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      child: SizedBox(
        height: 56,
        child: () {
          if (libraryMode == LibraryMode.editLibrary) {
            return SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: TextActionButton(
                    buttonText: '선반 편집',
                    onPressed: onEditShelfPressed,
                    isUnderlined: false,
                  ),
                ),
              ),
            );
          } else if (libraryMode == LibraryMode.editShelf) {
            return SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: TextActionButton(
                    buttonText: '서재 편집',
                    onPressed: onEditShelfCompletePressed,
                    isUnderlined: false,
                  ),
                ),
              ),
            );
          } else {
            return Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.only(left: 15, right: 15, bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GetX<UserController>(builder: (_) {
                      return Text.rich(
                        TextSpan(
                          text: _.username.value,
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
                      );
                    }),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: IconButton(
                            onPressed: onEditPressed,
                            splashRadius: 20,
                            icon: const Icon(
                              PhosphorIcons.pencilSimpleLight,
                              size: 26,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: IconButton(
                            onPressed: onAddPressed,
                            splashRadius: 20,
                            icon: const Icon(
                              PhosphorIcons.plusLight,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }
        }(),
      ),
    );
  }
}
