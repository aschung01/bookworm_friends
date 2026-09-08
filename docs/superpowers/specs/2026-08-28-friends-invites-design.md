# Friends and invites: mutual friendship, invite links as the only path in

Status: decided, not built.
Drawings: `docs/mockups/friend-requests/index.html` (root version `friends-only`).
Checkers: `docs/mockups/friend-requests/verify.py` (381 assertions),
`docs/mockups/friend-requests/cite_check.py` (24 citations).

## Context

The social model today is a single one-directional row. `public.follows`
(`supabase/migrations/20260505052949_initial_schema.sql:11-17`) is
`(follower_id, following_id, created_at)`, and inserting one grants the follower
read access to the followed user's shelves, books, memos, praise and avatar.
Nothing is mutual, nothing is consented to, and the row is the grant.

This replaces it with **mutual friendship**, entered **only through an invite
link**. Modelled on Flighty, and checked against its real screens.

Two consequences do most of the work:

1. **Mutuality makes the grant symmetric**, so a single canonical row can
   express it and a half-friendship becomes unrepresentable rather than merely
   discouraged.
2. **Invite-only deletes the request queue.** The queue, the badge, `status`,
   `requested_by`, the `UPDATE` policy an accept would need, two RPCs and
   `FriendState.outgoing`/`.incoming` were all created by _handle search_, not by
   mutuality. Dropping search drops all of them. Critically, an invite link needs
   **no push delivery**, so Phase 1 is not blocked on the FCM v1 migration.

### What the drawings settled

The drawings are in the app's own materials — real tokens from
`app_text_styles.dart` scaled by 0.615, real fonts off disk — and drawing them
found things the prose had wrong:

- **The consent screen has no Decline button.** The `✕` is the refusal, which is
  Flighty's structure. Dismissal writes nothing and does not consume the link's
  `used_count`, so a sender's link is not silently spent by someone who changed
  their mind.
- **A destructive confirm is `AlertDialog.adaptive`, not a page.** Both confirms
  this replaces already are (`lib/ui/pages/user_library_page.dart` (deleted),
  `lib/ui/widgets/dialogs/friend_info_dialog.dart` (deleted)). Drawing it as a
  full-screen page put a two-line question above 350px of white. The native
  alert also settles the button-label split for free — iOS orders Cancel first
  and the destructive action second, in red — so today's No/Unfollow
  (on the deleted `user_library_page.dart`) versus Cancel/Confirm
  (in the deleted `friend_info_dialog.dart`) disappears into the platform.
- **Managing a friend is reached by a gear in the visit app bar**, beside Poke.
  It was drawn on a long press of the Friends row first -- a real gesture
  (`lib/ui/widgets/friends_sheet.dart:408`, inherited from the deleted
  `FriendRail`) but an invisible one. Reusing an existing gesture is not the same
  as advertising an action, and nothing on that row hinted it existed. The visit
  bar is already the friend-level chrome -- `✕` to leave, her name, Poke -- and all
  three act on the person, which is what managing a friend does.
- **Poke is a `brandFill` pill, not an icon** (`lib/ui/pages/home_page.dart:1094-1112`:
  12/6 padding, radius 16, `AppTextStyles.label` in white). It occupies the slot
  your own avatar takes on your own library (`:1007`), so the two are mutually
  exclusive. The drawings had it as a circular icon for several passes.
- **There are two empty states, not one.** "No friends yet" and "friends, but
  nobody is mid-book". For a reading app the second is the _common_ state — people
  finish a book and start the next days later — and it must not offer "invite a
  friend" as the fix, because that is not the problem.
- **The tab bar stays up during a visit, and Friends stays lit.** This was drawn
  without one on the strength of a stale note.
  `lib/providers/shell_chrome_provider.dart:56-62` records that hiding it existed
  and was _deliberately removed_: no tab changes meaning inside a visit, and
  selecting Library or Card is how you leave, which makes the bar the way out
  rather than a claim about where you are.
- **The full-screen sheets need a type token the app lacks** — provisionally
  `AppTextStyles.hero`, 30pt serif borrowing `figure`'s metrics. It is the only
  size in the drawings not lifted whole from `app_text_styles.dart`.

### Rejected

- **A request queue with `status`/`requested_by`.** Built, then deleted. It is a
  search feature, and it is the only part of this that would need push.
- **`public-profiles`** — keeping public-by-default. Kept as a version in the
  drawings for the record. It is the only version where `UserLibraryPage` retains
  a reachable purpose. Not chosen: it leaves a stranger able to browse shelves.
- **A four-state relationship button** (`none`/`outgoing`/`incoming`/`friends`).
  Under invite-only, two states are unreachable and `none` cannot occur on a
  screen you had to be invited to reach.
- **The gear in the friend's `FinishedBooksSheet` header.** The first instinct,
  and the wrong slot. `lib/ui/pages/home_page.dart:209-214` already declined a
  back control there because it "costs no pixels in a header that has a title, a
  count and a year control in it", and said the point is that it "leaves her read
  view identical to your own" -- a gear only she has breaks that deliberately.
  `lib/ui/widgets/finished_books_sheet.dart:132-137` pins the two halves apart
  because at accessibility sizes the year filter starves the title and the row
  overflows rather than ellipsizing; the file measures the slack at 5.8px on a
  friend's sheet and `test/library_clearance_test.dart` guards it with three
  `TextScaler.linear(2)` cases (lines 239, 315, 453). The obvious escape -- move
  the filter to the capsule row that already exists in `expandedHeader` -- is
  closed too: `finished_books_sheet.dart:129-130` says that collapsed, "there is
  only the pile to show and capsules would cost all of it."
- **Flighty's per-friend "Share My Flights" toggle.** Recorded as `el-toggle`,
  drawn greyed out. It makes friendship and visibility separable per direction,
  which is exactly the asymmetry this design removes. Revisit only if asked for.
- **Every deep-link vendor.** AppsFlyer: "Deferred deep linking is not supported
  for Zero plan subscriptions", and User Invites is being revoked from the Zero
  plan — links go dead if you stop paying. Dub: no Flutter SDK, no Android, deep
  links require Pro. Adjust: tiers start ~100K MTUs. Branch: free tier is a POC
  ceiling, ~$500/mo floor. Self-hosted on `libstack.app` instead.

## Decision

### Schema

```sql
create table public.friendships (
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
```

The `check (user_a < user_b)` is the design. One canonical row per pair means a
half-friendship cannot be written at all, so no code path has to detect or repair
one, and `DELETE` severs both directions at once.

```sql
create table public.friend_invites (
  token       text primary key,
  inviter_id  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  max_uses    int not null default 10,
  used_count  int not null default 0,
  revoked_at  timestamptz
);

create table public.friend_invite_redemptions (
  token       text not null references public.friend_invites(token) on delete cascade,
  redeemer_id uuid not null references public.profiles(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  primary key (token, redeemer_id)
);
```

48 hours and 10 uses are Flighty's numbers, stated on their sheet. The token is 8
characters from an alphabet without `O/0/I/1`, because the bottom tier of the
deep-link ladder is a human reading it aloud.

Adding `status` later is one `ALTER TABLE ... DEFAULT 'accepted'`. This is not a
one-way door.

### One migration, and why it cannot be several

The visibility rule has **six call sites**, and one of them is a hand-inlined
duplicate:

| #   | Site                      | Form                                                                                          |
| --- | ------------------------- | --------------------------------------------------------------------------------------------- |
| 1   | `profiles` SELECT         | **inlined copy**, `supabase/migrations/20260505053006_rls_policies.sql:22-27`                 |
| 2   | `shelves` SELECT          | `is_profile_visible()`, `:49-50`                                                              |
| 3   | `books` SELECT            | `is_profile_visible()`, `:56-57`                                                              |
| 4   | `book_memos` SELECT       | `is_profile_visible()`, `:63-64`                                                              |
| 5   | `book_compliments` SELECT | via `is_book_visible()`, `supabase/migrations/20260815040337_compliment_uniqueness.sql:32-36` |
| 6   | `avatars` storage SELECT  | `supabase/migrations/20260819154523_add_profile_avatar.sql:74-84`                             |

Rewriting the function reaches 2–6 for free. **Site 1 does not move**, because it
is a copy. Between any two migrations the predicate would disagree with itself —
profiles readable under the old rule, their shelves under the new one — so this is
one transaction:

1. Create `friendships`, `friend_invites`, `friend_invite_redemptions` + RLS.
2. Backfill `friendships` from mutual pairs in `follows`, normalised so
   `user_a < user_b`.
3. Redefine `is_profile_visible()` against `friendships`, dropping `is_private`
   from the predicate.
4. **Replace the `profiles` SELECT policy with a call to the function**, deleting
   the duplicate permanently. This is the step that makes the rule single-sourced,
   and it is the reason this migration exists in this shape.
5. Add the friendship guard to `poke_user()`.
6. `alter table public.profiles drop column is_private;`
7. `drop table public.follows;` — last, because step 2 reads it.

`follows` SELECT is currently `USING (true)`
(`supabase/migrations/20260505053006_rls_policies.sql:36-37`), so the entire social graph is readable
by anyone, including anonymously. `friendships` SELECT must be
`user_a = auth.uid() OR user_b = auth.uid()`.

### What the backfill does to real data

Derived from `migration_data/07_follows.sql`, reproducible from the repo:

|                                          |        |
| ---------------------------------------- | ------ |
| edges                                    | 37     |
| distinct unordered pairs                 | 25     |
| mutual → `friendships`                   | **12** |
| one-way → **dropped**                    | **13** |
| one-way edges aimed at a private profile | **0**  |

12 × 2 + 13 = 37. The 13 one-way follows are **dropped silently**, with no
notification and no pending state to hold them: there is no `status` column to
park them in, and inventing one to preserve 13 rows would reintroduce the entire
queue. Per the dump, none of them point at a private profile, so no one loses
access to anything they can see today.

`follows.created_at` exists (`supabase/migrations/20260505052949_initial_schema.sql:14`) but is useless: the import
inserted only `(follower_id, following_id)`, so every row took `DEFAULT now()` and
carries the import timestamp. "Who asked first" is unknowable, which is a second
reason the one-way edges cannot be turned into directed requests.

**These numbers are from the import dump, not production.** They must be re-run
against the live database immediately before migrating, and the migration must be
written so that it does not depend on them — it backfills whatever is mutual and
drops whatever is not.

### `is_private` goes

Under friends-only it gates nothing: visibility is friendship, and with no handle
search there is no directory to be absent from.

The **Allow profile search** row goes with it — `settings_page.dart` (that switch is deleted), a
`Switch.adaptive` reading `!(profile?.isPrivate ?? false)` and calling
`updatePrivacy`. It is dead twice over: the column behind it is dropped, and it
gates a search that no longer exists. It is also the sole caller of
`updatePrivacy`, so **it has to be deleted before the provider method, or the
tree does not compile.**

The label is retired rather than reworded. "Let anyone view my library" is what
the switch would honestly become, and that is precisely the `public-profiles`
version's answer — the branch this design did not take.

Full surface, and it should be verified by grep rather than by reading this
list, because an earlier draft named the toggle here in prose and the
implementation plan still missed it:

| Site                                                            | What goes                                             |
| --------------------------------------------------------------- | ----------------------------------------------------- |
| `supabase/migrations/20260505052949_initial_schema.sql:5`       | the column                                            |
| `supabase/migrations/20260505053006_rls_policies.sql:14`, `:24` | both copies of the predicate, already being rewritten |
| `settings_page.dart` (that switch is deleted)                                    | the switch row                                        |
| `app_en.arb:277`, `app_ko.arb:250`                              | the `allowProfileSearch` string                       |
| `profile_provider.dart:195-202`                                 | `updatePrivacy`                                       |
| `profile.dart:30,41,54`                                         | the model field                                       |
| `book_compliment.dart:11`                                       | stale comment quoting the old predicate               |
| `share_destination_row.dart:29`                                 | the same                                              |
| `profile_avatar_test.dart:21`                                   | fixture key; harmless but stale                       |

### `poke_user()` gets a friendship check

Poke is person-level, so under friends-only it requires friendship. The live
definition is `supabase/migrations/20260818020000_poke_events.sql:77-116`.

While in there, two things it is missing get fixed, because the codebase already
set the standard two migrations later and this function simply predates it —
`supabase/migrations/20260821100303_add_profile_handle.sql:62-63` pins `SET search_path = ''` and
`:109-110` revokes execute from `anon, authenticated`:

- **`SET search_path = ''`** with fully-qualified names. It is `SECURITY DEFINER`
  with an unpinned search path today.
- **The push escapes its own guard.** The function has two separate `IF` blocks:
  the `poke_events` insert is guarded on `poker_id IS NOT NULL`, but the
  `net.http_post` is guarded only on `target_token IS NOT NULL`. An anonymous
  caller therefore cannot write the audit row but _can_ still fire the push — and
  with `poker_id` null, `poker_username || '님이...'` evaluates to `NULL`, so the
  notification ships with a null title. Both blocks move under one guard.

**This does not close the hole, and the spec should not claim it does.**
`supabase/functions/send-notification/index.ts` performs no authentication of any
kind — 42 lines, taking `target_user_id`, `title` and `body` straight from the
request body — so anyone can bypass `poke_user()` and call it directly. The
friendship check is defence in depth only. See _Deliberately not done_.

### Dart

Deleted: `SearchUserPage` and `AppRoutes.searchUsers`
(`lib/constants/app_routes.dart:21,50`); `UserLibraryPage` and
`AppRoutes.userLibrary` (`:22,51`); `_FollowListSheet`
(`lib/ui/pages/settings_page.dart` (`_FollowListSheet`, deleted)) and the Followers/Following stat pair
(`:530,533`, list opened at `:604`); and in
`lib/providers/user_provider.dart` — `searchUsersProvider` (`:140-151`),
`isFollowingProvider` (`:100`), `followerCountProvider` (`:74`),
`followingCountProvider` (`:87`), `followerListProvider` (`:152-166`), and
`follow`/`unfollow` (`:178-207`).

**`userLibraryProvider` stays** (`user_provider.dart:124`). It is load-bearing:
`lib/ui/pages/home_page.dart:502-513` uses it for the in-shell visit and
`lib/ui/views/book_details_tab_view.dart:147` for a friend's book. The page and
route go; the provider does not.

`UserLibraryPage` is safe to delete because the route has exactly two entry
points and both die with this change: `lib/ui/pages/search_user_page.dart` (deleted) (a
search result) and `lib/ui/pages/settings_page.dart` (that sheet is deleted) (a `_FollowListSheet`
row). Under mutual friendship the two follow lists collapse into one Friends
list, whose rows open a visit in the shell rather than this page.

Added: a `friendsProvider` replacing `followingListProvider` (14 references across
10 files, including a doc-comment link from `friendsReadingProvider`, which
derives its ids from it), invite create/redeem
calls, and a `Manage friend` screen reached from a new gear in the visit app
bar's trailing group, inboard of the Poke pill.

## Dependencies

### The domain is not a blocker, and the code floor is why

**Nothing in this spec requires `libstack.app` to be live.** The typed
8-character code is a complete path in on its own: the recipient installs the app
however they like, types the code on the `invite-code` screen, and
`redeem_invite(token)` writes the friendship. No link, no domain, no push.

So the whole of Phase 1 -- the three tables, the six-call-site RLS migration, the
`is_private` drop, the consent screen, `manage-friend`, removal, and the Dart
deletions -- is buildable and testable today. This is the same argument the spec
already makes about push, in the same shape: a working floor makes the better
tiers an optimisation rather than a precondition.

The domain gates only the link tiers, and they degrade independently:

| Tier                                | Needs the domain?                      | Wired today?                                                                            |
| ----------------------------------- | -------------------------------------- | --------------------------------------------------------------------------------------- |
| Typed 8-char code                   | No                                     | No, but needs nothing external                                                          |
| `bookworm-friends://` custom scheme | No                                     | **Yes** -- `ios/Runner/Info.plist:28-31`, `android/app/src/main/AndroidManifest.xml:42` |
| Universal Links (iOS)               | Yes -- AASA over HTTPS                 | No                                                                                      |
| App Links (Android)                 | Yes -- `assetlinks.json`               | No                                                                                      |
| Play Install Referrer               | Yes -- the landing page builds the URL | No                                                                                      |
| Clipboard-on-tap (iOS)              | Yes -- needs a page and a user gesture | No                                                                                      |

### Correction: none of the link plumbing exists yet

An earlier draft of this spec, and the `invite-installed` flow note, described the
installed case as "the Universal Link opens the app, `app_links` delivers the URI"
as though that were current behaviour. It is not:

- **`app_links` is not a dependency.** It is absent from `pubspec.yaml`.
- **`ios/Runner/Runner.entitlements` has no `com.apple.developer.associated-domains`.**
  Its only key is `aps-environment: development`.
- **Android has no App Link.** `android/app/src/main/AndroidManifest.xml:38-43` registers the
  `bookworm-friends` custom scheme only -- no `https` scheme, no `libstack.app`
  host, no `android:autoVerify="true"`.

The custom scheme is real and already registered on both platforms
(`ios/Runner/Info.plist:28-31`), where it serves the OAuth redirect
(`lib/providers/auth_provider.dart:77`). It can carry a token and open an installed
app with no domain at all. It cannot survive an in-app webview and cannot do
deferred, so it is a bonus tier, not a substitute for Universal Links.

### The real blocker is Android identity, upstream of the domain

`assetlinks.json` is keyed to the **package name plus the signing certificate
SHA-256**, and per `docs/APP_IDENTITY.md:82-95` neither is settled:

- The Play account was closed for inactivity, so `applicationId` is expected to
  change on re-registration -- suggested `app.libstack` or `com.unicorn.libstack`.
- `com.unicorn.bookworm_friends` **may not be reusable at all**; that document
  flags it as unverified and says to confirm before planning around it.

Publishing `assetlinks.json` now would pin it to a package name that is about to
change, stranding exactly the kind of unverifiable config that document gives as
its reason for leaving `applicationId` alone. **Android App Links should wait for
the account decision.** iOS does not have this problem:
`com.unicorn.bookwormFriends` is permanently frozen (`docs/APP_IDENTITY.md:40`), so
AASA content is stable as soon as the Team ID is to hand.

A trap for whoever writes those two files: the platforms' identifiers differ in
more than case. iOS is `com.unicorn.bookwormFriends`, Android is
`com.unicorn.bookworm_friends`. AASA takes
`<TeamID>.com.unicorn.bookwormFriends`; `assetlinks.json` takes the snake_case one.

### Everything else

- **`libstack.app` is bought; the landing page is being built separately.** Its
  handoff spec is delivered: AASA and `assetlinks.json` contents, serving rules,
  and the `/i/<token>` contract. AASA must be served over HTTPS at
  `/.well-known/apple-app-site-association`, with no redirect and
  `Content-Type: application/json`. The OS enforces all three and none of it can
  be stubbed locally.
- Probabilistic IP matching is deliberately omitted: it is the fastest-degrading
  part of the vendor offering, and Korean carrier NAT makes it worse than average.
- **`AppTextStyles.hero`** must be added before the sheets can be built.
- **`app_links`** must be added before any link tier can be received.
- Nothing here depends on push.

## Testing

### `supabase/tests/avatar_policies_test.sql` currently asserts the bug

It is the best test in the repo — it switches roles, so RLS is actually
exercised — and it is pinning the hole. Line 46 sets the owner
`is_private = true`; lines 59-61 insert a **unilateral** follow; lines 91-93
assert `n_follower = 1`. That is the suite asserting that a one-directional
follow grants read access to a private profile's photo.

Rewrite:

- Probe 1 (a stranger cannot read) and probe 4 (the owner always can) stand.
- Probe 2's `insert into public.follows` becomes a `friendships` row.
- Probe 3 changes from "unfollows" to "the friendship is deleted".
- The `is_private = true` setup goes with the column; the owner is now simply
  not a friend, which is what makes them unreadable.
- **New probe: a unilateral grant must be unrepresentable.** Attempt to insert a
  reversed-order row and assert it raises on the `user_a < user_b` check. This is
  the whole argument for the schema, so it should be executable rather than
  asserted in prose.

`supabase/tests/handle_test.sql` has no visibility or search assertions and is
unaffected.

### Dart

Baseline, established before any of this: **826 pass, 5 fail, 0 compile errors**.
All 5 failures are pre-existing, pile-related, and in
`test/library_read_books_test.dart`; they are unrelated to friends and must not be
attributed to this change.

Only **one** test line touches the deleted API:
`test/library_read_books_test.dart` (that override is deleted with the page) overrides `isFollowingProvider`. An earlier
note claimed seven files break on compile — that was wrong; the other files
matching "follow" are prose. `test/friend_navigation_test.dart`,
`test/friend_reading_test.dart` and `test/support/home_page_harness.dart` (a
helper imported by 12 files) all pass and do not reference the follows API.

New coverage: friendship is symmetric from both sides; a redeemed invite
increments `used_count` and writes a redemption row; an expired, revoked or
exhausted token is refused with the three distinguishable reasons the drawings
separate; dismissal writes nothing and does not increment `used_count`; removing
a friend revokes access in both directions; poke is refused between non-friends.

## Risks

- **The atomic migration is large and irreversible.** `follows` is dropped in the
  same transaction that reads it. Take a dump first; rehearse against a branch
  database; verify the six call sites afterward with a role-switching probe rather
  than by reading the policies.
- **The 13 dropped follows are 13 people who lose a shelf they could see**, even
  though none of those shelves is private. It is silent by decision.
- **Citations in this tree go stale mid-session.** During the drawing work,
  concurrent uncommitted edits shifted `shelf_row.dart` by 11 lines and
  `book_geometry.dart` by 16, silently invalidating citations that had been
  verified earlier the same day. `cite_check.py --show` now prints the content of
  every cited line for exactly this reason: range checking cannot detect drift,
  and it passed `home_page.dart:803` while it pointed at an unrelated `Padding`.
  Re-run it before trusting any line number here.
- **`AppTextStyles.hero` is a new token in a file that is deliberately small.**

## Deliberately not done

- **The `send-notification` open relay, and FCM v1.** This is a real, currently
  live security hole — no auth at all — but it is pre-existing and not caused by
  this change, and folding it in would make an already-large migration larger. It
  also very likely does not work today: the function posts to
  `https://fcm.googleapis.com/fcm/send` with `Authorization: key=`, the
  decommissioned legacy HTTP API. **Its own spec, and it should be soon.** Nothing
  in Phase 1 depends on it.
- **Whether the inviter gets a push when someone redeems.** The one thing here
  that would need FCM v1. Open.
- **The two per-friend notification toggles on `manage-friend`.** `invite-done`
  gives them a reason to exist — Flighty offers per-friend alerts at the moment
  the friendship lands, which is the one time you are thinking about that person —
  but there is no per-friend notification preference anywhere in the app today.
  If they slip, `manage-friend` is identity plus Remove, and `invite-done` loses
  its secondary button.
- **PostHog behind the existing `AnalyticsSink`.** One class, zero call-site
  changes; Firebase stays for Crashlytics. Not a Phase 1 blocker.
