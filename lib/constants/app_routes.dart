import 'package:flutter/material.dart';
import 'package:bookworm_friends/ui/pages/auth_page.dart';
import 'package:bookworm_friends/ui/pages/home_page.dart';
import 'package:bookworm_friends/ui/pages/loading_page.dart';
import 'package:bookworm_friends/ui/pages/search_book_page.dart';
import 'package:bookworm_friends/ui/pages/search_user_page.dart';
import 'package:bookworm_friends/ui/pages/settings_page.dart';
import 'package:bookworm_friends/ui/pages/splash_page.dart';
import 'package:bookworm_friends/ui/pages/user_library_page.dart';
import 'package:bookworm_friends/ui/views/book_details_tab_view.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String loading = '/loading';
  static const String auth = '/auth';
  static const String home = '/home';
  static const String searchUsers = '/search_users';
  static const String userLibrary = '/user_library';
  static const String details = '/details';
  static const String search = '/search';
  static const String settings = '/settings';

  static Map<String, WidgetBuilder> get routes => {
        splash: (_) => const SplashPage(),
        loading: (_) => const LoadingPage(),
        auth: (_) => const AuthPage(),
        home: (_) => const HomePage(),
        searchUsers: (_) => const SearchUserPage(),
        userLibrary: (_) => const UserLibraryPage(),
        details: (_) => const BookDetailsTabView(),
        search: (_) => const SearchBookPage(),
        settings: (_) => const SettingsPage(),
      };
}
