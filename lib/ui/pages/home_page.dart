import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/core/models/user_library_model.dart';
import 'package:bookworm_friends/ui/widgets/headers/home_header.dart';
import 'package:bookworm_friends/ui/widgets/library/library.dart';
import 'package:bookworm_friends/ui/widgets/library/user_library.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomePage extends GetView<LibraryController> {
  const HomePage({Key? key}) : super(key: key);

  void _onSearchUserPressed() {
    UserController.to.searchResult.clear();
    UserController.to.searchUserTextController.clear();
    Get.toNamed('/search_users');
  }

  void _onMenuPressed() {
    Get.toNamed('/settings');
  }

  List<Widget> createTabViews(double height) {
    List<Widget> _tabViews = [];
    for (int i = 0; i < UserController.to.userFollowing.length + 1; i++) {
      if (i == 0) {
        _tabViews.add(
          Library(
            height: height,
          ),
        );
      } else {
        _tabViews.add(
          UserLibrary(
            height: height,
            libraryModel: UserController.to.usersLibrary[i - 1] ??
                UserLibraryModel(
                  username:
                      UserController.to.userFollowing[i - 1]['username'] ?? '?',
                  library: {},
                  shelf: [],
                  finishedBooks: [],
                  following: true,
                  filterYear: UserController.to.filterYear.value,
                ),
          ),
        );
      }
    }
    return _tabViews;
  }

  void rebuildAllChildren(BuildContext context) {
    print('rebuild');
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
    UserController.to.rebuild = false;
  }

  @override
  Widget build(BuildContext context) {
    Future.delayed(Duration.zero, () {
      AuthController.to.getUserInfoIfEmpty();
      if (AuthController.to.isAuthenticated.value) {
        controller.getLibrary();
        if (controller.finishedBooks.isEmpty) {
          controller.getFinishedBooks();
        }
        if (UserController.to.userFollowing.isEmpty) {
          UserController.to.getUserFollowing();
        }
      }
    });

    return GestureDetector(
      onTap: () {
        if (controller.libraryMode.value != LibraryMode.library) {
          if (controller.libraryMode.value == LibraryMode.editLibrary) {
            controller.updateLibrary();
          } else if (controller.libraryMode.value == LibraryMode.editShelf) {
            controller.updateShelfOrder();
          }
          controller.libraryMode.value = LibraryMode.library;
        }
      },
      child: GetBuilder<UserController>(
        builder: (__) {
          if (__.rebuild) {
            Future.delayed(Duration.zero, () {
              rebuildAllChildren(context);
            });
          }
          return Scaffold(
            appBar: HomeHeader(
              onSearchUserPressed: _onSearchUserPressed,
              onMenuPressed: _onMenuPressed,
              libraryMode: controller.libraryMode,
            ),
            body: GetX<UserController>(
              builder: (_) {
                double _height = context.height -
                    (112 +
                        context.mediaQueryPadding.bottom +
                        context.mediaQueryPadding.top);
                return TabBarView(
                  controller: __.userTabController,
                  physics: const ClampingScrollPhysics(),
                  children: createTabViews(_height),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
