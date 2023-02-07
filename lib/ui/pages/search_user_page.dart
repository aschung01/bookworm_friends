import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SearchUserPage extends GetView<UserController> {
  const SearchUserPage({Key? key}) : super(key: key);

  void _onSearchSubmitted(String val) {
    controller.searchUsers();
  }

  void _onBackPressed() {
    Get.back();
  }

  void _onUserTap(int index) async {
    controller.username.value = controller.searchResult[index]['username'];

    controller.loading.value = true;
    Get.toNamed('/user_library');
    controller.clearLibrary();
    await controller.getUserLibrary(searchPage: true);
    await controller.getUserFinishedBooks(searchPage: true);
    controller.loading.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<UserController>(
      builder: (_) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: SearchHeader(
            controller: controller.searchUserTextController,
            hintText: '닉네임으로 친구를 검색하세요',
            elevate: false,
            onFieldSubmitted: _onSearchSubmitted,
            onBackPressed: _onBackPressed,
          ),
          body: SafeArea(
            child: GetX<UserController>(
              builder: (_) {
                if (_.searchResult.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.only(top: context.height * 0.25),
                    child: SingleChildScrollView(
                      child: Center(
                        child: Column(
                          children: const [
                            Padding(
                              padding: EdgeInsets.only(bottom: 15),
                              child: SmileBookwormIcon(
                                width: 80,
                              ),
                            ),
                            Text(
                              '친구의 서재를 구경하고, \n서로 독서 자극을 주고받아요 🙌',
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
                } else {
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(30, 10, 30, 15),
                    physics: const ClampingScrollPhysics(),
                    itemBuilder: ((context, index) {
                      return SizedBox(
                        height: 56,
                        width: context.width - 60,
                        child: InkWell(
                          onTap: () => _onUserTap(index),
                          borderRadius: BorderRadius.circular(10),
                          splashColor: Colors.transparent,
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: lightGrayColor,
                                ),
                                child: Center(
                                  child: Text(
                                    _.searchResult[index]['emoji'],
                                    style: const TextStyle(
                                      color: darkPrimaryColor,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                _.searchResult[index]['username'],
                                style: const TextStyle(
                                  color: darkPrimaryColor,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    itemCount: _.searchResult.length,
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }
}
