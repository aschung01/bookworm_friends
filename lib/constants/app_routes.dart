import 'package:bookworm_friends/ui/pages/auth_page.dart';
import 'package:bookworm_friends/ui/pages/home_page.dart';
import 'package:bookworm_friends/ui/pages/loading_page.dart';
import 'package:bookworm_friends/ui/pages/search_book_page.dart';
import 'package:bookworm_friends/ui/pages/search_user_page.dart';
import 'package:bookworm_friends/ui/pages/settings_page.dart';
import 'package:bookworm_friends/ui/pages/splash_page.dart';
import 'package:bookworm_friends/ui/pages/user_library_page.dart';
import 'package:bookworm_friends/ui/views/book_details_tab_view.dart';
import 'package:get/get.dart';

class AppRoutes {
  AppRoutes._();
  static final routes = [
    GetPage(name: '/', page: () => const SplashPage()),
    GetPage(name: '/loading', page: () => const LoadingPage(), transition: Transition.cupertinoDialog),
    GetPage(
      name: '/auth',
      page: () => const AuthPage(),
      transition: Transition.topLevel,
    ),
    GetPage(
      name: '/home',
      page: () => const HomePage(),
      transition: Transition.topLevel,
    ),
    GetPage(
      name: '/search_users',
      page: () => const SearchUserPage(),
      transition: Transition.topLevel,
    ),
    GetPage(
      name: '/user_library',
      page: () => const UserLibraryPage(),
      transition: Transition.cupertinoDialog,
    ),
    GetPage(name: '/details', page: () => const BookDetailsTabView()),
    GetPage(
      name: '/search',
      page: () => const SearchBookPage(),
      transition: Transition.topLevel,
    ),
    GetPage(
      name: '/settings',
      page: () => const SettingsPage(),
      transition: Transition.cupertinoDialog,
      // transitionDuration: Duration(milliseconds: 300),
    ),
  ];
}
