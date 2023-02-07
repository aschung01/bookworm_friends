import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/settings_controller.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/loading_blocks.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FollowInfoBottomSheet extends GetView<SettingsController> {
  const FollowInfoBottomSheet({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: context.height * 0.6,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(10, 10, 10, context.mediaQueryPadding.bottom),
        child: GetX<SettingsController>(builder: (_) {
          return Column(
            mainAxisSize: MainAxisSize.min,
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
                tabs: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 8.0),
                          child: Text(
                            '팔로워',
                            style: TextStyle(
                              color: darkPrimaryColor,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          _.loading.value
                              ? ''
                              : _.followingInfo['followers'].length.toString(),
                          style: const TextStyle(
                            color: darkPrimaryColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Text(
                            '팔로잉',
                            style: TextStyle(
                              color: darkPrimaryColor,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          _.loading.value
                              ? ''
                              : _.followingInfo['following'].length.toString(),
                          style: const TextStyle(
                              color: darkPrimaryColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
                labelColor: darkPrimaryColor,
                labelStyle: const TextStyle(
                  color: darkPrimaryColor,
                  fontSize: 16,
                ),
                unselectedLabelStyle: const TextStyle(
                  color: grayColor,
                  fontSize: 16,
                ),
                controller: _.followingInfoTabController,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorColor: AppController.to.themeColor,
                splashFactory: NoSplash.splashFactory,
              ),
              const Divider(
                color: lightGrayColor,
                height: 1,
                thickness: 1,
              ),
              _.loading.value
                  ? Column(
                      children: [
                        const SizedBox(
                          height: 10,
                        ),
                        LoadingBlock(
                          width: context.width - 40,
                          height: 40,
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        LoadingBlock(
                          width: context.width - 40,
                          height: 40,
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        LoadingBlock(
                          width: context.width - 40,
                          height: 40,
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                      ],
                    )
                  : Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TabBarView(
                          controller: _.followingInfoTabController,
                          children: [
                            ListView.separated(
                              physics: const ClampingScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(20, 10, 20, 10),
                              itemBuilder: (context, index) {
                                return Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: lightGrayColor,
                                      ),
                                      margin: const EdgeInsets.only(right: 12),
                                      child: Center(
                                        child: Text(
                                          _.followingInfo['followers'][index]
                                              ['emoji'],
                                          style: const TextStyle(
                                            color: darkPrimaryColor,
                                            fontSize: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _.followingInfo['followers'][index]
                                          ['username'],
                                      style: const TextStyle(
                                        color: darkPrimaryColor,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                );
                              },
                              separatorBuilder: (context, index) =>
                                  const SizedBox(
                                height: 5,
                              ),
                              itemCount: _.followingInfo['followers'].length,
                            ),
                            ListView.separated(
                              physics: const ClampingScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(20, 10, 20, 10),
                              itemBuilder: (context, index) {
                                return Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: lightGrayColor,
                                      ),
                                      margin: const EdgeInsets.only(right: 12),
                                      child: Center(
                                        child: Text(
                                          _.followingInfo['following'][index]
                                              ['emoji'],
                                          style: const TextStyle(
                                            color: darkPrimaryColor,
                                            fontSize: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _.followingInfo['following'][index]
                                          ['username'],
                                      style: const TextStyle(
                                        color: darkPrimaryColor,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                );
                              },
                              separatorBuilder: (context, index) =>
                                  const SizedBox(
                                height: 5,
                              ),
                              itemCount: _.followingInfo['following'].length,
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          );
        }),
      ),
    );
  }
}

void getFollowInfoBottomSheet() {
  Get.bottomSheet(
    const FollowInfoBottomSheet(),
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
