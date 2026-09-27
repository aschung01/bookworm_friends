# App Store listing draft — 1.1.0

**Status: copy is PUBLISHED to both locales. Screenshots and the build are not.**

| Field              | State                                                          |
| ------------------ | -------------------------------------------------------------- |
| `copyright`        | ✅ `2026 Andrew Chung`                                         |
| `usesIdfa`         | ✅ `false` — corrected, see Finding 3                          |
| `en-US` locale     | ✅ published — `Libstack: Reading Tracker`, was holding Korean |
| `ko` locale        | ✅ published — 2022 copy replaced                              |
| Age rating         | ✅ answered                                                    |
| Privacy Policy URL | ✅ `https://libstack.app/privacy` on both locales              |
| Support URL        | ✅ `https://libstack.app/support` on both locales              |
| Reviewer contact   | ✅ Andrew Chung — and the dead 2022 demo account is cleared    |
| Review notes       | ✅ published, 2963 chars                                       |
| Screenshots        | ❌ not uploaded — see Finding 5                                |
| Build 13           | ❌ not uploaded                                                |
| Apple sign-in      | ❌ **broken — blocks submission, see Finding 1**               |

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

| Route                                             | Users  | Books   | Verdict                                   |
| ------------------------------------------------- | ------ | ------- | ----------------------------------------- |
| `gmail.com` → Google                              | 52     | 195     | ✅ Works. Proven twice above.             |
| `privaterelay.appleid.com` + `icloud.com` → Apple | 21     | 86      | ⚠️ Should work. **Unproven — see below.** |
| naver / kakao / nate / hanmail / daum / other     | **63** | **192** | ❌ No route exists.                       |

**63 users holding 192 books — 46% of the people and 41% of the books — cannot get back in.** The
app offers only Apple and Google, and no Korean portal address can be presented through either.

Two things I checked because they would have changed the answer, and they did:

- **There is no password route.** Every migrated row has `encrypted_password = ''` — an empty
  string, not a hash. (`count()` counts empty strings, which is what made this look like "all 137
  have passwords" on first pass.) Only the demo account has a real bcrypt hash. So adding
  email+password sign-in would recover **nobody**; it would take an emailed one-time code.
- **Not one Apple identity has ever been created on this project.** The entire `auth.identities`
  table is 2 Google rows and 1 email row. Which means two separate things are unproven: whether
  Apple sign-in works here at all, and whether Apple returns those 20 users their original relay
  address. Relay addresses are scoped to the primary App ID, and the bundle ID has not changed, so
  it _should_ hold — but `signInWithOAuth` uses the **web** flow through a Services ID, not native
  SIWA, and if that Services ID is not grouped under `com.unicorn.bookwormFriends` those 20 users
  land on a brand-new empty account instead of their library.

**Two recommendations, in priority order:**

1. **Sign in with Apple is broken right now — confirmed, not theoretical.** Tested 2026-09-21 and
   it fails with **"Provider not enabled"**: the Apple provider has never been switched on in
   Supabase Auth, which is exactly why `auth.identities` holds zero Apple rows. You are fixing it.
   This was one step from being the rejection, because the review notes point App Review at Sign in
   with Apple as their only way into the app. **Do not submit until a real Apple sign-in has
   produced an identity row here** — `select provider, count(*) from auth.identities group by 1;`
   While enabling it, confirm the Services ID is grouped under the primary App ID
   `com.unicorn.bookwormFriends`; that is what decides whether the 20 relay users reach their own
   library or a new empty one.
2. **Kakao sign-in recovers the 63, and is a 1.1.1 item, not a blocker.** Kakao is a built-in
   Supabase provider, and those naver/nate/hanmail/daum addresses are almost certainly the _Kakao
   account_ emails the old app received — which is exactly what auto-linking matches on. Note that
   `kakaoRestApiKey` in the build config is **not** a head start: it is a Book Search REST key, and
   Kakao Login needs its own app registration and redirect URI. Shipping 1.1.0 without it is fine
   as long as the Korean What's New does not promise those users their shelves back — which the
   copy below no longer does.

### Finding 2 — the demo credentials cannot work, and no version of them can

You created `test@apple.com` on 2026-09-01. It is real, confirmed, has a genuine bcrypt password,
0 books, and has never been signed into.

**The app has no field to type it into.** `auth_page.dart` renders exactly two buttons —
`continueWithApple` and `continueWithGoogle` — and `auth_provider.dart` exposes only
`signInWithGoogle`, `signInWithApple` and `signOut`. There is no `signInWithPassword` anywhere in
`lib/`. I re-read both files rather than trusting the earlier note, because your message implied
this had been solved; it has not.

TestFlight beta review did not catch it because beta review frequently does not attempt sign-in at
all. App Review will, and a reviewer handed credentials with nowhere to enter them rejects under
Guideline 2.1.

**Recommendation: do not supply credentials. Set `demoAccountRequired = false` and explain.** Apple
routinely accepts this for Sign in with Apple apps — the reviewer makes an account with their own
Apple ID in one tap. Notes drafted below. This is also why Finding 1's first recommendation matters
so much.

The alternative — building an email+password screen for review only — costs a screen, two locales,
tests and a Supabase email-provider configuration, and Apple actively dislikes sign-in surfaces that
exist only for them. It would also recover zero returning users, per Finding 1.

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

### Finding 5 — the screenshots still have no captions

Eleven captures are at exact required sizes (7 × iPhone 6.9" `1320×2868`, 4 × iPad 13" `2064×2752`)
in `build/shots/` — **gitignored, and destroyed by the next `flutter clean`.** Still unmoved; still
needs a decision. Captions drafted at the end of this document.

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

Coming back from the old version? Sign in with the same Apple ID or Google account you used before and your shelves will be waiting. If your shelf comes up empty, reach out and I will reconnect it by hand — nothing was deleted.

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

---

## ko

### Name (limit 30)

```
Libstack: 독서 기록
```

### Subtitle (limit 30)

```
책벌레 친구들 - 함께하는 독서 기록
```

Your string, with `함꼐하는` corrected to `함께하는` — `ㅐ`/`ㅔ` transposed. Confirm you are happy
with the fix.

> `독서 기록` now appears in both name and subtitle, which is precisely the waste observation 2
> calls out. It is a deliberate trade: the subtitle's job is to preserve four years of
> `책벌레 친구들` recognition on the storefront where every existing user lives. If you would rather
> not spend it twice, the name goes back to bare `Libstack` and the subtitle carries the category
> alone.

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

예전 버전을 쓰셨다면: 그때 Google 또는 Apple 계정으로 가입하셨다면, 같은 계정으로 로그인하면 서재가 그대로 남아 있습니다. 카카오 계정으로 가입하셨던 분들은 아직 로그인할 방법이 없습니다 — 카카오 로그인을 복구하는 작업을 진행 중이고, 그때까지 서재는 삭제되지 않고 그대로 보관됩니다.

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

Set alongside these: `demoAccountRequired = false`, and `demoAccountName` /
`demoAccountPassword` explicitly blanked — see Finding 6, there is a dead 2022 account in
those fields right now. Reviewer contact is `Andrew Chung`, `aschung1005@gmail.com`,
`+1 628-688-9415`, held in `REVIEWER_CONTACT` in `scripts/asc_version.py`. Apply the whole
block with:

```bash
.venv/bin/python scripts/asc_version.py --set-review-details
```

### Notes (limit 4000)

```
NO DEMO ACCOUNT IS NEEDED — PLEASE USE SIGN IN WITH APPLE.

Libstack has no username-and-password sign-in. The only two ways in are Sign in with Apple and Google, so there are no credentials to hand over. On the first screen, tap "Continue with Apple" and use your own Apple ID; Hide My Email works fine. Account creation is instant, with no email confirmation, no payment, and no personal details beyond what Apple returns. You can delete the account from within the app when you are finished.

The app is free. No in-app purchases, no subscriptions, no advertising.

WHAT TO TRY. A new account starts with an empty shelf, so:

1. SEARCH TAB — type any title, for example "Dune". Or tap the barcode button and scan the back cover of any physical book.
2. Tap a result, add it, and choose a shelf. It appears on the shelf on the Library tab.
3. Tap the book on the shelf to open it. Update progress logs where you are, by page number (p.259 / 432) or by percent.
4. The view switcher on the Library tab cycles three shelf views: covers face-out, spines lined up, and leaning. Books can be dragged between positions.
5. LIBRARY CARD, at the bottom of the Library tab — it summarises books finished, days read, reading pace and most-read author, and the share button renders it as an image for the system share sheet, Instagram Stories or Photos.

FRIENDS ARE MUTUAL AND INVITE-ONLY. There is no public profile, no feed, no way to search for or browse strangers, and no direct messaging between users. A connection exists only after both people accept an invite link, and a library is readable only between mutually connected accounts. This is enforced by row-level security in the database, not in the client. The only user-to-user content is an emoji reaction on a book. Notes a reader writes on a book are private to its author and are never visible to friends.

To see the Friends tab with real data you need a second account: Friends tab, Invite, share the link, then open that link on a second device signed in with a different Apple ID and accept it. Invite links expire after 48 hours.

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

Proposed order and captions — top-anchored, 4–6 words, brand green `#09BC8A` on the app's own
`pageBackground`, set in Gowun Batang Bold to match the in-app `hero`/`title` token:

| #   | Capture             | Caption                       |
| --- | ------------------- | ----------------------------- |
| 1   | `01-library-covers` | A bookshelf you actually keep |
| 2   | `02-library-spines` | Covers, spines, or leaning    |
| 3   | `03-library-card`   | Your reading becomes a card   |
| 4   | `05-book-details`   | Log the page you're on        |
| 5   | `07-share-card`     | Share it, or keep it          |
| 6   | `04-friends`        | Read alongside your friends   |
| 7   | `06-search-results` | Scan the barcode to add       |

iPad reuses 1, 3, 6, 4 against its four captures.

Two open questions I am not deciding for you:

- **Whether slot 1 becomes a poster.** Four of eight benchmark apps spend it on composed art with
  no UI at all. We have the chalk-hand asset vocabulary to do it — but read
  `docs/mockups/empty-states/PROMPTS.md` first, because `AGENTS.md` is explicit that hand-authored
  SVG in that style has failed ten times.
- **Where the 11 files live.** They are still in `build/shots/`, 22.6 MB, one `flutter clean` from
  gone. `docs/store/screenshots/` is the obvious home if you are willing to carry them in git.
