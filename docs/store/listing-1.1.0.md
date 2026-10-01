# App Store listing draft — 1.1.0

**Status: copy is PUBLISHED to both locales. Screenshots and the build are not.**

| Field              | State                                                                |
| ------------------ | -------------------------------------------------------------------- |
| `copyright`        | ✅ `2026 Andrew Chung`                                               |
| `usesIdfa`         | ✅ `false` — corrected, see Finding 3                                |
| `en-US` locale     | ✅ published — `Libstack: Reading Tracker`, was holding Korean       |
| `ko` locale        | ✅ published — 2022 copy replaced                                    |
| Age rating         | ✅ answered                                                          |
| Privacy Policy URL | ✅ `https://libstack.app/privacy` on both locales                    |
| Support URL        | ✅ `https://libstack.app/support` on both locales                    |
| Reviewer contact   | ✅ Andrew Chung — demo account `test@apple.com`, seeded and verified |
| Review notes       | ✅ published, 2963 chars                                             |
| Apple sign-in      | ✅ **works, and links to the 2022 account — see Finding 1**          |
| Screenshots        | ✅ 8 iPhone + 4 iPad, both locales, 2022 sets deleted                |
| Build              | ✅ **+15 attached** — the first build with email/password auth       |
| `releaseType`      | ⚠️ `AFTER_APPROVAL` — decide, `MANUAL` may suit a resurrection       |

**The build is the live blocker.** `+14` uploaded 2026-09-26 21:57 and is `VALID`, but every file
in the Sign in with Apple button rebuild (Finding 6) was written 2026-09-27 12:42–13:35 — the day
after — so the compliant button is in no uploaded build. Ship `+15` before attaching anything.
`scripts/asc_version.py` lists the builds and attaches one:

```bash
.venv/bin/python scripts/asc_version.py                      # report, incl. builds
.venv/bin/python scripts/asc_version.py --attach-build 15
```

Everything above is reachable from `scripts/asc_version.py`, which reads this file as
the source of truth for the copy — so **edit the fields below and re-run, rather than editing
in the web UI**, or the two drift:

```bash
.venv/bin/python scripts/asc_version.py                      # report only
.venv/bin/python scripts/asc_version.py --set-review-details
.venv/bin/python scripts/asc_version.py --publish-copy
```

The 2022 values it would overwrite are preserved in
`docs/store/asc-2022-listing-snapshot.json`, captured with `--snapshot` before any write.
Apple keeps no edit history for localizations and the API will not hand an overwritten value
back, so that file is the only copy of the original Korean description and keywords.
**The demo-account password in it is redacted** — the live record held a real 15-character
one, and a snapshot is a plain file under `docs/`.

Version `1.1.0` = `PREPARE_FOR_SUBMISSION`, id `31f662f9-da17-48fc-a94f-de1d1e331d7a`.
Character counts verified by `scripts/check_listing_limits.py`.

---

## Findings

### Finding 1 — old libraries do come back, for 73 of 136 users. Your answer to this one was half right.

**The mechanism is proven on this project, not assumed.** Supabase links a new OAuth identity to
an existing user when the provider returns a matching **confirmed** email. Two accounts demonstrate
it across a four-year gap:

| Account                 | User row created | Google identity created | Gap       | Books kept |
| ----------------------- | ---------------- | ----------------------- | --------- | ---------- |
| `aschung1005@gmail.com` | 2022-08-24       | 2026-08-10              | 1447 days | 75         |
| `achung20@gmail.com`    | 2022-08-28       | 2026-05-06              | 1347 days | 6          |

All 136 migrated users have a confirmed email, and 136 profiles sit behind them holding 473 books.
So the libraries are there. **Reachability depends entirely on which email the migration stored**,
and that splits the user base three ways:

| Route                                             | Users  | Books   | Verdict                                              |
| ------------------------------------------------- | ------ | ------- | ---------------------------------------------------- |
| `gmail.com` → Google                              | 52     | 195     | ✅ Works. Proven twice above.                        |
| `privaterelay.appleid.com` + `icloud.com` → Apple | 21     | 86      | ⚠️ Mechanism proven. **Relay persistence unproven.** |
| naver / kakao / nate / hanmail / daum / other     | **63** | **192** | ❌ No route exists.                                  |

**63 users holding 192 books — 46% of the people and 41% of the books — cannot get back in.** The
app offers only Apple and Google, and no Korean portal address can be presented through either.

Two things I checked because they would have changed the answer, and they did:

- **Apple sign-in now works, and it linked rather than duplicated. ✅ Proven 2026-09-28.** Signing in
  with Apple against an Apple ID whose address matches an existing confirmed email attached a second
  identity to the **existing 2022 user** instead of opening a new one:

  ```
  user aschung1005@gmail.com   created 2022-08-24, 75 books
    raw_app_meta_data {"provider":"google","providers":["google","apple"]}
    identity google  2026-08-10
    identity apple   2026-09-28   email_verified true, name "Andrew Chung"
  ```

  Totals unchanged either side of it — 137 users, 137 profiles, 473 books — so nothing was
  duplicated. This is the exact email-matching path the 21 Apple-route users depend on, and it also
  disproves the theory that the app was failing to request the `email` scope: Apple returned both
  `email` and `name`, so `auth_provider.dart` needs no change.

- **What is still unproven is narrower than it was: whether Apple hands a _returning 2022 user_ their
  original `@privaterelay.appleid.com` address.** Relay addresses are scoped to the primary App ID
  and the bundle ID has not changed, so it should hold, but only an Apple ID that actually authorized
  this app in 2022 can demonstrate it and none is available to test with. An earlier test that came
  back with **no email at all** is fully explained by Apple returning `email` only on the _first_
  authorization of an App ID — that Apple ID had authorized before — and not by a scope fault.
  It produced a null-email orphan account, since deleted.

- **There is no password route.** Every migrated row has `encrypted_password = ''` — an empty
  string, not a hash. (`count()` counts empty strings, which is what made this look like "all 137
  have passwords" on first pass.) Only the demo account has a real bcrypt hash. So adding
  email+password sign-in would recover **nobody**; it would take an emailed one-time code.

**Two recommendations, in priority order:**

1. **Sign in with Apple was broken and is now fixed. ✅** It failed on 2026-09-21 with **"Provider
   not enabled"** — the Apple provider had never been switched on in Supabase Auth, which is why
   `auth.identities` held zero Apple rows. Setup is written up in `docs/apple-sign-in.md`: both the
   App ID and the Services ID (`com.bookwormFriends.signin`) already existed from 2022 with
   `APPLE_ID_AUTH`, so what was left was the Services ID's return URL, a freshly minted client
   secret (`scripts/apple_client_secret.py`, **expires 2027-03-25**) and the Client IDs ordering
   trap. It was one step from being the rejection, because the review notes point App Review at
   Sign in with Apple as their only way into the app.

   The gate this section set — _do not submit until a real Apple sign-in has produced an identity
   row here_ — is now met, and the identity landed on the **existing** account rather than a new
   one, which also answers the question about the Services ID being grouped under the primary App
   ID. Re-check with `select provider, count(*) from auth.identities group by 1;` (`apple:1,
email:1, google:2`).

2. **Kakao sign-in recovers the 63, and is a 1.1.1 item, not a blocker.** Kakao is a built-in
   Supabase provider, and those naver/nate/hanmail/daum addresses are almost certainly the _Kakao
   account_ emails the old app received — which is exactly what auto-linking matches on. Note that
   `kakaoRestApiKey` in the build config is **not** a head start: it is a Book Search REST key, and
   Kakao Login needs its own app registration and redirect URI. Shipping 1.1.0 without it is fine
   as long as the Korean What's New does not promise those users their shelves back — which the
   copy below no longer does.

### Finding 2 — the demo credentials could not work. ✅ Fixed, by building the screen.

**As written, this finding said not to supply credentials at all, and it was right at the time.**
`auth_page.dart` rendered exactly two buttons — `continueWithApple` and `continueWithGoogle` — and
`auth_provider.dart` exposed only `signInWithGoogle`, `signInWithApple` and `signOut`. There was no
`signInWithPassword` anywhere in `lib/`, so a reviewer handed a username and password would have had
nowhere to type them, which is a Guideline 2.1 rejection. The recommendation was
`demoAccountRequired = false` plus an explanation, and it noted that TestFlight beta review had not
caught the gap only because beta review frequently does not attempt sign-in at all.

**What changed is the premise.** `feat/email-password-auth` merged on 2026-09-30: `email_auth_page.dart`,
`new_password_page.dart`, `password_recovery_listener.dart`, `resetPasswordForEmail`, and about 960
lines of tests. There is now an email field, a password field, sign-up and reset, and Supabase SMTP
is configured and verified end to end.

The finding's own counter-argument was that building such a screen "for review only" costs a screen,
two locales, tests and an SMTP configuration, that Apple dislikes sign-in surfaces that exist only
for them, and that it would recover zero returning users. The first clause was an accurate estimate
of the cost. The other two do not apply to what was built: the screen is for **everyone**, which is
why it is advertised in both locales' What's New, and it recovers the 63 users Finding 1 could not
reach — every migrated row has a confirmed email and `encrypted_password = ''`, which means "no
password set" rather than "no account", so a reset reaches them.

**So credentials are now the lower-risk path**, because 2.1 rejections come from credentials that do
not work rather than from offering them. `test@apple.com` is verified against
`/auth/v1/token?grant_type=password` (HTTP 200, provider `email`) and seeded with 44 books across 3
shelves, a year of reading days, and one friendship — so the shelf, the Library Card, the streak and
the Friends tab all have content on first launch. `build/demo-account-revert.sql` undoes the seed.

**Re-verify the pair before each submission rather than trusting that it worked once.** The 2022
record pointed App Review at a dead `aschung01@snu.ac.kr`, which is precisely the failure this field
is capable of.

### Finding 3 — `usesIdfa` was a false declaration. ✅ Fixed.

You said yes to IDFA and I applied it without checking the binary. Checking it now:

- No `AdSupport.framework`, no `ASIdentifierManager`, no `GoogleAppMeasurementIdentitySupport`
  anywhere in `ios/`. Since Firebase 8, Analytics does **not** touch the IDFA unless that last
  module is explicitly added. It is not.
- No ad SDK and no attribution SDK in `pubspec.yaml`. No IAP either.
- `NSUserTrackingUsageDescription` reads "Used to collect crash, performance data" — and crash and
  performance diagnostics are not "tracking" under Apple's definition, which requires linking user
  data to third-party data for ads or a data broker.

So the app shows the ATT prompt to ask for a permission it cannot exercise. Declaring `usesIdfa`
means ASC asks which of three purposes apply — serve ads, attribute installs, limit ad fraud — and
**none of them do.** That is an invitation for a reviewer question at best.

**Applied on 2026-09-21, before build 13 was uploaded:**

1. ✅ `usesIdfa = false` in ASC, via `scripts/asc_version.py --set-idfa false`.
2. ✅ The `AppTrackingTransparency.requestTrackingAuthorization()` block deleted from
   `main.dart`, along with the now-unused `dart:io` and plugin imports; the whole `initState`
   override went with it. `app_tracking_transparency` dropped from `pubspec.yaml`.
   `NSUserTrackingUsageDescription` removed from `Info.plist`. A comment at each of the three
   sites records why, so nobody re-adds the prompt without an SDK that reads the identifier.
   1710 tests pass, `flutter analyze` clean in `lib/` + `test/`, `plutil -lint` OK.
3. ❌ **Still outstanding, and not in this repo:** the privacy policy sentence that says
   permission is asked "before any of this is associated with an advertising identifier."
   Nothing is, and there is no longer a prompt. That sentence now describes behaviour the app
   does not have.

Note `ios/Podfile.lock` still lists the pod. It is generated and regenerates on the next iOS
build, so it is not worth hand-editing — but do not be surprised to see it change in the diff
for build 13.

Side benefits: first launch no longer opens with a permission prompt nobody benefits from, and the
prompt has stopped photobombing screenshot captures.

### Finding 4 — the support page documents a feature that was removed

`libstack.app/support` tells readers that a web invite page "shows an **eight-character code** you
can type into the app by hand", and calls it "the reliable path when a link is opened inside a
messenger's own browser". `auth_page.dart` records that the typed-code screen was deleted — there is
now nothing anywhere in the app that accepts a code.

That is the exact failure the page presents as the fallback, and messenger in-app browsers are the
single most likely way a Korean user receives an invite link. Worth fixing on the site before
launch; it is a page edit, not an app change. Flagging rather than fixing since the website is not
in this repo.

### Finding 5 — the screenshots are safe now, and still have no captions

Eleven captures at exact required sizes (7 × iPhone 6.9" `1320×2868`, 4 × iPad 13" `2064×2752`),
**moved out of `build/shots/` and into the repo** at
`docs/store/screenshots/1.1.0/capture/{iphone69,ipad13}/`. 23 MB, which is nothing against a 1.0 GB
`.git`, and the alternative was leaving a day of simulator work one `flutter clean` from gone.
`capture/` is the raw device output; a caption pass writes a sibling `upload/`.

Still uncaptioned, and per the competitor read below every serious app in this category spends slot
1 on composed art rather than raw UI. Captions drafted at the end of this document.
`index.html` beside them is a generated contact sheet — all 11 at once, in store order, with the
defects below marked. Open it before deciding anything about captions.

#### They predate the reading streak, so some of them are wrong

Captured **2026-09-19**. The streak merged to main **2026-09-26 21:41** (`d147827`). Verified by
opening the frames, not inferred:

| Frame                            | What it draws                 | What ships now                                   |
| -------------------------------- | ----------------------------- | ------------------------------------------------ |
| `iphone69/01`, `02`, `ipad13/02` | bar flame in **rust**         | `kCandleFlame` **#F2A93F**, and a generated mark |
| `iphone69/03`, `ipad13/02`       | streak tile **unfilled grey** | filled warm/cool with a `StreakFlameMark`        |

The chip itself is in the captures — it predates this branch — so the drift is hue and glyph rather
than a missing control, which is exactly the kind of thing that survives a glance and fails a
side-by-side. Two further problems the sheet makes obvious and no test would:

- **The finished-books sheet is half-open across the bottom third of `01` and `02`**, showing
  "Books read 1", a single spine and a lot of white — in the two most valuable frames Apple shows.
- **The seeded data is "1d, best 1" and 1 book read this year.** That was survivable while the
  streak tile was grey furniture. It is the loudest object on the card now, so a screenshot
  advertising a streak feature would be advertising a one-day streak.

**So re-capture, and seed a real run first.** Captioning the current frames would composite text
onto obsolete pixels, and the iPad card needs its `CenteredContent` fix landed before its frame is
worth taking at all.

### Finding 6 — four 2022 values were still live in App Store Connect, and one was a rejection. ✅ Fixed.

These only surfaced once `scripts/asc_version.py` could read the record back. None of them are
visible from the copy draft, and all four would have shipped:

| Resource                     | Current value                                                                                                                              | Problem                                                                                                      |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `appInfoLocalizations` en-US | `백벌레 친구들 - 친구들과 함께하는 독서 기록`                                                                                              | **The en-US name and subtitle are in Korean.** Creating the locale copied the ko values.                     |
| `privacyPolicyUrl` (both)    | a 2022 `yellow-crow-b73.notion.site` page                                                                                                  | Superseded by `libstack.app/privacy`, which is current and far more thorough.                                |
| `supportUrl`                 | ko → a 2022 `bookwormfriends.notion.site` page; en-US → **null**                                                                           | Required for submission, and null in en-US.                                                                  |
| `appStoreReviewDetail`       | contact `정 순호` / `achung20@gmail.com` / `+8201081394632`, **`demoAccountName = aschung01@snu.ac.kr`** with `demoAccountRequired = true` | Points App Review at a dead 2022 account. This is the Guideline 2.1 rejection from Finding 2, already armed. |

The last row is the dangerous one. Finding 2 was about _not adding_ credentials; it turns out stale
ones were already there. `--set-review-details` blanks `demoAccountName` and
`demoAccountPassword` explicitly rather than omitting them, because a PATCH only touches the
attributes it names — omitting them would leave the dead account in place even with
`demoAccountRequired` false.

`--publish-copy` fixes the first three as a side effect: it writes `supportUrl` on every version
localization and `privacyPolicyUrl` on every app-info localization, and the en-US name and subtitle
come from the draft below.

Also worth a conscious decision: `releaseType` is `AFTER_APPROVAL`, so an approved build goes live
by itself. For a listing that has been dormant since 2022, `MANUAL` may be preferable.

---

## What the competition actually does

Re-run properly this time, with Flighty added. Every name and description below came from Apple's
own lookup API; every subtitle from the rendered storefront page; the caption notes are from
actually downloading and looking at each app's first two screenshots.

| App            | Name field                       | Chars  | Subtitle                         | Chars  | Sum /60 |
| -------------- | -------------------------------- | ------ | -------------------------------- | ------ | ------- |
| Goodreads      | `Goodreads: Book Tracker & More` | **30** | `Reviews, lists & reading goals` | **30** | **60**  |
| Duolingo       | `Duolingo: Language Lessons`     | 26     | `Languages, Math, Music & Chess` | **30** | 56      |
| Flighty        | `Flighty – Live Flight Tracker`  | 29     | `World's Fastest Delay Alerts`   | 28     | 57      |
| Fable          | `Fable: Track & Discuss Books`   | 28     | `A modern app for every reader`  | 29     | 57      |
| The StoryGraph | `StoryGraph: Reading Tracker`    | 27     | `Book recommendations and stats` | **30** | 57      |
| Basmo          | `Basmo.Reading Tracker,Book Log` | **30** | `Your AI ChatBook Assistant`     | 26     | 56      |
| Bookmory       | `Bookmory - reading tracker`     | 26     | `Track & Remember Your Books`    | 27     | 53      |
| Bookly         | `Bookly: Book Tracker`           | 20     | `Booktok Reading Log`            | 19     | **39**  |
| **Libstack**   | `Libstack: Reading Tracker`      | 25     | `Bookshelf, TBR & book journal`  | 29     | 54      |

Five things that changed or confirmed decisions here:

**1. Not one of the eight ships a bare brand name, and the strong ones near-max both fields.**
Goodreads runs exactly 30/30. Duolingo and StoryGraph both hit 30 on the subtitle. This settles the
open question: `Libstack: Reading Tracker` over bare `Libstack`.

**2. The strong ones never spend a character twice; the weak ones do.** Duolingo's name says
"Language Lessons", so its subtitle spends all 30 characters naming four _other_ subjects rather
than restating it. Bookly repeats "Book" across both halves **and** uses only 39 of 60 — a double
loss on the exact terms it needs. Bookmory repeats the track/tracker stem. Our pair shares no word,
which is the one thing our draft already had right.

**3. Screenshot slot 1 is a poster, not a screenshot.** Flighty, Fable, Goodreads and Basmo all
spend their most valuable frame on composed art with **zero app UI** — headline, illustration,
wordmark. Flighty draws its own Apple Design Award and App of the Year laurels into that frame,
because Apple only _serves_ a badge to Duolingo in this set. Our 11 captures are all raw device UI.

**4. The first three description lines are a funnel, not a feature sentence.** Flighty's are, in
order: third-party proof, one-line positioning (`The flight tracker your pilot uses.`), then
objection removal — `No account required.` / `No newsletters.` / `No ads.` Nothing above the fold
describes a feature. Compare Bookly's opener, which would fit any of the six trackers verbatim.
Flighty also ships two visible grammar errors and still won the ADA: structure beats polish. We have
no press quotes, but we _can_ run the objection-removal move honestly — free, no ads, no
subscription, nothing public — and the description below now leads with it.

**5. Promotional text is the real fold and three of eight use it.** It renders _above_ the
description and changes without review. StoryGraph's is the model: `NEW: Automatically sync your
Kobo reading progress with StoryGraph!` And on What's New, the gap is stark — Flighty writes release
notes as a mini launch page with `#` headers per feature; Goodreads writes "This update contains bug
fixes and improvements." For a listing that has been dead since 2022, that field is the first thing
a returning user reads.

Where we are actually different, and none of the eight has it: a physical shelf you arrange with
spines, a shareable library card, mutual-only friends, and borrow-via-Libby. Lead there, not on
"reading tracker with stats" — Bookmory and StoryGraph own that ground.

---

## en-US

### Name (limit 30)

```
Libstack: Reading Tracker
```

### Subtitle (limit 30)

```
Bookshelf, TBR & book journal
```

No word shared with the name. Pool gains `bookshelf`, `TBR`, `book`, `journal`. The 6 unspent
characters are deliberate — there is no seventh term worth forcing in.

### Promotional text (limit 170, editable without review)

```
Back after four years, rebuilt from scratch. Scan a barcode, shelve the book where you like, and watch the shelf fill up — then share your reading as a library card.
```

Aimed at the returning half of the audience for launch month, per observation 5. Swap it for a
feature line once the dormant users have cycled through.

### Keywords (limit 100)

```
streak,ISBN,barcode,stats,books read,shelf,library,Libby,friends,goals,habit,log,diary,spine
```

Excludes every word already in the name and subtitle, since Apple indexes all three as one pool.
`book tracker`, `book log`, `reading log` and `book stats` all remain reachable as assembled
phrases.

### Description (limit 4000)

```
A bookshelf you actually keep.

Free. No ads, no subscription, nothing to unlock. Your library is private until you hand someone a link.

Add a book by title, author or ISBN — or point your camera at the barcode on the back. Put it on a shelf you named yourself. Watch the shelf fill up.

A SHELF THAT LOOKS LIKE A SHELF
• Name your own shelves and move books between them
• Three ways to see one: covers face-out, spines lined up, or leaning
• Whatever you are reading leads every shelf, so you never lose your place

TRACK WHERE YOU ACTUALLY ARE
• Log progress by page (p.259 / 432) or by percent
• Stamp the days you read and build a streak
• Keep notes on any book — private to you, always

A LIBRARY CARD WORTH SHARING
Your reading becomes a card: books finished, days reading, your pace, your most-read author, your shelves. Share it as an image, or keep it to yourself.

READ ALONGSIDE FRIENDS
• See what your friends have open right now
• Visit their shelves
• Poke a friend who has gone quiet
• Invite by link — friendships are mutual, and only friends can see your library

OPEN IT WHERE YOU READ
Jump straight to a book in the app you read it in, or borrow it free from your local library through Libby.

Korean and English throughout. Light and dark. iPhone and iPad.
```

### What's New (limit 4000)

```
Libstack is a new name, and a new app underneath it.

Coming back from the old version? Sign in with the same Apple ID or Google account you used before, and in most cases your shelves are already waiting. If yours comes up empty, reach out and I will reconnect it by hand — nothing was deleted.

• Sign in with an email and password, Apple, or Google — whichever you prefer.
• Friends. Invite by link, see what your friends have open, visit their shelves, and poke the quiet ones. Friendships are mutual, and only friends can see your library.
• Reading progress by page or percent, with the days you read stamped into a streak.
• A Library Card that turns your reading into something worth sharing — books, days reading, pace, most-read author.
• Shelves you arrange yourself, in three views: covers, spines, or leaning.
• Notes on any book, private to you.
• Open a book in the app you read it in, or borrow it free from your library through Libby.
• Redesigned for iPad.
• Korean and English, light and dark.
```

The reconnect-by-hand line is there because of Finding 1: 21 users are reachable only through an
Apple relay address we have never once seen returned. If it does not hold, that sentence is the
difference between a bug report and a churned user.

**Softened 2026-09-28, after Apple sign-in was proven to link.** It used to promise "your shelves
_will_ be waiting"; it now says "in most cases". Counter-intuitively the softening came _with_ the
good news rather than instead of it: proving the mechanism also pinned down exactly who it has not
been proven for — the 20 Hide My Email users, whose original relay address no available Apple ID
can test. An unqualified promise was defensible while the whole question was open and is not once
the exception has a number on it.

---

## ko

### Name (limit 30)

```
책벌레 친구들 (Libstack): 독서 기록
```

### Subtitle (limit 30)

```
친구와 함께 만드는 독서 습관
```

> **Why the name carries both brands, and the subtitle carries neither.**
>
> This slot was `Libstack: 독서 기록` for a day, and that was a rebrand default rather than a
> decision — the reasoning below did not exist when it was published, which is what made it look
> arbitrary on review. Three jobs, done in 25 of 30 characters:
>
> - **`책벌레 친구들` leads**, because it is an exact-match name hit for the four years of recognition
>   this listing already has, in the storefront where **every existing user lives**. A name match
>   outranks a subtitle match, which is all the old subtitle could offer.
> - **`(Libstack)` resolves an icon mismatch**, and this is the reason the obvious
>   `책벌레 친구들: 독서 기록` was rejected. `ios/Runner/ko.lproj/InfoPlist.strings` pins
>   `CFBundleDisplayName = "Libstack"` — deliberately, since a `ko.lproj` exists and could have said
>   otherwise — so a Korean reader installs from this listing and gets an icon labelled `Libstack`.
>   Without the parenthetical that reads as having downloaded the wrong app.
> - **`독서 기록` stays** because it is the only term in the field with Korean search volume.
>   "Libstack" has none; nobody types it.
>
> **The truncation objection is disproven by this listing's own history.** 25 Korean characters is
> 35 half-widths of display space, which will truncate in search results — but the name Apple
> displayed here from 2022 to 2026 was `책벌레 친구들 - 친구들과 함께하는 독서 기록` at **43**. This is
> narrower than what shipped. It should cut around `책벌레 친구들 (Libstack)…`, which is the bridge
> message intact. And **truncation is display-only**: Apple indexes the whole string, so `독서 기록`
> keeps its ranking value even unseen.
>
> **So the subtitle stopped carrying `책벌레 친구들`.** Its documented job was preserving that
> recognition; the name does it now, and earlier. Keeping it in both would put the brand twice in
> the only two lines Apple shows — the same waste observation 2 raises about `독서 기록`, relocated
> onto the brand. It also retires the old note here, which offered to drop `독서 기록` from the name
> instead; that trade is moot now that the name has a reason to be long.
>
> **And it carries no keywords either**, on purpose. `독서기록`, `책장`, `서재`, `독서습관`, `완독`
> and `바코드` are all in the keywords field below, where a second copy earns nothing. So the
> subtitle persuades: `친구와 함께 만드는 독서 습관` is also the closest line to the 2022 subtitle
> (`친구와 함께 독서 습관 만들기`), which is continuity for a returning reader at no cost.
>
> The `함꼐하는` → `함께하는` fix that used to be flagged here (`ㅐ`/`ㅔ` transposed) is moot — that
> string is gone.

### Promotional text (limit 170, editable without review)

```
4년 만에 완전히 새로 만들었습니다. 바코드를 비추고 원하는 선반에 꽂으면 책장이 채워집니다. 읽은 기록은 공유할 수 있는 한 장의 도서 대출증이 됩니다. 무료이고, 광고도 구독도 없습니다.
```

This field was missing from the ko draft entirely, which would have left the highest-value text
position blank on the storefront where all 136 existing users are — see observation 5. It leads
with the four-year gap because that is the one thing a returning Korean user needs to hear, and
closes on free/no-ads because no competitor in the benchmark set is.

Deliberately **not** the `같은 계정으션 로그인하세요` recovery promise: per Finding 1, roughly half
the Korean audience signed up through Kakao and cannot log in yet. That caveat belongs in What's
New, where there is room to be honest about it, not in a 170-character hook.

### Keywords (limit 100)

```
독서기록,독서앱,책장,서재,독서습관,완독,책읽기,독서모임,바코드,ISBN,도서관,밀리의서재,리디
```

### Description (limit 4000)

```
계속 관리하게 되는 책장.

무료입니다. 광고도, 구독도, 잠겨 있는 기능도 없습니다. 내 서재는 링크를 건네기 전까지 아무에게도 보이지 않습니다.

제목이나 저자, ISBN으로 책을 찾거나, 책 뒤편의 바코드를 카메라로 비추기만 하세요. 직접 이름 붙인 선반에 꽂고, 선반이 채워지는 걸 지켜보세요.

책장처럼 보이는 책장
• 선반 이름을 직접 정하고, 책을 옮겨 가며 정리하세요
• 선반을 보는 방식 세 가지: 표지, 책등, 기대어 놓기
• 지금 읽는 책이 항상 선반 맨 앞에 서기 때문에 읽던 자리를 놓치지 않습니다

지금 어디까지 읽었는지
• 쪽수(p.259 / 432) 또는 퍼센트로 진도를 기록하세요
• 읽은 날을 도장처럼 남기면 연속 기록이 쌓입니다
• 책마다 남기는 메모는 언제나 나만 볼 수 있습니다

공유하고 싶어지는 도서 대출증
읽은 기록이 한 장의 카드가 됩니다. 완독한 책, 읽은 날수, 한 권에 걸리는 시간, 가장 많이 읽은 작가, 선반까지. 이미지로 공유하거나, 혼자 간직하세요.

친구와 함께 읽기
• 친구가 지금 펼쳐 둔 책을 확인하세요
• 친구의 서재에 방문하세요
• 조용해진 친구는 콕 찔러 주세요
• 링크로 초대하세요. 친구는 서로 수락해야 맺어지고, 서재는 친구에게만 보입니다

읽던 곳에서 이어 읽기
읽던 앱에서 바로 책을 열거나, Libby로 동네 도서관에서 무료로 대출하세요.

한국어와 영어를 모두 지원합니다. 라이트 모드와 다크 모드, iPhone과 iPad를 모두 지원합니다.
```

### What's New (limit 4000)

```
이름도 Libstack으로, 속도 새로워졌습니다.

예전 버전을 쓰셨다면: 그때 Google 또는 Apple 계정으로 가입하셨다면, 같은 계정으로 로그인해 보세요. 대부분 서재가 그대로 남아 있습니다. 혹시 비어 있으면 알려 주세요 — 직접 연결해 드리겠습니다.

• 이메일과 비밀번호, Apple, Google 중 원하는 방법으로 로그인하세요.
• 친구. 링크로 친구를 초대하고, 친구가 읽는 책을 확인하고, 친구의 서재를 둘러보고, 조용한 친구는 콕 찔러 보세요. 친구는 서로 수락해야 맺어지고, 서재는 친구에게만 보입니다.
• 쪽수나 퍼센트로 남기는 진도, 그리고 읽은 날이 쌓이는 연속 기록.
• 읽은 기록이 한 장의 카드가 되는 도서 대출증 — 완독한 책, 읽은 날수, 속도, 가장 많이 읽은 작가.
• 직접 정리하는 선반, 표지·책등·기대어 놓기 세 가지 보기.
• 책마다 남기는 나만의 메모.
• 읽던 앱에서 바로 열기, Libby로 도서관 무료 대출.
• iPad 화면에 맞게 새로 정리했습니다.
• 한국어와 영어, 라이트와 다크 모드.
```

This is the paragraph Finding 1 forced. 60 of the 63 unreachable users are on Korean portal
addresses, so on this storefront roughly half the returning audience cannot log in. Telling them
their shelf is intact and Kakao is coming is the honest version; the en-US text can stay optimistic
because 52 of its 73 reachable users are on Google.

---

## App Review notes

Set alongside these: `demoAccountRequired = true`, with `demoAccountName` /
`demoAccountPassword` supplying a real account. Reviewer contact is `Andrew Chung`,
`aschung1005@gmail.com`, `+1 628-688-9415`, held in `REVIEWER_CONTACT` in
`scripts/asc_version.py`. Apply the whole block with:

```bash
.venv/bin/python scripts/asc_version.py --set-review-details
```

> **This reverses Finding 2, and the reversal is a fact rather than a preference.** That
> finding said not to supply credentials, because `auth_page.dart` offered only Apple and
> Google and a reviewer handed a username and password would have had nowhere to type them —
> a Guideline 2.1 rejection. True at the time. `feat/email-password-auth` has since merged,
> so there is an email field, a password field, sign-up, and reset. Supplying working
> credentials is now the lower-risk path of the two: 2.1 rejections come from credentials
> that do not work, not from offering them.
>
> The account is `test@apple.com`, created 2026-09-29. Note the listing's own history here:
> the 2022 record pointed App Review at a **dead** `aschung01@snu.ac.kr`, which is the exact
> failure this field is capable of. Re-check the pair actually signs in before each
> submission rather than trusting that it did once.

### Notes (limit 4000)

```
A DEMO ACCOUNT IS PROVIDED, AND SIGN IN WITH APPLE ALSO WORKS.

The demo account in the fields above signs in on the first screen: tap "Continue with email", enter the address and password, then tap "Sign in". It already has 44 books across three shelves — five in progress, 17 finished — a year of reading days with a 17-day run, and one friend, so every feature below has something in it from the first launch.

If you would rather use your own account, tap "Continue with Apple" instead — Hide My Email works fine. Account creation is instant, with no payment and no personal details beyond what Apple returns. Either way you can delete the account from within the app when you are finished.

The app is free. No in-app purchases, no subscriptions, no advertising.

WHAT TO TRY.

1. SEARCH TAB — type any title, for example "Dune". Or tap the barcode button and scan the back cover of any physical book.
2. Tap a result, add it, and choose a shelf. It appears on the shelf on the Library tab.
3. Tap the book on the shelf to open it. Update progress logs where you are, by page number (p.259 / 432) or by percent.
4. The view switcher on the Library tab cycles three shelf views: covers face-out, spines lined up, and leaning. Books can be dragged between positions.
5. LIBRARY CARD, at the bottom of the Library tab — it summarises books finished, days read, reading pace and most-read author, and the share button renders it as an image for the system share sheet, Instagram Stories or Photos.
6. READING STREAK — tap the flame in the bar at the top of the Library tab. The demo account's current run is 17 days, drawn as a week row and a month grid you can page back through. "I read today" records the day; recording a day that is not yet logged plays a short celebration.

FRIENDS ARE MUTUAL AND INVITE-ONLY. There is no public profile, no feed, no way to search for or browse strangers, and no direct messaging between users. A connection exists only after both people accept an invite link, and a library is readable only between mutually connected accounts. This is enforced by row-level security in the database, not in the client. The only user-to-user content is an emoji reaction on a book. Notes a reader writes on a book are private to its author and are never visible to friends.

The demo account already has one friend, so the Friends tab is populated — tap the friend to visit their shelves. To make a new connection yourself you need a second account: Friends tab, Invite, share the link, then open that link on a second device signed in with a different account and accept it. Invite links expire after 48 hours.

ACCOUNT DELETION. Settings, then Delete account. One confirmation, then it is immediate and irreversible: the authentication user, profile, handle, photo, every book and shelf, notes, reading days and friendships are all removed server-side by an edge function. This satisfies Guideline 5.1.1(v).

BOOK DATA. Titles, authors, page counts and cover images come from the Google Books, Kakao and Open Library catalogues. Libstack hosts no book text or audio. "Where to read" on a book links out to Apple Books, Kindle, Google Play Books, or a free public-library loan through Libby, and opening one leaves the app.

DIAGNOSTICS. The app collects crash and performance data through Firebase Crashlytics and Analytics. It does not use the Advertising Identifier and shows no advertising.

The app supports iPhone and iPad, in English and Korean, in light and dark appearance.
```

⚠️ The DIAGNOSTICS paragraph is only true once Finding 3 is applied. If `usesIdfa` stays `true`,
delete that paragraph — do not submit a contradiction between the notes and the declaration.

---

## Screenshot captions

Per observation 4, the requirement is a **system**, not seven decorated images: one position, one
type treatment, one length band across every frame. Apple crops hard in search results and shows
only the first three, so those three have to carry what it is, why it is different, and the payoff.

Proposed order and captions — 4–6 words, set in Gowun Batang Bold to match the in-app
`hero`/`title` token. **Ink is `primaryText`, not brand green**: `brandText` at 10% of frame
width on near-white paper is a wash, and the headline is the one thing in the frame that has
to survive being served as a thumbnail.

| #   | Capture             | Headline                      | Supporting line                      |
| --- | ------------------- | ----------------------------- | ------------------------------------ |
| 1   | `01-library-covers` | A bookshelf you actually keep | Free. No ads, no subscription.       |
| 2   | `02-library-spines` | Covers, spines, or leaning    | Drag them into the order you want.   |
| 3   | `03-library-card`   | Your reading becomes a card   | Books, days, pace, most-read author. |
| 4   | `05-book-details`   | Log the page you're on        | By page or percent, in one drag.     |
| 5   | `07-share-card`     | Made to be handed over        | Nothing is public until you send it. |
| 6   | `04-friends`        | Read alongside your friends   | See what they have open right now.   |
| 7   | `06-search-results` | Scan the barcode to add       | Or search by title, author, or ISBN. |

Two changes from the first draft of this table, both for the same reason — observation 2
applied one level down, since the strong listings never spend a character twice:

- **Slot 1's supporting line is the objection-removal move, not `Covers, spines, or
leaning.`** That was slot 2's _headline_ verbatim, so the first two frames a reviewer sees
  would have said one thing twice. Free, no ads, no subscription is what Flighty spends its
  own opening on, it is true here, and nothing else in the set says it.
- **Slot 5's headline was `Share it, or keep it`.** "It" had no referent this side of slot 3,
  and the second clause described the absence of an action. `Made to be handed over` names
  the artifact's purpose and leaves the privacy point to the line underneath.

No two headlines and no two supporting lines share an idea. Headlines run 4–6 words;
supporting lines stay under 40 characters, which is one line at 40% of the headline's size.

iPad reuses 1, 3, 6, 4 against its four captures.

### The layout, decided by looking

`test/store_frame_render_preview.dart` composites the frames and writes `build/store_frames/`,
including a `_sheet.png` contact sheet. **Top-anchored, centre-aligned, headline plus a
supporting line, device inset with a bezel and bleeding off the bottom edge** — treatment `d`
of four that were rendered and compared at full size and as thumbnails.

The two references disagree, and picking one settled the rest. **Flighty** uses a dark ground,
a bezelled device tilted and cropped off two edges, and a big bold caption top-left over an
attribution stack. **Duolingo** uses no device at all: a full-bleed raw screenshot with the
caption drawn as one of its own in-app components, bottom-centre. Inset-with-bezel was chosen,
which is Flighty's model, so the caption goes where Flighty puts it.

Three things decided the variants, and two of them are structural rather than aesthetic:

- **Top, because Apple crops the top in search results.** A bottom caption is invisible exactly
  where the frame has to do its work — and bleeding the device off the _top_ instead cost the
  app's own `My Library` heading and status bar to the crop.
- **Centre, because the device is centred.** Left-aligned is the stronger editorial move and
  Flighty earns it with a dark ground and an attribution stack beneath. Against a centred phone
  on light paper the left-hang reads unresolved at thumbnail size.
- **A supporting line, because at the size Apple serves these it is the only variant where you
  learn two things.** It also lets the headline stay short rather than stretching to carry the
  whole claim. Drop it on any frame where it would merely restate the headline; position and
  alignment stay fixed either way, which is what keeps the set a system.

Proportional, not absolute: the headline is 10.2% of frame width and the device 82%, so the
iPad pass inherits the same _proportions_ rather than the same point sizes. The screen's aspect
is taken from the capture, so a screenshot is never stretched — the one distortion a reviewer
notices immediately. The screen radius is 14.1% of screen width, measured off the hardware,
because a radius that is merely "rounded" is the tell that a mockup was drawn rather than
photographed.

Two traps the renderer is built around, both of which cost a round here:

- **A missing `Material` ancestor does not look like a missing `Material` ancestor.** Without
  one the ambient default is `MaterialApp`'s `_errorTextStyle`, and `Text` _merges_ it: the
  explicit colour, family and size all won, so the headline came out correct in every respect
  except the underline and yellow `decorationColor` that nothing here overrode. It reads as a
  font bug rather than a missing widget.
- **The device has to take what the caption leaves.** Positioned from the frame's edge it
  ignores the caption's height, and the supporting-line variant drew its second line behind the
  phone with the last word clipped. Deriving the crop from the remainder makes a taller caption
  mean a deeper crop, which is the honest trade: the more you say, the less app you show.

**The frames in `build/store_frames/` are built from a stale capture on purpose.** This pass
chose a layout, and the layout does not depend on what is inside the screen. They still show
the rust flame and the half-open finished-books sheet, so the bottom of the crop is uglier than
it will be.

Two open questions I am not deciding for you:

- **Whether slot 1 becomes a poster.** Four of eight benchmark apps spend it on composed art with
  no UI at all. We have the chalk-hand asset vocabulary to do it — but read
  `docs/mockups/empty-states/PROMPTS.md` first, because `AGENTS.md` is explicit that hand-authored
  SVG in that style has failed ten times and only the xAI route worked.
- **Whether supporting lines get written for all seven slots.** ~~Only slot 1's exists.~~
  Written — all seven are in the table above and in the renderer. What is still open is
  whether the **Korean** set reuses this structure or needs shorter lines: the tile fits
  about 14 full-width syllables where English gets 30, which is the same constraint the
  home-screen widget's copy ladder already works under.
