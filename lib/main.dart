import 'dart:async';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/invite_link_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/providers/shell_chrome_provider.dart';
import 'package:bookworm_friends/providers/theme_provider.dart';
import 'package:bookworm_friends/services/image_disk_cache.dart';
import 'package:bookworm_friends/services/notification_service.dart';
import 'package:bookworm_friends/ui/widgets/invite_link_listener.dart';
import 'package:bookworm_friends/ui/widgets/password_recovery_listener.dart';
import 'package:bookworm_friends/ui/widgets/shell_chrome.dart';
import 'package:bookworm_friends/ui/widgets/streak_widget_sync.dart';
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

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  final prefs = await SharedPreferences.getInstance();

  // Before the first cover or avatar resolves. Assigns a static and nothing more --
  // see `configureImageDiskCache`.
  configureImageDiskCache();

  _configureEasyLoading();

  // **The second `app_links` subscriber, and the rule that makes it safe.**
  //
  // This file used to say there was deliberately no deep link listener here, because
  // `Supabase.initialize` already starts one (`SupabaseAuth._startDeeplinkObserver`)
  // to exchange the OAuth code, `app_links` is a singleton handing the one URI to
  // every subscriber, and an unfiltered second listener raced it over a single-use
  // PKCE code -- so one of the two exchanges always failed and pushed an
  // `AuthException` onto `onAuthStateChange`.
  //
  // That reasoning still holds and is not being overruled. `InviteLinkService`
  // reacts *only* to `https://libstack.app/i/<token>` and returns immediately for
  // everything else, so the OAuth callback is still handled by exactly one observer.
  // **Widening that filter brings the sign-in bug back**, and it will look like
  // intermittent login failure rather than anything to do with invites.
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  // Started before `runApp` so the launch URI is read before the first frame: the
  // splash page checks for a pending token, and a listener attached later would miss
  // the cold-start case entirely -- which is the case a tapped link always is.
  final linkService = container.read(inviteLinkServiceProvider);
  linkService.tokens.listen(
    (token) =>
        container.read(pendingInviteTokenProvider.notifier).state = token,
  );
  await linkService.start();
  final launchToken = linkService.takePending();
  if (launchToken != null) {
    container.read(pendingInviteTokenProvider.notifier).state = launchToken;
  }

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));

  // Initialize push notifications without blocking first paint. On iOS these
  // calls await APNs registration, which never completes on the simulator and
  // would otherwise hang startup before runApp.
  unawaited(NotificationService.initialize());
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

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  /// Held rather than rebuilt: `EasyLoading.init()` returns a fresh builder each
  /// call, and it now has to compose with the shell's chrome.
  late final TransitionBuilder _easyLoading = EasyLoading.init();

  // **No App Tracking Transparency prompt, deliberately.** One used to fire from
  // `initState` on every iOS launch. Nothing in the app can act on the answer:
  // there is no ad SDK, no attribution SDK, and Firebase Analytics has not touched
  // the IDFA since Firebase 8 unless `GoogleAppMeasurementIdentitySupport` is
  // linked, which it is not. Crash and performance diagnostics are not "tracking"
  // under Apple's definition, which requires linking user data to third-party data
  // for advertising or a data broker.
  //
  // So the prompt asked for a permission that could not be exercised, and the
  // matching `usesIdfa` declaration in App Store Connect had no valid purpose to
  // select from the three Apple offers. Both are gone. **Do not re-add the prompt
  // without an SDK that actually reads the identifier**, or the declaration becomes
  // false again.

  /// Wakes the reading day's phase at 21:00 and again at midnight.
  ///
  /// **The clock lives here rather than in `readingDayPhaseProvider`**, and that placement is
  /// the whole design. The provider is a pure function of the recorded days and the current
  /// moment; a timer inside it made it a provider every widget test had to know about, because
  /// `testWidgets` fails a test that ends with a timer pending and a container disposed in a
  /// tear-down is torn down after that check. Owning it at the shell keeps the provider
  /// testable and puts the one long-lived timer in the one place that is already long-lived.
  Timer? _phaseBoundary;

  @override
  void initState() {
    super.initState();
    // **The app's first lifecycle observer**, for the same clock. A suspended app's timers do
    // not fire on schedule, so a reader who backgrounds the app at 20:55 and returns at 22:10
    // would come back to a phase computed on the wrong side of the boundary. Resume recomputes
    // from the real clock, which is also what covers the timer firing an hour out across a DST
    // transition — and why `nextReadingPhaseBoundary` can stay wall-clock arithmetic.
    WidgetsBinding.instance.addObserver(this);
    _schedulePhaseBoundary();
  }

  @override
  void dispose() {
    _phaseBoundary?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only `resumed`: the passage of time is the only thing this is watching for, and a phase
    // computed while the app was hidden is not worth the wake.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(readingDayPhaseProvider);
      _schedulePhaseBoundary();
    }
  }

  /// One timer to the next boundary, rescheduled when it fires — not a ticker.
  ///
  /// The phase changes at most twice a day, so a periodic rebuild would be a per-second cost
  /// for two transitions. `nextReadingPhaseBoundary` is asserted to be strictly in the future
  /// at every minute of the day, which is what keeps this from becoming a spin.
  void _schedulePhaseBoundary() {
    _phaseBoundary?.cancel();
    final now = DateTime.now();
    _phaseBoundary = Timer(nextReadingPhaseBoundary(now).difference(now), () {
      ref.invalidate(readingDayPhaseProvider);
      _schedulePhaseBoundary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      navigatorKey: navigatorKey,
      // Replaces `CNTabBarRouteObserver`. It would destroy the tab bar for every
      // sheet route, which is the behaviour the floating bar is built to avoid;
      // this one keeps the halo-containment half that `CNButton` depends on. See
      // `ShellRouteObserver`.
      navigatorObservers: [ref.watch(shellRouteObserverProvider)],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
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
      // The tab bar is layered over the navigator so it can float in front of a
      // modal sheet; EasyLoading wraps *outside* it so a bottom toast still lands
      // on top of the bar rather than behind it.
      // `InviteLinkListener` wraps the shell rather than the other way round: it
      // draws nothing, and a link can arrive on any screen, so it has to sit outside
      // every route. See its class comment for the case it exists to fix — a link
      // tapped while the app is already running used to do nothing at all.
      // `StreakWidgetSync` sits alongside for the same reason and draws nothing either: a night
      // can be recorded from the streak page, the book details band or the finished-books sheet,
      // and the home-screen widget has to follow all three. Innermost of the three so it is
      // below `Localizations` — it needs `AppLocalizations` to put translated copy in the
      // snapshot, which is what keeps those strings out of Swift.
      // `PasswordRecoveryListener` is here on the same grounds: a reset link can be
      // exchanged while the reader is anywhere, and the set-password screen is pushed over
      // whatever they landed on rather than routed to. See its class comment.
      builder: (context, child) => _easyLoading(
        context,
        InviteLinkListener(
          navigatorKey: navigatorKey,
          child: PasswordRecoveryListener(
            navigatorKey: navigatorKey,
            child: StreakWidgetSync(
              child: ShellChrome(navigatorKey: navigatorKey, child: child!),
            ),
          ),
        ),
      ),
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
      // Consulted only for names the table above does not hold. See
      // `AppRoutes.onGenerateRoute`: it is where a route that needs its own
      // transition lives, which the table cannot express.
      onGenerateRoute: AppRoutes.onGenerateRoute,
    );
  }
}
