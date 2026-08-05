# bookworm_friends

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

## Localization

UI strings live in `lib/l10n/app_en.arb` (English) and `lib/l10n/app_ko.arb` (Korean). The app follows the device locale. After editing ARB files, run `flutter gen-l10n`. Generated `lib/l10n/app_localizations*.dart` files are gitignored.

## Tests

```bash
flutter test
```
