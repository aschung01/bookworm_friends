# App identity

Recorded 2026-08-20, when the app was renamed from Bookworm Friends to Libstack.

The rename touched the **display name** only. Every **identity string** (bundle IDs,
Firebase project, OAuth callback scheme, Dart package name) still says `bookworm`,
and most of it has to stay that way. That mismatch is deliberate. This file exists so
nobody "tidies" it up and breaks the live app.

## Display name — renamed to Libstack

Users see this. Safe to change at any time.

| Surface                   | Where                                                                                                                |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| In-app title (`appTitle`) | `lib/l10n/app_en.arb`, `lib/l10n/app_ko.arb`                                                                         |
| iOS launcher              | `ios/Runner/Info.plist` (fallback), `ios/Runner/en.lproj/InfoPlist.strings`, `ios/Runner/ko.lproj/InfoPlist.strings` |
| Android launcher          | `android/app/src/main/res/values/strings.xml`, `values-ko/strings.xml`                                               |
| macOS                     | `macos/Runner/Info.plist`, `macos/Runner/en.lproj/InfoPlist.strings`, `macos/Runner/ko.lproj/InfoPlist.strings`      |

The `.lproj` / `values-ko` overrides take precedence over the plist fallbacks, so a
rename that only edits `Info.plist` will appear to do nothing. Change both.

Korean is `Libstack`, not a transliteration. It is a coined brand name, so it stays in
Latin script the way Notion and Slack do in the Korean stores. Consequence: the `-ko`
overrides now hold the same string as English and are pure redundancy. They were kept
rather than deleted because `ios/Runner/ko.lproj/InfoPlist.strings` still carries
`NSPhotoLibraryUsageDescription`, and dropping the macOS one risks a dangling Xcode
reference. `책벌레 친구들` is no longer in the app; it is still a good App Store
subtitle for the KO locale if the category signal is wanted there.

`macos/Runner/Configs/AppInfo.xcconfig` sets `PRODUCT_NAME = bookworm_friends` on
purpose — it drives `CFBundleName` and the built `.app` filename, not the user-facing
label. Leave it.

## Identity strings — frozen, and why

| Thing                                 | Value                                              | Status                         |
| ------------------------------------- | -------------------------------------------------- | ------------------------------ |
| iOS bundle ID                         | `com.unicorn.bookwormFriends`                      | **Permanently frozen**         |
| Android `applicationId` / `namespace` | `com.unicorn.bookworm_friends`                     | Change on Play re-registration |
| Firebase project                      | `bookworm-friends-notification`                    | **Permanently frozen**         |
| iOS URL scheme                        | `bookworm-friends`                                 | Frozen by preference           |
| Dart package                          | `bookworm_friends` (`pubspec.yaml` + ~130 imports) | Cosmetic, unrenamed            |

**iOS bundle ID.** The app is live on the App Store under this ID, and
`ios/Runner/GoogleService-Info.plist` is registered against it. Changing a bundle ID
does not rename an app; it creates a brand-new App Store listing and abandons every
install, review, and ranking signal. X still ships as `com.atebits.Tweetie2`. Never
change this.

> **Verified 2026-08-30** against Apple's lookup API, because two plan documents claimed
> the opposite ("pulled years ago") and the invite landing page's CTA depended on the
> answer. Live: `trackId` **1643321634**, 책벌레 친구들, **v1.0.6, last updated
> 2022-09-24**, 2 ratings, KR storefront, free. Both plans are corrected in place.
>
> Two caveats this turned up, neither of which changes the rule above:
>
> - **The shipped binary predates the Supabase migration.** It talks to the defunct
>   Django/Amplify backend; `pubspec.yaml` is at `1.1.0+1`. Anything that sends a new
>   user to the store — the invite landing page in particular — is sending them to an app
>   that cannot sign in. See `specs/2026-08-30-invite-landing-design.md`.
> - **The "installs, reviews, ranking" argument is weak on the numbers.** Two ratings is
>   not a ranking signal worth protecting, and the plans were right to treat the corpus as
>   dormant. The bundle ID should still never change — `GoogleService-Info.plist`, the
>   Supabase redirect allowlist, and the Google and Kakao consoles are all registered
>   against it, and that is reason enough on its own.

**Firebase project ID.** GCP project IDs are immutable. Invisible to users. Nothing to
decide here.

**iOS URL scheme.** This is the OAuth callback consumed by `flutter_web_auth` (see the
`flutter_web_auth` intent filter in `android/app/src/main/AndroidManifest.xml`).
Renaming it means updating the Supabase redirect allowlist plus the Google and Kakao
consoles, for zero user-visible benefit.

**Dart package name.** Renaming `bookworm_friends` to `libstack` is a mechanical
find-and-replace across `pubspec.yaml` and ~130 `package:bookworm_friends/...` imports
in `lib/` and `test/`. Entirely invisible to users. Not done yet; do it in one isolated
commit if at all, never mixed with feature work.

## Android: change the applicationId on re-registration

The Play listing is gone — the Google developer account was closed for inactivity. That
removes the reason iOS is frozen: there are no installs, reviews, or ranking left to
protect. Android is a clean slate.

Unverified but likely: `com.unicorn.bookworm_friends` may not be reusable at all. Play
reserves published package names permanently, and that generally holds even for the
original developer after an app is deleted or an account closed. **Confirm this before
planning around it.**

It was left unchanged because there is no account to publish to, so there is no
deadline, and flipping it today would strand a pile of unverifiable config. When a new
account exists, change it then and do all of this in one pass:

1. `applicationId` and `namespace` in `android/app/build.gradle` (lines ~17 and ~35).
2. New Firebase Android app → new `android/app/google-services.json`. The current one
   is pinned to `"package_name": "com.unicorn.bookworm_friends"`.
3. Regenerate `lib/firebase_options.dart`.
4. New Google Sign-In OAuth client — bound to package name **and** signing SHA-1.
5. Re-register the Kakao Android platform — package name **and** keyhash.
6. Update Supabase redirect URLs.

Suggested new ID: `app.libstack` (reverse-DNS of `libstack.app`, which we own) or
`com.unicorn.libstack` to stay consistent with the iOS prefix.

**Check first whether the account is recoverable.** Closure for inactivity is a
different category from termination for a policy violation and may be appealable. If
the account and its listing come back, Android flips to frozen exactly like iOS, and
none of the above should happen.

## Known cosmetic leftovers

Neither is a bug. Both are pre-existing Flutter defaults, and both are self-consistent,
so nothing is broken.

- **macOS is on the `com.example` placeholder.** `macos/Runner/Configs/AppInfo.xcconfig`
  (`PRODUCT_BUNDLE_IDENTIFIER`), `macos/Runner/GoogleService-Info.plist` (`BUNDLE_ID`),
  and `lib/firebase_options.dart` all agree on `com.example.bookwormFriends` — meaning
  it is registered in Firebase as a real app under the placeholder name. Only matters if
  the macOS build is ever distributed. Fixing it requires a Firebase console change too,
  so do not edit the xcconfig alone.
- **`MainActivity.kt` package does not match its directory.** It declares
  `package com.unicorn.bookworm_friends` while living at
  `android/app/src/main/kotlin/com/example/bookworm_friends/`. Kotlin does not require
  the two to agree, so it compiles. Tidy it during the Android ID change, not before.
