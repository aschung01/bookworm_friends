import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/core/models/user_library_model.dart';
import 'package:bookworm_friends/ui/widgets/headers/header.dart';
import 'package:bookworm_friends/ui/widgets/library/library.dart';
import 'package:bookworm_friends/ui/widgets/library/user_library.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserLibraryPage extends GetView<UserController> {
  const UserLibraryPage({Key? key}) : super(key: key);

  void _onBackPressed() {
    Get.back();
  }

  void _onFollowPressed() {
    controller.updateUserFollowing();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: Header(onPressed: _onBackPressed),
      body: GetX<UserController>(
        builder: (_) {
          return UserLibrary(
            height: context.height -
                (112 +
                    context.mediaQueryPadding.bottom +
                    context.mediaQueryPadding.top),
            loading: _.loading.value,
            libraryModel: UserLibraryModel(
              username: _.username.value,
              library: _.library,
              shelf: _.shelf,
              finishedBooks: _.finishedBooks,
              following: _.following.value,
              filterYear: _.filterYear.value,
              filterMonth: _.filterMonth.value,
            ),
          );
        },
      ),
    );
  }
}
