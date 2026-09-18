# Libstack

A social reading tracker. Flutter app backed by Supabase (Postgres + Auth + Edge Functions) with Riverpod state management, Firebase push notifications, and book search via Kakao (Korean) / Google Books + Open Library (international).

## Setup

### 1. Build-time secrets (`env.json`)

API keys are injected at build time and are **not** committed. Create `env.json` in the project root (it's gitignored):

```json
{
  "GOOGLE_BOOKS_API_KEY": "your-google-books-key",
  "KAKAO_REST_API_KEY": "your-kakao-rest-key"
}
```

- `GOOGLE_BOOKS_API_KEY` — optional. If omitted, Google Books runs keyless (low quota) and falls back to Open Library.
- `KAKAO_REST_API_KEY` — required for Korean book search.

### 2. Run / build

Use the helper scripts so the keys are always injected:

```bash
./run.sh                      # flutter run with env.json
./run.sh -d "iPhone 17 Pro"   # target a specific device
./build.sh ios --release      # release build with env.json
./build.sh apk --release
```

Running plain `flutter run` (without `--dart-define-from-file=env.json`) will build with empty keys, silently degrading book search.

### 3. Ship to TestFlight

```bash
# Bump `version:` in pubspec.yaml first -- TestFlight rejects a build number
# it has already seen. e.g. 1.1.0+12 -> 1.1.0+13
./release_ios.sh              # archive, sign, upload
./release_ios.sh --no-upload  # stop after producing the IPA
```

`pubspec.yaml` is the single source of truth for the version: `ios/Runner/Info.plist`
reads `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`.

This needs `ios/asc.json` (gitignored) holding the App Store Connect API key
details, alongside the `.p8` it points at:

```json
{
  "keyId": "XXXXXXXXXX",
  "issuerId": "00000000-0000-0000-0000-000000000000",
  "keyPath": "~/private_keys/AuthKey_XXXXXXXXXX.p8"
}
```

Use `./release_ios.sh` rather than `flutter build ipa` — the latter cannot sign for
distribution on this machine. See `AGENTS.md` for why.

## Localization

UI strings live in `lib/l10n/app_en.arb` (English) and `lib/l10n/app_ko.arb` (Korean). The app follows the device locale. After editing ARB files, run `flutter gen-l10n`. Generated `lib/l10n/app_localizations*.dart` files are gitignored.

## App identity

The app displays as **Libstack**, but its bundle IDs, Firebase project, and Dart package name still say `bookworm` — deliberately. The iOS bundle ID and Firebase project ID can never change, and the Android `applicationId` should only change when the Play account is re-registered.

Read `docs/APP_IDENTITY.md` before touching any bundle ID, `applicationId`, URL scheme, or the `pubspec.yaml` package name.

## Tests

```bash
flutter test
```
