# Flutter + Supabase Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Bookworm Friends from Flutter 2.17/Amplify/GetX to Flutter 3.32+/Supabase/Riverpod with full data layer replacement.

**Architecture:** Supabase Postgres with RLS replaces the defunct Django/Amplify backend. Auth moves to Supabase native OAuth (Apple + Google). GetX controllers become Riverpod providers that call Supabase directly. Firebase retained for push/analytics/crashlytics, with Edge Functions sending notifications.

**Tech Stack:** Flutter 3.32+, Dart 3, supabase_flutter, flutter_riverpod, Firebase (messaging/analytics/crashlytics), Supabase Edge Functions (Deno/TypeScript)

---

## Task 1: Flutter & Dart 3 Upgrade + Dependency Swap

**Files:**
- Modify: `pubspec.yaml`
- Modify: `analysis_options.yaml`
- Delete: `amplify/` (entire directory)
- Delete: `lib/core/services/amplify_service.dart`
- Delete: `lib/core/services/kakao_service.dart`
- Delete: `lib/core/services/api_service.dart`
- Delete: `lib/core/services/library_api_service.dart`
- Delete: `lib/core/services/user_api_service.dart`
- Delete: `lib/helpers/dio_auth_interceptor.dart`
- Delete: `lib/helpers/parse_jwt.dart`

- [ ] **Step 1: Update pubspec.yaml SDK constraint and dependencies**

Replace the entire `pubspec.yaml` with updated dependencies:

```yaml
name: bookworm_friends
description: A social reading tracker app.
publish_to: 'none'
version: 2.0.0+1

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  supabase_flutter: ^2.8.0
  flutter_riverpod: ^2.6.0
  intl: ^0.19.0
  flutter_secure_storage: ^9.2.0
  flutter_easyloading: ^3.0.5
  phosphor_flutter: ^2.1.0
  flutter_shake_animated: ^0.0.5
  emojis: ^0.9.9
  animated_text_kit: ^4.2.2
  shimmer: ^3.0.0
  flutter_svg: ^2.0.10
  url_launcher: ^6.3.0
  package_info_plus: ^8.0.0
  firebase_core: ^3.8.0
  firebase_messaging: ^15.1.0
  flutter_local_notifications: ^18.0.0
  app_links: ^6.3.0
  in_app_review: ^2.0.9
  firebase_analytics: ^11.3.0
  firebase_crashlytics: ^4.1.0
  app_tracking_transparency: ^2.0.6
  go_router: ^14.6.0
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/icons/bookwormIcon.svg
    - assets/icons/smileBookwormIcon.svg
    - assets/icons/appleWhiteIcon.svg
    - assets/icons/appleBlackIcon.svg
    - assets/icons/googleIcon.svg
    - assets/icons/bookmarkIcon.svg
    - assets/icons/sadCharacter.svg
  fonts:
    - family: DesignHouse
      fonts:
        - asset: assets/fonts/designhouseOTFBold.otf
          weight: 700
        - asset: assets/fonts/designhouseOTFLight.otf
          weight: 300
```

- [ ] **Step 2: Delete obsolete files and directories**

```bash
rm -rf amplify/
rm lib/core/services/amplify_service.dart
rm lib/core/services/kakao_service.dart
rm lib/core/services/api_service.dart
rm lib/core/services/library_api_service.dart
rm lib/core/services/user_api_service.dart
rm lib/helpers/dio_auth_interceptor.dart
rm lib/helpers/parse_jwt.dart
rm assets/icons/kakaoIcon.svg
```

- [ ] **Step 3: Update analysis_options.yaml**

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

- [ ] **Step 4: Run flutter pub get and fix version conflicts**

```bash
flutter pub get
```

Resolve any dependency conflicts by adjusting version constraints. This step may require iteration.

- [ ] **Step 5: Delete amplifyconfiguration.dart if it exists**

```bash
find lib -name "amplifyconfiguration.dart" -delete
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: upgrade to Flutter 3/Dart 3, swap dependencies for Supabase + Riverpod"
```

---

## Task 2: Supabase Schema & RLS Setup

**Files:**
- Create: `supabase/migrations/001_initial_schema.sql`
- Create: `supabase/migrations/002_rls_policies.sql`
- Create: `supabase/migrations/003_auth_trigger.sql`

- [ ] **Step 1: Initialize Supabase project structure**

```bash
mkdir -p supabase/migrations
```

- [ ] **Step 2: Write initial schema migration**

Create `supabase/migrations/001_initial_schema.sql`:

```sql
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username varchar(20) UNIQUE,
  emoji varchar(6),
  is_private boolean NOT NULL DEFAULT false,
  fcm_token text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.follows (
  follower_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id != following_id)
);

CREATE TABLE public.shelves (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name varchar(15) NOT NULL,
  position int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.books (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  shelf_id uuid NOT NULL REFERENCES public.shelves(id) ON DELETE CASCADE,
  isbn varchar(13) NOT NULL,
  title varchar(100) NOT NULL,
  thumbnail text NOT NULL,
  status smallint NOT NULL DEFAULT 0,
  position int NOT NULL DEFAULT 0,
  rating real,
  start_date date,
  finish_date date,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.book_memos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.book_compliments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  from_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  compliment varchar(6) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_shelves_user_id ON public.shelves(user_id);
CREATE INDEX idx_books_user_id ON public.books(user_id);
CREATE INDEX idx_books_shelf_id ON public.books(shelf_id);
CREATE INDEX idx_book_memos_book_id ON public.book_memos(book_id);
CREATE INDEX idx_book_compliments_book_id ON public.book_compliments(book_id);
CREATE INDEX idx_follows_following_id ON public.follows(following_id);
```

- [ ] **Step 3: Write RLS policies migration**

Create `supabase/migrations/002_rls_policies.sql`:

```sql
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shelves ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_memos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_compliments ENABLE ROW LEVEL SECURITY;

-- Helper function: check if a profile is visible to the current user
CREATE OR REPLACE FUNCTION public.is_profile_visible(target_user_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = target_user_id
    AND (
      is_private = false
      OR id = auth.uid()
      OR id IN (SELECT following_id FROM public.follows WHERE follower_id = auth.uid())
    )
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- profiles policies
CREATE POLICY "Users can read visible profiles" ON public.profiles
  FOR SELECT USING (
    is_private = false
    OR id = auth.uid()
    OR id IN (SELECT following_id FROM public.follows WHERE follower_id = auth.uid())
  );

CREATE POLICY "Users can insert own profile" ON public.profiles
  FOR INSERT WITH CHECK (id = auth.uid());

CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE USING (id = auth.uid());

-- follows policies
CREATE POLICY "Anyone can read follows" ON public.follows
  FOR SELECT USING (true);

CREATE POLICY "Users can insert own follows" ON public.follows
  FOR INSERT WITH CHECK (follower_id = auth.uid());

CREATE POLICY "Users can delete own follows" ON public.follows
  FOR DELETE USING (follower_id = auth.uid());

-- shelves policies
CREATE POLICY "Owner full access to shelves" ON public.shelves
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Others can read visible shelves" ON public.shelves
  FOR SELECT USING (public.is_profile_visible(user_id));

-- books policies
CREATE POLICY "Owner full access to books" ON public.books
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Others can read visible books" ON public.books
  FOR SELECT USING (public.is_profile_visible(user_id));

-- book_memos policies
CREATE POLICY "Owner full access to memos" ON public.book_memos
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Others can read visible memos" ON public.book_memos
  FOR SELECT USING (public.is_profile_visible(user_id));

-- book_compliments policies
CREATE POLICY "Sender can insert compliments" ON public.book_compliments
  FOR INSERT WITH CHECK (from_user_id = auth.uid());

CREATE POLICY "Book owner can read compliments" ON public.book_compliments
  FOR SELECT USING (
    book_id IN (SELECT id FROM public.books WHERE user_id = auth.uid())
    OR from_user_id = auth.uid()
  );

CREATE POLICY "Sender can delete own compliments" ON public.book_compliments
  FOR DELETE USING (from_user_id = auth.uid());
```

- [ ] **Step 4: Write auth trigger migration**

Create `supabase/migrations/003_auth_trigger.sql`:

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id) VALUES (NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Updated_at trigger for profiles
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER book_memos_updated_at
  BEFORE UPDATE ON public.book_memos
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
```

- [ ] **Step 5: Apply migrations to Supabase project**

Run these migrations via the Supabase Dashboard SQL Editor or CLI:

```bash
# If using Supabase CLI:
supabase db push
```

- [ ] **Step 6: Commit**

```bash
git add supabase/
git commit -m "feat: add Supabase schema, RLS policies, and auth trigger migrations"
```

---

## Task 3: Supabase Initialization & Constants

**Files:**
- Modify: `lib/constants/constants.dart`
- Create: `lib/core/supabase_config.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Rewrite constants.dart**

Remove all Amplify/Cognito/Kakao constants, keep UI constants:

```dart
import 'package:flutter/material.dart';

const Color greenThemeColor = Color(0xff09BC8A);
const Color darkPrimaryColor = Color(0xff212529);
const Color softRedColor = Color(0xffD9433A);
const Color cancelRedColor = Color(0xffD9433A);
const Color lightGrayColor = Color(0xffE9ECEF);
const Color grayColor = Color(0xffADB5BD);
const Color backgroundColor = Color(0xffF8F9FA);

List<double> bookOpacityList = [0.4, 0.7, 1.0];

const String kakaoBookSearchBaseUrl = 'https://dapi.kakao.com';
const String kakaoRestApiKey = 'ab7c0da780466d764fbee0e55e65900c';
```

- [ ] **Step 2: Create Supabase config**

Create `lib/core/supabase_config.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'YOUR_SUPABASE_URL';
const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

SupabaseClient get supabase => Supabase.instance.client;
```

- [ ] **Step 3: Rewrite main.dart with Supabase + Riverpod initialization**

```dart
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: greenThemeColor,
          secondary: lightGrayColor,
        ),
        useMaterial3: true,
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
      locale: const Locale('ko', 'KR'),
      builder: EasyLoading.init(),
      home: const SplashPage(),
    );
  }
}

// Placeholder — will be replaced with proper routing in Task 7
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
```

- [ ] **Step 4: Verify the app builds**

```bash
flutter pub get && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git add lib/constants/constants.dart lib/core/supabase_config.dart lib/main.dart
git commit -m "feat: initialize Supabase + Riverpod, rewrite main.dart and constants"
```

---

## Task 4: Auth Provider (Riverpod)

**Files:**
- Create: `lib/providers/auth_provider.dart`
- Delete: `lib/core/controllers/auth_controller.dart`

- [ ] **Step 1: Create auth provider**

Create `lib/providers/auth_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final User? user;

  const AuthState({required this.status, this.user});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.authenticated(User user)
      : this(status: AuthStatus.authenticated, user: user);
  const AuthState.unauthenticated()
      : this(status: AuthStatus.unauthenticated);
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final session = supabase.auth.currentSession;
    if (session != null) {
      return AuthState.authenticated(session.user);
    }

    supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session != null) {
        state = AuthState.authenticated(session.user);
      } else if (event == AuthChangeEvent.signedOut) {
        state = const AuthState.unauthenticated();
      }
    });

    return const AuthState.unauthenticated();
  }

  Future<void> signInWithGoogle() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'bookworm-friends://home',
    );
  }

  Future<void> signInWithApple() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: 'bookworm-friends://home',
    );
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
    state = const AuthState.unauthenticated();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authProvider);
  return auth.user?.id;
});
```

- [ ] **Step 2: Delete old auth controller**

```bash
rm lib/core/controllers/auth_controller.dart
```

- [ ] **Step 3: Commit**

```bash
git add lib/providers/auth_provider.dart
git add -u
git commit -m "feat: add Riverpod auth provider with Apple + Google OAuth"
```

---

## Task 5: Profile Provider

**Files:**
- Create: `lib/providers/profile_provider.dart`
- Create: `lib/models/profile.dart`

- [ ] **Step 1: Create profile model**

Create `lib/models/profile.dart`:

```dart
class Profile {
  final String id;
  final String? username;
  final String? emoji;
  final bool isPrivate;
  final String? fcmToken;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profile({
    required this.id,
    this.username,
    this.emoji,
    this.isPrivate = false,
    this.fcmToken,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String?,
      emoji: json['emoji'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      fcmToken: json['fcm_token'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get needsOnboarding => username == null;
}
```

- [ ] **Step 2: Create profile provider**

Create `lib/providers/profile_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';

final profileProvider = FutureProvider.autoDispose<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final data = await supabase
      .from('profiles')
      .select()
      .eq('id', userId)
      .single();

  return Profile.fromJson(data);
});

final updateProfileProvider = Provider((ref) => UpdateProfileNotifier(ref));

class UpdateProfileNotifier {
  final Ref ref;
  UpdateProfileNotifier(this.ref);

  Future<void> updateUsername(String username) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase
        .from('profiles')
        .update({'username': username})
        .eq('id', userId);

    ref.invalidate(profileProvider);
  }

  Future<void> updateEmoji(String emoji) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase
        .from('profiles')
        .update({'emoji': emoji})
        .eq('id', userId);

    ref.invalidate(profileProvider);
  }

  Future<void> updatePrivacy(bool isPrivate) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase
        .from('profiles')
        .update({'is_private': isPrivate})
        .eq('id', userId);

    ref.invalidate(profileProvider);
  }

  Future<void> updateFcmToken(String token) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase
        .from('profiles')
        .update({'fcm_token': token})
        .eq('id', userId);
  }

  Future<bool> checkUsernameAvailable(String username) async {
    final data = await supabase
        .from('profiles')
        .select('id')
        .eq('username', username)
        .maybeSingle();

    return data == null;
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/models/profile.dart lib/providers/profile_provider.dart
git commit -m "feat: add profile model and Riverpod provider"
```

---

## Task 6: Library Provider (Shelves + Books + Memos)

**Files:**
- Create: `lib/models/shelf.dart`
- Create: `lib/models/book.dart`
- Create: `lib/models/book_memo.dart`
- Create: `lib/providers/library_provider.dart`
- Delete: `lib/core/controllers/library_controller.dart`
- Delete: `lib/core/models/user_library_model.dart`

- [ ] **Step 1: Create shelf model**

Create `lib/models/shelf.dart`:

```dart
import 'package:bookworm_friends/models/book.dart';

class Shelf {
  final String id;
  final String userId;
  final String name;
  final int position;
  final DateTime createdAt;
  final List<Book> books;

  const Shelf({
    required this.id,
    required this.userId,
    required this.name,
    required this.position,
    required this.createdAt,
    this.books = const [],
  });

  factory Shelf.fromJson(Map<String, dynamic> json) {
    return Shelf(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      position: json['position'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      books: (json['books'] as List<dynamic>?)
              ?.map((b) => Book.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
```

- [ ] **Step 2: Create book model**

Create `lib/models/book.dart`:

```dart
class Book {
  final String id;
  final String userId;
  final String shelfId;
  final String isbn;
  final String title;
  final String thumbnail;
  final int status;
  final int position;
  final double? rating;
  final DateTime? startDate;
  final DateTime? finishDate;
  final DateTime createdAt;

  const Book({
    required this.id,
    required this.userId,
    required this.shelfId,
    required this.isbn,
    required this.title,
    required this.thumbnail,
    required this.status,
    required this.position,
    this.rating,
    this.startDate,
    this.finishDate,
    required this.createdAt,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      shelfId: json['shelf_id'] as String,
      isbn: json['isbn'] as String,
      title: json['title'] as String,
      thumbnail: json['thumbnail'] as String,
      status: json['status'] as int,
      position: json['position'] as int? ?? 0,
      rating: (json['rating'] as num?)?.toDouble(),
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : null,
      finishDate: json['finish_date'] != null
          ? DateTime.parse(json['finish_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
```

- [ ] **Step 3: Create book memo model**

Create `lib/models/book_memo.dart`:

```dart
class BookMemo {
  final String id;
  final String bookId;
  final String userId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BookMemo({
    required this.id,
    required this.bookId,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BookMemo.fromJson(Map<String, dynamic> json) {
    return BookMemo(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
```

- [ ] **Step 4: Create library provider**

Create `lib/providers/library_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/book_memo.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:intl/intl.dart';

final libraryProvider = FutureProvider.autoDispose<List<Shelf>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final data = await supabase
      .from('shelves')
      .select('*, books(*)')
      .eq('user_id', userId)
      .order('position');

  return data.map((s) => Shelf.fromJson(s)).toList();
});

final finishedBooksProvider =
    FutureProvider.autoDispose.family<List<Book>, ({int year, int month})>(
  (ref, filter) async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return [];

    var query = supabase
        .from('books')
        .select()
        .eq('user_id', userId)
        .eq('status', 2);

    if (filter.year > 0) {
      final start = DateTime(filter.year, filter.month > 0 ? filter.month : 1);
      final end = filter.month > 0
          ? DateTime(filter.year, filter.month + 1)
          : DateTime(filter.year + 1);
      query = query
          .gte('finish_date', DateFormat('yyyy-MM-dd').format(start))
          .lt('finish_date', DateFormat('yyyy-MM-dd').format(end));
    }

    final data = await query.order('finish_date', ascending: false);
    return data.map((b) => Book.fromJson(b)).toList();
  },
);

final libraryActionsProvider = Provider((ref) => LibraryActions(ref));

class LibraryActions {
  final Ref ref;
  LibraryActions(this.ref);

  Future<void> addShelf(String name) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final shelves = await ref.read(libraryProvider.future);
    final nextPosition = shelves.isEmpty ? 0 : shelves.last.position + 1;

    await supabase.from('shelves').insert({
      'user_id': userId,
      'name': name,
      'position': nextPosition,
    });

    ref.invalidate(libraryProvider);
  }

  Future<void> updateShelfName(String shelfId, String newName) async {
    await supabase
        .from('shelves')
        .update({'name': newName})
        .eq('id', shelfId);

    ref.invalidate(libraryProvider);
  }

  Future<void> updateShelfOrder(List<String> shelfIds) async {
    for (var i = 0; i < shelfIds.length; i++) {
      await supabase
          .from('shelves')
          .update({'position': i})
          .eq('id', shelfIds[i]);
    }

    ref.invalidate(libraryProvider);
  }

  Future<void> deleteShelf(String shelfId) async {
    await supabase.from('shelves').delete().eq('id', shelfId);
    ref.invalidate(libraryProvider);
  }

  Future<void> addBook({
    required String shelfId,
    required String isbn,
    required String title,
    required String thumbnail,
    required int status,
    DateTime? startDate,
    DateTime? finishDate,
  }) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase.from('books').insert({
      'user_id': userId,
      'shelf_id': shelfId,
      'isbn': isbn,
      'title': title,
      'thumbnail': thumbnail,
      'status': status,
      'start_date': startDate != null
          ? DateFormat('yyyy-MM-dd').format(startDate)
          : null,
      'finish_date': finishDate != null
          ? DateFormat('yyyy-MM-dd').format(finishDate)
          : null,
    });

    ref.invalidate(libraryProvider);
  }

  Future<void> updateBookStatus(
    String bookId,
    int status, {
    DateTime? startDate,
    DateTime? finishDate,
  }) async {
    await supabase.from('books').update({
      'status': status,
      'start_date': startDate != null
          ? DateFormat('yyyy-MM-dd').format(startDate)
          : null,
      'finish_date': finishDate != null
          ? DateFormat('yyyy-MM-dd').format(finishDate)
          : null,
    }).eq('id', bookId);

    ref.invalidate(libraryProvider);
  }

  Future<void> deleteBook(String bookId) async {
    await supabase.from('books').delete().eq('id', bookId);
    ref.invalidate(libraryProvider);
  }

  Future<void> addMemo(String bookId, String content) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase.from('book_memos').insert({
      'book_id': bookId,
      'user_id': userId,
      'content': content,
    });
  }

  Future<void> updateMemo(String memoId, String content) async {
    await supabase
        .from('book_memos')
        .update({'content': content})
        .eq('id', memoId);
  }

  Future<void> deleteMemo(String memoId) async {
    await supabase.from('book_memos').delete().eq('id', memoId);
  }
}

final bookMemosProvider =
    FutureProvider.autoDispose.family<List<BookMemo>, String>(
  (ref, bookId) async {
    final data = await supabase
        .from('book_memos')
        .select()
        .eq('book_id', bookId)
        .order('created_at', ascending: false);

    return data.map((m) => BookMemo.fromJson(m)).toList();
  },
);
```

- [ ] **Step 5: Delete old controllers and models**

```bash
rm lib/core/controllers/library_controller.dart
rm lib/core/models/user_library_model.dart
```

- [ ] **Step 6: Commit**

```bash
git add lib/models/ lib/providers/library_provider.dart
git add -u
git commit -m "feat: add library models and Riverpod provider (shelves, books, memos)"
```

---

## Task 7: User/Social Provider (Follows + Search + Compliments)

**Files:**
- Create: `lib/models/book_compliment.dart`
- Create: `lib/providers/user_provider.dart`
- Create: `lib/providers/book_details_provider.dart`
- Delete: `lib/core/controllers/user_controller.dart`
- Delete: `lib/core/controllers/book_details_controller.dart`
- Delete: `lib/core/controllers/settings_controller.dart`

- [ ] **Step 1: Create book compliment model**

Create `lib/models/book_compliment.dart`:

```dart
class BookCompliment {
  final String id;
  final String bookId;
  final String fromUserId;
  final String compliment;
  final DateTime createdAt;

  const BookCompliment({
    required this.id,
    required this.bookId,
    required this.fromUserId,
    required this.compliment,
    required this.createdAt,
  });

  factory BookCompliment.fromJson(Map<String, dynamic> json) {
    return BookCompliment(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      fromUserId: json['from_user_id'] as String,
      compliment: json['compliment'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
```

- [ ] **Step 2: Create user provider**

Create `lib/providers/user_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';

final followingListProvider =
    FutureProvider.autoDispose<List<Profile>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final data = await supabase
      .from('follows')
      .select('following_id, profiles!follows_following_id_fkey(*)')
      .eq('follower_id', userId);

  return data
      .map((row) => Profile.fromJson(row['profiles'] as Map<String, dynamic>))
      .toList();
});

final followerCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, userId) async {
  final result = await supabase
      .from('follows')
      .select()
      .eq('following_id', userId)
      .count();

  return result.count;
});

final followingCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, userId) async {
  final result = await supabase
      .from('follows')
      .select()
      .eq('follower_id', userId)
      .count();

  return result.count;
});

final isFollowingProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, targetUserId) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;

  final data = await supabase
      .from('follows')
      .select()
      .eq('follower_id', userId)
      .eq('following_id', targetUserId)
      .maybeSingle();

  return data != null;
});

final userLibraryProvider =
    FutureProvider.autoDispose.family<List<Shelf>, String>(
  (ref, targetUserId) async {
    final data = await supabase
        .from('shelves')
        .select('*, books(*)')
        .eq('user_id', targetUserId)
        .order('position');

    return data.map((s) => Shelf.fromJson(s)).toList();
  },
);

final searchUsersProvider =
    FutureProvider.autoDispose.family<List<Profile>, String>(
  (ref, query) async {
    if (query.isEmpty) return [];

    final data = await supabase
        .from('profiles')
        .select()
        .ilike('username', '%$query%')
        .limit(20);

    return data.map((p) => Profile.fromJson(p)).toList();
  },
);

final userActionsProvider = Provider((ref) => UserActions(ref));

class UserActions {
  final Ref ref;
  UserActions(this.ref);

  Future<void> follow(String targetUserId) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase.from('follows').insert({
      'follower_id': userId,
      'following_id': targetUserId,
    });

    ref.invalidate(followingListProvider);
    ref.invalidate(isFollowingProvider(targetUserId));
  }

  Future<void> unfollow(String targetUserId) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase
        .from('follows')
        .delete()
        .eq('follower_id', userId)
        .eq('following_id', targetUserId);

    ref.invalidate(followingListProvider);
    ref.invalidate(isFollowingProvider(targetUserId));
  }
}
```

- [ ] **Step 3: Create book details provider**

Create `lib/providers/book_details_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';

final bookComplimentsProvider =
    FutureProvider.autoDispose.family<List<BookCompliment>, String>(
  (ref, bookId) async {
    final data = await supabase
        .from('book_compliments')
        .select()
        .eq('book_id', bookId)
        .order('created_at', ascending: false);

    return data.map((c) => BookCompliment.fromJson(c)).toList();
  },
);

final bookDetailsActionsProvider = Provider((ref) => BookDetailsActions(ref));

class BookDetailsActions {
  final Ref ref;
  BookDetailsActions(this.ref);

  Future<void> addCompliment(String bookId, String emoji) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase.from('book_compliments').insert({
      'book_id': bookId,
      'from_user_id': userId,
      'compliment': emoji,
    });

    ref.invalidate(bookComplimentsProvider(bookId));
  }

  Future<void> deleteCompliment(String complimentId, String bookId) async {
    await supabase.from('book_compliments').delete().eq('id', complimentId);
    ref.invalidate(bookComplimentsProvider(bookId));
  }
}
```

- [ ] **Step 4: Delete old controllers**

```bash
rm lib/core/controllers/user_controller.dart
rm lib/core/controllers/book_details_controller.dart
rm lib/core/controllers/settings_controller.dart
rm lib/core/controllers/search_book_controller.dart
rm lib/core/controllers/deep_link_controller.dart
rm lib/core/controllers/app_controller.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/models/book_compliment.dart lib/providers/user_provider.dart lib/providers/book_details_provider.dart
git add -u
git commit -m "feat: add user/social and book details Riverpod providers"
```

---

## Task 8: Book Search Service (Kakao Book API)

**Files:**
- Create: `lib/services/book_search_service.dart`

The Kakao Book Search API is still used (it's a public API, not tied to Kakao login). We keep it but rewrite using the `http` package (Supabase dependency includes it) instead of Dio.

- [ ] **Step 1: Create book search service**

Create `lib/services/book_search_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bookworm_friends/constants/constants.dart';

class BookSearchResult {
  final String title;
  final String isbn;
  final String thumbnail;
  final String? url;
  final List<String> authors;
  final String? publisher;
  final DateTime? datetime;
  final String? contents;

  const BookSearchResult({
    required this.title,
    required this.isbn,
    required this.thumbnail,
    this.url,
    this.authors = const [],
    this.publisher,
    this.datetime,
    this.contents,
  });

  factory BookSearchResult.fromJson(Map<String, dynamic> json) {
    return BookSearchResult(
      title: json['title'] as String? ?? '',
      isbn: (json['isbn'] as String? ?? '').split(' ').first,
      thumbnail: json['thumbnail'] as String? ?? '',
      url: json['url'] as String?,
      authors: (json['authors'] as List<dynamic>?)
              ?.map((a) => a as String)
              .toList() ??
          [],
      publisher: json['publisher'] as String?,
      datetime: json['datetime'] != null
          ? DateTime.tryParse(json['datetime'] as String)
          : null,
      contents: json['contents'] as String?,
    );
  }
}

class BookSearchService {
  static const _baseUrl = kakaoBookSearchBaseUrl;
  static const _apiKey = kakaoRestApiKey;

  static Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async {
    final uri = Uri.parse('$_baseUrl/v3/search/book').replace(
      queryParameters: {
        'query': query,
        'page': page.toString(),
        'size': size.toString(),
      },
    );

    final response = await http.get(uri, headers: {
      'Authorization': 'KakaoAK $_apiKey',
    });

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final documents = data['documents'] as List<dynamic>;

    return documents
        .map((d) => BookSearchResult.fromJson(d as Map<String, dynamic>))
        .toList();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/services/book_search_service.dart
git commit -m "feat: add Kakao book search service using http package"
```

---

## Task 9: Push Notification Setup

**Files:**
- Create: `lib/services/notification_service.dart`
- Create: `supabase/functions/send-notification/index.ts`

- [ ] **Step 1: Create notification service (client side)**

Create `lib/services/notification_service.dart`:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:bookworm_friends/core/supabase_config.dart';

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    await _messaging.requestPermission();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(settings);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  static Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  static Future<void> updateTokenInProfile() async {
    final token = await getToken();
    if (token == null) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    await supabase
        .from('profiles')
        .update({'fcm_token': token})
        .eq('id', userId);
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'default_channel',
          'Default',
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
```

- [ ] **Step 2: Create Edge Function for sending notifications**

Create `supabase/functions/send-notification/index.ts`:

```typescript
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const fcmServerKey = Deno.env.get("FCM_SERVER_KEY")!;

serve(async (req) => {
  const { type, target_user_id, title, body } = await req.json();

  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  const { data: profile } = await supabase
    .from("profiles")
    .select("fcm_token")
    .eq("id", target_user_id)
    .single();

  if (!profile?.fcm_token) {
    return new Response(JSON.stringify({ error: "No FCM token" }), {
      status: 404,
    });
  }

  const fcmResponse = await fetch(
    "https://fcm.googleapis.com/fcm/send",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `key=${fcmServerKey}`,
      },
      body: JSON.stringify({
        to: profile.fcm_token,
        notification: { title, body },
        data: { type },
      }),
    }
  );

  const result = await fcmResponse.json();
  return new Response(JSON.stringify(result), { status: 200 });
});
```

- [ ] **Step 3: Create poke RPC function**

Add to `supabase/migrations/003_auth_trigger.sql` or create a new migration. Create `supabase/migrations/004_poke_function.sql`:

```sql
CREATE OR REPLACE FUNCTION public.poke_user(target_username text)
RETURNS void AS $$
DECLARE
  target_id uuid;
  target_token text;
  poker_username text;
BEGIN
  SELECT id, fcm_token INTO target_id, target_token
  FROM public.profiles
  WHERE username = target_username;

  SELECT username INTO poker_username
  FROM public.profiles
  WHERE id = auth.uid();

  IF target_token IS NOT NULL THEN
    PERFORM net.http_post(
      url := current_setting('app.settings.edge_function_url') || '/send-notification',
      body := jsonb_build_object(
        'type', 'poke',
        'target_user_id', target_id,
        'title', poker_username || '님이 콕 찔렀어요!',
        'body', '읽고 있는 책이 궁금해요 📚'
      )
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

- [ ] **Step 4: Commit**

```bash
git add lib/services/notification_service.dart supabase/functions/ supabase/migrations/004_poke_function.sql
git commit -m "feat: add push notification service and Edge Function"
```

---

## Task 10: UI Pages Migration (Null Safety + Riverpod)

**Files:**
- Modify: All files in `lib/ui/pages/`
- Modify: `lib/ui/views/book_details_tab_view.dart`
- Modify: `lib/constants/app_routes.dart`

This task converts all UI pages from GetX to Riverpod. Each page needs:
1. Replace `GetView`/`StatelessWidget` with `ConsumerWidget` or `ConsumerStatefulWidget`
2. Replace `controller.value.obs` with `ref.watch(provider)`
3. Replace `Get.toNamed` with `Navigator.pushNamed` (or go_router)
4. Fix null safety issues (add `?`, `!`, required keywords)

- [ ] **Step 1: Rewrite app_routes.dart with standard Navigator routes**

Replace `lib/constants/app_routes.dart`:

```dart
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
```

- [ ] **Step 2: Rewrite splash_page.dart**

This page checks auth state and routes accordingly:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/constants/app_routes.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final authState = ref.read(authProvider);

    if (authState.status == AuthStatus.authenticated) {
      final profile = await ref.read(profileProvider.future);
      if (!mounted) return;

      if (profile?.needsOnboarding ?? true) {
        Navigator.pushReplacementNamed(context, AppRoutes.settings);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.auth);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
```

- [ ] **Step 3: Rewrite auth_page.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/constants/app_routes.dart';

class AuthPage extends ConsumerWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    });

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/smileBookwormIcon.svg',
              height: 120,
            ),
            const SizedBox(height: 48),
            const Text(
              '책벌레 친구들',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'DesignHouse',
              ),
            ),
            const SizedBox(height: 48),
            _SignInButton(
              label: 'Apple로 계속하기',
              icon: 'assets/icons/appleBlackIcon.svg',
              backgroundColor: Colors.black,
              textColor: Colors.white,
              onPressed: () => ref.read(authProvider.notifier).signInWithApple(),
            ),
            const SizedBox(height: 12),
            _SignInButton(
              label: 'Google로 계속하기',
              icon: 'assets/icons/googleIcon.svg',
              backgroundColor: Colors.white,
              textColor: Colors.black,
              onPressed: () => ref.read(authProvider.notifier).signInWithGoogle(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  final String label;
  final String icon;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onPressed;

  const _SignInButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: textColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: SvgPicture.asset(icon, height: 20),
          label: Text(label),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Update main.dart to use routes map**

Update the `MaterialApp` in `lib/main.dart` to use routes:

```dart
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/services/notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  await NotificationService.initialize();
  await NotificationService.updateTokenInProfile();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: greenThemeColor,
          secondary: lightGrayColor,
        ),
        useMaterial3: true,
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
      locale: const Locale('ko', 'KR'),
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
      builder: EasyLoading.init(),
    );
  }
}
```

- [ ] **Step 5: Convert remaining pages to ConsumerWidget stubs**

For each remaining page (`home_page.dart`, `search_book_page.dart`, `search_user_page.dart`, `settings_page.dart`, `user_library_page.dart`, `loading_page.dart`, `book_info_tab_page.dart`, `book_memo_tab_page.dart`, `book_details_tab_view.dart`), convert to ConsumerWidget/ConsumerStatefulWidget with the same UI but using `ref.watch()` instead of GetX observables. The pattern for each:

```dart
// Before:
class HomePage extends GetView<LibraryController> {
  // ... uses controller.shelf.obs, etc.
}

// After:
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);
    // ... uses libraryAsync.when(data: ..., loading: ..., error: ...)
  }
}
```

Each page conversion follows this pattern — replace `GetView` → `ConsumerWidget`, `controller.x.obs` → `ref.watch(xProvider)`, `Get.toNamed` → `Navigator.pushNamed`, `Obx(()=>...)` → direct widget tree (Riverpod rebuilds the consumer automatically).

This step requires converting each page file individually. The exact UI code is preserved; only the state management wiring changes.

- [ ] **Step 6: Delete remaining helper files that are no longer needed**

```bash
rm lib/helpers/transformers.dart
rm lib/firebase_options.dart
```

Note: `firebase_options.dart` will need to be regenerated with `flutterfire configure` for the new Firebase project setup.

- [ ] **Step 7: Verify the app compiles**

```bash
flutter analyze
```

Fix any remaining null safety or type errors.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: migrate all UI pages from GetX to Riverpod ConsumerWidgets"
```

---

## Task 11: Data Migration Scripts

**Files:**
- Create: `scripts/parse_backup.py`
- Create: `scripts/import_to_supabase.py`

- [ ] **Step 1: Create SQL backup parser script**

Create `scripts/parse_backup.py`:

```python
#!/usr/bin/env python3
"""Parse PostgreSQL COPY blocks from a cluster backup into JSONL files."""

import sys
import json
from pathlib import Path

TABLES_TO_EXTRACT = {
    'public.users_user': [
        'password', 'last_login', 'is_superuser', 'uuid', 'created_at',
        'updated_at', 'username', 'is_active', 'email', 'is_staff', 'resign'
    ],
    'public.user_details_static': [
        'id', 'fcm_token', 'auth_provider', 'user_id', 'emoji', 'private'
    ],
    'public.shelf': ['id', 'name', 'order', 'user_id'],
    'public.book': [
        'id', 'isbn', 'order', 'status', 'start_date', 'finish_date',
        'rating', 'shelf_id', 'user_id', 'title', 'thumbnail'
    ],
    'public.book_memo': [
        'id', 'created_at', 'updated_at', 'content', 'book_id', 'user_id'
    ],
    'public.book_compliment': [
        'id', 'created_at', 'updated_at', 'compliment', 'book_id', 'user_id'
    ],
    'public.users_following_users': ['id', 'following_user_id', 'user_id'],
}


def parse_value(val: str) -> object:
    if val == '\\N':
        return None
    if val == 't':
        return True
    if val == 'f':
        return False
    try:
        return int(val)
    except ValueError:
        pass
    try:
        return float(val)
    except ValueError:
        pass
    return val


def parse_backup(backup_path: str, output_dir: str):
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)

    with open(backup_path, 'r', encoding='utf-8') as f:
        current_table = None
        current_columns = None
        current_file = None

        for line in f:
            if line.startswith('COPY ') and ' FROM stdin' in line:
                parts = line.split('(')
                table_name = parts[0].replace('COPY ', '').strip()

                if table_name in TABLES_TO_EXTRACT:
                    cols_str = parts[1].split(')')[0]
                    current_columns = [c.strip() for c in cols_str.split(',')]
                    current_table = table_name
                    safe_name = table_name.replace('public.', '')
                    current_file = open(output / f'{safe_name}.jsonl', 'w')
                    print(f'Extracting {table_name} -> {safe_name}.jsonl')
                continue

            if current_table and line.strip() == '\\.':
                if current_file:
                    current_file.close()
                current_table = None
                current_columns = None
                current_file = None
                continue

            if current_table and current_columns and current_file:
                values = line.rstrip('\n').split('\t')
                if len(values) == len(current_columns):
                    row = {}
                    for col, val in zip(current_columns, values):
                        row[col] = parse_value(val)
                    current_file.write(json.dumps(row, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <backup_file> [output_dir]')
        sys.exit(1)

    backup_file = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else './migration_data'
    parse_backup(backup_file, out_dir)
    print('Done!')
```

- [ ] **Step 2: Create Supabase import script**

Create `scripts/import_to_supabase.py`:

```python
#!/usr/bin/env python3
"""Import JSONL data into Supabase, creating auth users and mapping old IDs."""

import json
import os
import sys
from pathlib import Path
from supabase import create_client, Client

SUPABASE_URL = os.environ.get('SUPABASE_URL', '')
SUPABASE_SERVICE_KEY = os.environ.get('SUPABASE_SERVICE_ROLE_KEY', '')


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    with open(path, 'r') as f:
        for line in f:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def main(data_dir: str):
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        print('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env vars')
        sys.exit(1)

    supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    data_path = Path(data_dir)

    # Load old data
    users = load_jsonl(data_path / 'users_user.jsonl')
    details = load_jsonl(data_path / 'user_details_static.jsonl')
    shelves_data = load_jsonl(data_path / 'shelf.jsonl')
    books_data = load_jsonl(data_path / 'book.jsonl')
    memos_data = load_jsonl(data_path / 'book_memo.jsonl')
    compliments_data = load_jsonl(data_path / 'book_compliment.jsonl')
    follows_data = load_jsonl(data_path / 'users_following_users.jsonl')

    # Build details lookup
    details_by_user = {d['user_id'].strip(): d for d in details}

    # Step 1: Create auth users, build ID mapping
    old_to_new_user: dict[str, str] = {}

    for user in users:
        if not user.get('is_active') or user.get('resign'):
            continue

        old_id = user['uuid'].strip()
        email = user['email']

        # Create user via admin API
        try:
            result = supabase.auth.admin.create_user({
                'email': email,
                'email_confirm': True,
            })
            new_id = result.user.id
            old_to_new_user[old_id] = new_id

            # Update profile with old data
            detail = details_by_user.get(old_id, {})
            supabase.table('profiles').update({
                'username': user['username'],
                'emoji': detail.get('emoji'),
                'is_private': detail.get('private', False),
            }).eq('id', new_id).execute()

            print(f'  Created user: {user["username"]} ({old_id} -> {new_id})')
        except Exception as e:
            print(f'  Error creating user {email}: {e}')

    # Step 2: Import shelves
    old_to_new_shelf: dict[int, str] = {}

    for shelf in shelves_data:
        old_user_id = shelf['user_id'].strip()
        new_user_id = old_to_new_user.get(old_user_id)
        if not new_user_id:
            continue

        result = supabase.table('shelves').insert({
            'user_id': new_user_id,
            'name': shelf['name'],
            'position': shelf['order'],
        }).execute()

        if result.data:
            old_to_new_shelf[shelf['id']] = result.data[0]['id']

    print(f'Imported {len(old_to_new_shelf)} shelves')

    # Step 3: Import books
    old_to_new_book: dict[int, str] = {}

    for book in books_data:
        old_user_id = book['user_id'].strip()
        new_user_id = old_to_new_user.get(old_user_id)
        new_shelf_id = old_to_new_shelf.get(book['shelf_id'])
        if not new_user_id or not new_shelf_id:
            continue

        result = supabase.table('books').insert({
            'user_id': new_user_id,
            'shelf_id': new_shelf_id,
            'isbn': book['isbn'],
            'title': book['title'],
            'thumbnail': book['thumbnail'],
            'status': book['status'],
            'position': book['order'],
            'rating': book.get('rating'),
            'start_date': book.get('start_date'),
            'finish_date': book.get('finish_date'),
        }).execute()

        if result.data:
            old_to_new_book[book['id']] = result.data[0]['id']

    print(f'Imported {len(old_to_new_book)} books')

    # Step 4: Import memos
    memo_count = 0
    for memo in memos_data:
        new_book_id = old_to_new_book.get(memo['book_id'])
        new_user_id = old_to_new_user.get(memo['user_id'].strip())
        if not new_book_id or not new_user_id:
            continue

        supabase.table('book_memos').insert({
            'book_id': new_book_id,
            'user_id': new_user_id,
            'content': memo['content'],
            'created_at': memo.get('created_at'),
            'updated_at': memo.get('updated_at'),
        }).execute()
        memo_count += 1

    print(f'Imported {memo_count} memos')

    # Step 5: Import compliments
    comp_count = 0
    for comp in compliments_data:
        new_book_id = old_to_new_book.get(comp['book_id'])
        new_user_id = old_to_new_user.get(comp['user_id'].strip())
        if not new_book_id or not new_user_id:
            continue

        supabase.table('book_compliments').insert({
            'book_id': new_book_id,
            'from_user_id': new_user_id,
            'compliment': comp['compliment'],
            'created_at': comp.get('created_at'),
        }).execute()
        comp_count += 1

    print(f'Imported {comp_count} compliments')

    # Step 6: Import follows
    follow_count = 0
    for follow in follows_data:
        follower_id = old_to_new_user.get(follow['user_id'].strip())
        following_id = old_to_new_user.get(follow['following_user_id'].strip())
        if not follower_id or not following_id:
            continue

        try:
            supabase.table('follows').insert({
                'follower_id': follower_id,
                'following_id': following_id,
            }).execute()
            follow_count += 1
        except Exception:
            pass

    print(f'Imported {follow_count} follows')
    print('Migration complete!')


if __name__ == '__main__':
    data_dir = sys.argv[1] if len(sys.argv) > 1 else './migration_data'
    main(data_dir)
```

- [ ] **Step 3: Run the parser on the backup**

```bash
cd scripts
python3 parse_backup.py "/Users/aschung/Downloads/db_cluster-06-05-2024@09-51-27.backup (1)" ./migration_data
```

Verify JSONL files are created with correct data.

- [ ] **Step 4: Commit**

```bash
git add scripts/
git commit -m "feat: add data migration scripts (SQL backup parser + Supabase importer)"
```

---

## Task 12: Final Integration & Cleanup

**Files:**
- Delete: `lib/core/` (empty directory after controllers removed)
- Modify: `lib/main.dart` (final version)
- Delete: `lib/helpers/utils.dart` (if still exists and unused)
- Delete: `lib/helpers/url_launcher.dart` (if unused after Kakao removal)

- [ ] **Step 1: Remove empty directories and unused files**

```bash
rm -rf lib/core/controllers/
rm -rf lib/core/services/
rm -rf lib/core/models/
rmdir lib/core/ 2>/dev/null || true
rm -f lib/helpers/utils.dart
```

Keep `lib/helpers/url_launcher.dart` if it's still used for sharing book URLs (check first).

- [ ] **Step 2: Regenerate Firebase config**

```bash
flutterfire configure
```

This generates a new `firebase_options.dart` for the project.

- [ ] **Step 3: Verify full build**

```bash
flutter pub get
flutter analyze
flutter build apk --debug
```

- [ ] **Step 4: Run the app and verify auth flow**

```bash
flutter run
```

Test:
1. App launches → splash → auth page
2. Sign in with Google → redirects → home page
3. Sign in with Apple → redirects → home page
4. If new user → onboarding (set username)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: final cleanup, remove dead code and empty directories"
```

---

## Task 13: Widget File Updates (Null Safety)

**Files:**
- Modify: All files in `lib/ui/widgets/`

All widget files need null safety fixes and GetX removal. The pattern:

- [ ] **Step 1: Update widget imports and types**

For each widget file in `lib/ui/widgets/`:
1. Remove `import 'package:get/get.dart';`
2. Replace `Get.find<XController>()` with accepting data via constructor params
3. Add `required` to constructor parameters that were previously nullable
4. Replace `Key? key` with `super.key`
5. Fix any `!` operator usage on potentially null values

- [ ] **Step 2: Update bottom sheet widgets**

Bottom sheets that call API methods need to accept callbacks or use `ref`:
- Convert to `ConsumerWidget` if they need Supabase access
- Accept `VoidCallback` or typed callbacks for actions

- [ ] **Step 3: Verify no GetX imports remain**

```bash
grep -r "package:get" lib/
```

Should return no results.

- [ ] **Step 4: Final flutter analyze**

```bash
flutter analyze
```

All issues should be resolved.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix: migrate all widgets to null safety, remove remaining GetX usage"
```
