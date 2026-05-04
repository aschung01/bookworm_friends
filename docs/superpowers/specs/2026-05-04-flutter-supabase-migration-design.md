# Flutter + Supabase Migration Design

## Overview

Migrate a 2022 Flutter app (Dart 2.17, AWS Amplify, GetX, Dio) to latest Flutter (Dart 3) with Supabase for auth and database. Replace the defunct Django/Amplify backend entirely.

**Current state:** Flutter app with 71 Dart files, AWS Amplify (Cognito auth + REST API), Firebase (messaging/analytics/crashlytics), Kakao/Apple/Google login, GetX state management, Dio HTTP client. Backend is shut down.

**Target state:** Latest Flutter/Dart 3, Supabase (Auth + Postgres + Edge Functions), Riverpod state management, Apple + Google OAuth only, Firebase retained for push/analytics/crashlytics.

**Platforms:** iOS, Android, Web, macOS, Linux, Windows (all).

---

## 1. Supabase Schema

All tables in `public` schema. All PKs are UUID. FKs reference `auth.users.id` via `profiles.id`.

### profiles

| Column     | Type        | Notes                          |
|------------|-------------|--------------------------------|
| id         | uuid PK     | FK → auth.users.id             |
| username   | varchar(20) | unique, nullable (null until onboarding) |
| emoji      | varchar(6)  | nullable                       |
| is_private | boolean     | default false                  |
| fcm_token  | text        | nullable                       |
| created_at | timestamptz | default now()                  |
| updated_at | timestamptz | default now()                  |

### follows

| Column       | Type        | Notes                              |
|--------------|-------------|------------------------------------|
| follower_id  | uuid        | FK → profiles.id                   |
| following_id | uuid        | FK → profiles.id                   |
| created_at   | timestamptz | default now()                      |
|              |             | composite PK (follower_id, following_id) |

### shelves

| Column     | Type        | Notes                  |
|------------|-------------|------------------------|
| id         | uuid PK     | default gen_random_uuid() |
| user_id    | uuid        | FK → profiles.id       |
| name       | varchar(15) | not null               |
| position   | int         | not null (ordering)    |
| created_at | timestamptz | default now()          |

### books

| Column      | Type        | Notes                             |
|-------------|-------------|-----------------------------------|
| id          | uuid PK     | default gen_random_uuid()         |
| user_id     | uuid        | FK → profiles.id                  |
| shelf_id    | uuid        | FK → shelves.id                   |
| isbn        | varchar(13) | not null                          |
| title       | varchar(100)| not null                          |
| thumbnail   | text        | not null                          |
| status      | smallint    | 0=to-read, 1=reading, 2=finished |
| position    | int         | ordering within shelf             |
| rating      | real        | nullable                          |
| start_date  | date        | nullable                          |
| finish_date | date        | nullable                          |
| created_at  | timestamptz | default now()                     |

### book_memos

| Column     | Type        | Notes                        |
|------------|-------------|------------------------------|
| id         | uuid PK     | default gen_random_uuid()    |
| book_id    | uuid        | FK → books.id ON DELETE CASCADE |
| user_id    | uuid        | FK → profiles.id             |
| content    | text        | not null                     |
| created_at | timestamptz | default now()                |
| updated_at | timestamptz | default now()                |

### book_compliments

| Column       | Type        | Notes                        |
|--------------|-------------|------------------------------|
| id           | uuid PK     | default gen_random_uuid()    |
| book_id      | uuid        | FK → books.id ON DELETE CASCADE |
| from_user_id | uuid        | FK → profiles.id             |
| compliment   | varchar(6)  | emoji                        |
| created_at   | timestamptz | default now()                |

### Helper function

```sql
CREATE FUNCTION is_profile_visible(target_user_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = target_user_id
    AND (is_private = false OR id = auth.uid()
         OR id IN (SELECT following_id FROM follows WHERE follower_id = auth.uid()))
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;
```

---

## 2. Row Level Security

All tables have RLS enabled.

### profiles
- SELECT: `is_private = false OR id = auth.uid() OR id IN (SELECT following_id FROM follows WHERE follower_id = auth.uid())`
- INSERT: `id = auth.uid()`
- UPDATE: `id = auth.uid()`

### follows
- SELECT: `true`
- INSERT: `follower_id = auth.uid()`
- DELETE: `follower_id = auth.uid()`

### shelves
- ALL (owner): `user_id = auth.uid()`
- SELECT (others): `is_profile_visible(user_id)`

### books
- ALL (owner): `user_id = auth.uid()`
- SELECT (others): `is_profile_visible(user_id)`

### book_memos
- ALL (owner): `user_id = auth.uid()`
- SELECT (others): `is_profile_visible(user_id)`

### book_compliments
- INSERT: `from_user_id = auth.uid()`
- SELECT: `book_id IN (SELECT id FROM books WHERE user_id = auth.uid()) OR from_user_id = auth.uid()`
- DELETE: `from_user_id = auth.uid()`

---

## 3. Auth Flow

**Providers:** Apple + Google (native Supabase OAuth).

**Sign-up/sign-in:**
1. User taps Apple or Google button
2. `supabase_flutter` handles OAuth redirect (native deep link on mobile, redirect on web)
3. First sign-in: Supabase creates `auth.users` row
4. Database trigger creates `profiles` row with `id = auth.users.id`, empty username
5. App detects empty username → routes to onboarding (pick username + emoji)
6. Subsequent launches: session restored automatically by Supabase SDK

**Trigger:**
```sql
CREATE FUNCTION handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id) VALUES (NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();
```

**Account deletion:** Edge Function calls `supabase.auth.admin.deleteUser()`. CASCADE on FKs handles data cleanup.

---

## 4. Flutter Architecture

### Upgrade
- Dart SDK: `^3.0.0`
- Flutter: latest stable (3.32+)
- Full null safety migration

### Dependency changes

**Remove:**
- amplify_flutter, amplify_auth_cognito, amplify_api
- amazon_cognito_identity_dart_2
- dio (replaced by Supabase client)
- flutter_inappwebview (OAuth handled natively)
- kakao_flutter_sdk
- get (GetX)
- uni_links (replaced by app_links)

**Add:**
- supabase_flutter
- flutter_riverpod
- app_links

**Keep (upgrade to latest):**
- firebase_core, firebase_messaging, firebase_analytics, firebase_crashlytics
- flutter_secure_storage
- flutter_easyloading, shimmer, animated_text_kit, phosphor_flutter
- url_launcher, package_info_plus, in_app_review, app_tracking_transparency
- flutter_local_notifications, flutter_svg

### File structure changes

**Delete:**
- `amplify/` directory
- `lib/core/services/amplify_service.dart`
- `lib/core/services/kakao_service.dart`
- `lib/core/services/api_service.dart`
- `lib/core/services/library_api_service.dart`
- `lib/core/services/user_api_service.dart`
- `lib/helpers/dio_auth_interceptor.dart`
- `lib/helpers/parse_jwt.dart`
- `amplifyconfiguration.dart`

**New Riverpod providers:**
- `lib/providers/auth_provider.dart` — auth state, sign-in/out
- `lib/providers/library_provider.dart` — shelves, books, memos
- `lib/providers/user_provider.dart` — profile, follows
- `lib/providers/book_details_provider.dart` — book detail + compliments

### Data access pattern

Replace REST API calls with direct Supabase client queries:
```dart
// Before (Dio + REST):
var res = await ApiService.get('/library/', null);

// After (Supabase):
final res = await supabase.from('shelves').select('*, books(*)').eq('user_id', userId);
```

---

## 5. Push Notifications

Firebase stays for FCM, analytics, crashlytics.

### Notification triggers

| Event          | Mechanism                              | Recipient   |
|----------------|----------------------------------------|-------------|
| New compliment | DB webhook on book_compliments INSERT  | Book owner  |
| New follower   | DB webhook on follows INSERT           | Followed user |
| Poke           | Direct Edge Function call (RPC)        | Target user |

### Implementation
- Database webhooks trigger Supabase Edge Functions
- Edge Functions read target user's `fcm_token` from `profiles`
- Send push via Firebase Cloud Messaging HTTP v1 API
- Poke is an RPC: `supabase.rpc('poke_user', {'target_username': ...})`

### Client side
- `firebase_messaging` + `flutter_local_notifications` unchanged
- On app launch: get FCM token → update `profiles.fcm_token`

---

## 6. Data Migration

### Approach
Parse the existing SQL backup file directly (no local Postgres needed), extract table data into JSONL, then import into Supabase via admin API.

### Script 1: SQL backup → JSONL
- Parse `COPY ... FROM stdin` blocks from the backup file
- Output one `.jsonl` file per table: `users_user.jsonl`, `shelf.jsonl`, `book.jsonl`, `book_memo.jsonl`, `book_compliment.jsonl`, `users_following_users.jsonl`, `user_details_static.jsonl`

### Script 2: JSONL → Supabase
- Create Supabase auth users via admin API (one per active, non-resigned `users_user` row)
- Build UUID mapping: old `char(32)` → new Supabase auth UUID
- Insert mapped data into new schema tables

### Data mapping

| Old table              | → New table      | Notes                              |
|------------------------|------------------|------------------------------------|
| users_user + user_details_static | profiles | username, emoji, is_private        |
| shelf                  | shelves          | order → position                   |
| book                   | books            | map user_id + shelf_id             |
| book_memo              | book_memos       | map user_id + book_id              |
| book_compliment        | book_compliments | user_id → from_user_id, map book_id |
| users_following_users  | follows          | map both user_ids                  |

### Caveat
Users must re-authenticate with Apple or Google (new auth system). Kakao-only users cannot recover automatically.
