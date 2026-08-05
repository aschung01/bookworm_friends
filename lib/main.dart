import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/services/notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  if (!kDebugMode) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  final prefs = await SharedPreferences.getInstance();

  _initDeepLinks();
  _configureEasyLoading();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MyApp(),
    ),
  );

  // Initialize push notifications without blocking first paint. On iOS these
  // calls await APNs registration, which never completes on the simulator and
  // would otherwise hang startup before runApp.
  unawaited(NotificationService.initialize());
}

void _initDeepLinks() {
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) {
    supabase.auth.getSessionFromUrl(uri);
  });
}

void _configureEasyLoading() {
  EasyLoading.instance
    ..indicatorType = EasyLoadingIndicatorType.fadingCircle
    ..loadingStyle = EasyLoadingStyle.dark
    ..maskType = EasyLoadingMaskType.clear
    ..toastPosition = EasyLoadingToastPosition.bottom
    ..indicatorSize = 40.0
    ..radius = 10.0
    ..displayDuration = const Duration(milliseconds: 2000)
    ..userInteractions = false
    ..dismissOnTap = false;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await AppTrackingTransparency.requestTrackingAuthorization();
        } catch (_) {}
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: greenThemeColor,
          secondary: lightGrayColor,
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // No forced locale: follow the device locale, resolving to a supported
      // one (en/ko). Add an in-app override here later if desired.
      builder: EasyLoading.init(),
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
    );
  }
}
