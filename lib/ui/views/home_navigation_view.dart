import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/home_navigation_controller.dart';
import 'package:bookworm_friends/ui/pages/home_page.dart';
import 'package:bookworm_friends/ui/pages/search_book_page.dart';
import 'package:bookworm_friends/ui/widgets/common/home_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomeNavigationView extends GetView<HomeNavigationController> {
  HomeNavigationView({super.key});

  final List<Widget> _pages = <Widget>[
    const HomePage(),
    const SearchBookPage(),
    const Placeholder(),
  ];

  @override
  Widget build(BuildContext context) {
    Future<bool> onBackPressed() async {
      return await controller.onBackPressed();
    }

    return GetBuilder<HomeNavigationController>(
      builder: (_) {
        return WillPopScope(
          onWillPop: onBackPressed,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: _pages[_.currentIndex],
            ),
            bottomNavigationBar: HomeNavigationBar(
              currentIndex: _.currentIndex,
              onIconTap: _.onIconTap,
            ),
          ),
        );
      },
    );
  }
}
