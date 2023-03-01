import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/book_details_controller.dart';
import 'package:bookworm_friends/core/controllers/deep_link_controller.dart';
import 'package:bookworm_friends/core/controllers/home_navigation_controller.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/controllers/search_book_controller.dart';
import 'package:bookworm_friends/core/controllers/settings_controller.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk_template.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  Get.put<AppController>(AppController());
  Get.put<UserController>(UserController());
  Get.put<AuthController>(AuthController());
  await AuthController.to.asyncMethod();
  Get.put<HomeNavigationController>(HomeNavigationController());
  Get.put<BookDetailsController>(BookDetailsController());
  Get.put<SearchBookController>(SearchBookController());
  Get.put<LibraryController>(LibraryController());
  Get.put<SettingsController>(SettingsController());
  Get.put<DeepLinkController>(DeepLinkController());

  runApp(const MyApp());
}

class MyApp extends GetView<AppController> {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
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
    return GetMaterialApp(
      theme: controller.theme.copyWith(
        colorScheme: controller.theme.colorScheme.copyWith(
          // secondary: brightPrimaryColor.withOpacity(0.3),
          secondary: lightGrayColor,
        ),
      ),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('ko', 'KR'),
      ],
      key: controller.scaffoldKey,
      initialRoute: '/',
      locale: const Locale('ko', 'KO'),
      getPages: AppRoutes.routes,
      builder: EasyLoading.init(),
    );
  }
}
