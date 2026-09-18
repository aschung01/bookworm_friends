# Friends and invites — Implementation Plan

> **For agentic workers:** Implement task-by-task, in order. Steps use checkbox (`- [ ]`) syntax for
> tracking. Read `.agents/skills/flutter-tester/SKILL.md` before writing any test — this project has
> established Given-When-Then and layer-isolation conventions. Read
> `.agents/skills/supabase-postgres-best-practices/SKILL.md` before Task 2.

**Design:** `docs/superpowers/specs/2026-08-28-friends-invites-design.md`
**Drawings:** `docs/mockups/friend-requests/index.html`, root version `friends-only`. Verify with
`python3 docs/mockups/friend-requests/verify.py` (589 assertions) and
`python3 docs/mockups/friend-requests/cite_check.py --show` (27 citations). **Run both before and
after** touching a number or a line reference the page cites.

**Prior art to read first:**

- `supabase/migrations/20260821100303_add_profile_handle.sql` — the house standard for a
  `SECURITY DEFINER` function: `SET search_path = ''` at `:62-63`, `REVOKE` at `:109-110`. Task 3
  applies it to `poke_user()`, which predates it.
- `supabase/migrations/20260815040337_compliment_uniqueness.sql` — `is_book_visible()` wraps
  `is_profile_visible()`. It is call site 5 of 6 and needs no edit, which is the point of Task 2.
- `docs/superpowers/plans/2026-08-22-friend-navigation-plan.md` — deleted `friend_rail.dart` and
  established the visit. Task 6 adds the gear to the bar that plan built.

**Goal:** Replace one-directional `follows` with mutual `friendships`, entered only through an invite
link, and delete the search surface that made a request queue necessary.

**What is genuinely new:** three tables, one RPC pair, one screen, and a gear in the visit bar.
Everything else is deletion.

---

## Baseline, measured before any change

`flutter test` — **826 pass, 5 fail, 0 compile errors.** All five failures are pre-existing and in
`test/library_read_books_test.dart` (lines 108, 134, 158, 178, 197); every one is a read-pile
assertion finding zero widgets. **They are not yours. Do not fix them, and do not let the count of
five change without noticing.**

Exactly **one** test line touches the API this plan deletes: `test/library_read_books_test.dart` (that override is deleted with the page),
which overrides `isFollowingProvider`. An earlier note claimed seven files break. That was wrong; the
rest match the word "follow" in prose only.

---

## What this changes, stated carefully

**The `check (user_a < user_b)` is the design, not a tidiness.** One canonical row per pair means a
half-friendship is unrepresentable, so no code path has to detect or repair one, and a single
`DELETE` severs both directions. Every write must normalise the pair before touching the table:

```sql
-- Canonical order, everywhere. Never insert a raw (me, them).
least(a, b), greatest(a, b)
```

**The visibility rule has six call sites and one is a hand-inlined copy.** Rewriting
`is_profile_visible()` reaches five of them for free. The `profiles` SELECT policy
(`supabase/migrations/20260505053006_rls_policies.sql:22-27`) spells the predicate out again and does not move. Between
any two migrations the rule would disagree with itself — profiles readable under the old rule, their
shelves under the new — so Task 2 is **one transaction**, and step 4 of it deletes the duplicate
permanently.

**Phase 1 does not need the domain.** The typed 8-character code is a complete path in: install,
type, `redeem_invite`. Tasks 1–8 are buildable and testable with no AASA, no `assetlinks.json`, and
no push. Task 9 is the link tiers and is explicitly deferred.

---

## Task 1: the three tables

> **Done.** `20260828120000_friendships.sql` + `supabase/tests/friendships_test.sql` (6
> cases, passing). Executed, not just written: `sh supabase/tests/run_local.sh` applies the
> whole migration chain to a throwaway Postgres and runs every SQL test.
>
> That harness is new and was not in the plan. `supabase/config.toml` does not exist — this
> project is linked to a remote — and `supabase init` would have added config to the repo
> uninvited, so instead `supabase/tests/_harness.sql` stubs the four Supabase-managed
> objects the migrations touch (`auth.uid()`, `auth.users`, `storage.objects`,
> `net.http_post`) and `_seed.sql` provides three profiles. Writing an irreversible
> migration without somewhere to rehearse it was not a risk worth taking.
>
> Two things the harness caught that review would not have: `storage.buckets` needs
> `file_size_limit` (the avatars migration sets it), and `authenticated` needs table
> GRANTs — without them RLS is never reached and every policy test fails with "permission
> denied" while saying nothing about the policy. An event trigger grants on each new table,
> since migrations create tables after the harness runs.

- [ ] `supabase/migrations/20260828120000_friendships.sql`. Tables only — no policy touches the
      visibility rule yet, so this migration is independently safe and reversible.
- [ ] `friendships(user_a, user_b, created_at)`, PK `(user_a, user_b)`, both FKs
      `references public.profiles(id) on delete cascade`, and `check (user_a < user_b)`.
- [ ] `COMMENT ON TABLE` stating that the check makes a half-friendship unrepresentable, and that
      this is why there is no `status` column.
- [ ] Index on `(user_b)`. The PK already serves lookups by `user_a`; a friend list has to search
      both columns, and the spec's `friendsProvider` queries `user_a = me OR user_b = me`.
- [ ] `friend_invites(token pk, inviter_id, created_at, expires_at, max_uses default 10, used_count
default 0, revoked_at)`.
- [ ] `friend_invite_redemptions(token, redeemer_id, redeemed_at)`, PK `(token, redeemer_id)` — which
      is what makes a second redemption by the same person a no-op rather than a double-count.
- [ ] RLS on all three. `friendships` SELECT is `user_a = auth.uid() OR user_b = auth.uid()` —
      **never `USING (true)`**, which is what `follows` does today (`supabase/migrations/20260505053006_rls_policies.sql:36-37`) and why
      the whole social graph is currently readable anonymously.
- [ ] `friend_invites` SELECT: inviter only. A redeemer reaches it through the RPC, which is
      `SECURITY DEFINER`, so no policy needs to expose a token to the person redeeming it.
- [ ] **No `UPDATE` policy on `friendships`.** There is nothing to update; the table is
      insert-and-delete. Adding one would be the first step back toward a request queue.

**Tests** — `supabase/tests/friendships_test.sql`, new, modelled on `avatar_policies_test.sql`'s
role-switching (that is the only reason that file catches anything):

- [ ] A reversed-order insert raises on the check. **This is the whole argument for the schema, so it
      must be executable rather than asserted in prose.**
- [ ] A third party cannot SELECT a friendship they are not in.
- [ ] `on delete cascade` removes friendships when a profile goes.

---

## Task 2: the atomic visibility migration

> **Done.** `20260828120100_friends_only_visibility.sql`, plus
> `supabase/tests/visibility_test.sql` (six call sites × four states) and a rewritten
> `avatar_policies_test.sql`. All passing.
>
> The backfill is rehearsed separately by `sh supabase/tests/rehearse_backfill.sh`, which
> stops the chain one migration short — after `friendships` exists, before `follows` is
> dropped — because that is the only moment the question is answerable. Its fixture
> deliberately includes `c → b` without `b → c` alongside a mutual `a ↔ b`: reciprocity is
> per-pair, and a naive "has an edge in both directions" query pairs them wrongly.
>
> `visibility_test.sql` adds a probe the plan did not ask for: **the anonymous caller**.
> The original hole was specifically anonymous — `is_private = false` was evaluated before
> any relationship check, so a null `auth.uid()` matched it. A stranger-only test would
> have passed against the broken predicate.
>
> **Re-derived against production, as the risk table requires** (read-only, via
> `supabase db query --linked`). It has moved since the dump, which is exactly why the
> migration is written not to depend on the counts:
>
> |                                      | dump | production |
> | ------------------------------------ | ---- | ---------- |
> | follow edges                         | 37   | **36**     |
> | distinct pairs                       | 25   | 25         |
> | mutual pairs → friendships           | 12   | **11**     |
> | one-way edges dropped                | 13   | **14**     |
> | of those, aimed at a private profile | 0    | **0**      |
>
> The last row is the one the decision rests on, and it still holds: **nobody loses access
> to a shelf they can currently see.** The other four moved because the graph is live.
>
> **Pushed to production**, 2026-08-29, after a schema dump and a data dump. The backfill
> produced **11 friendships across 17 people** — the figure predicted above, which is the
> check that matters: a different number would have meant the migration's reciprocity join
> disagreed with the query used to forecast it. `follows` and `profiles.is_private` are
> gone, `is_profile_visible()` reads `friendships`, non-canonical rows are 0, and the three
> new tables carry SELECT/DELETE/UPDATE policies and **no INSERT policy at all** — so
> `redeem_invite()` really is the only writer.
>
> `create_invite()` was then exercised against production inside a transaction that was
> rolled back: 8 characters, no `O/I/0/1`, 10 uses, 48 hours, and `friend_invites` left
> empty afterwards.

> **Read the whole task before writing a line of it.** It drops `follows` in the same transaction
> that reads it. Take a dump first and rehearse on a branch database.

- [ ] `supabase/migrations/20260828120100_friends_only_visibility.sql`. One transaction, in this
      order, and the order is load-bearing:

- [ ] **1. Backfill.** Insert one row per mutual pair, normalised:

  ```sql
  insert into public.friendships (user_a, user_b)
  select distinct least(f.follower_id, f.following_id),
                  greatest(f.follower_id, f.following_id)
  from public.follows f
  join public.follows r
    on r.follower_id = f.following_id
   and r.following_id = f.follower_id;
  ```

- [ ] **2. Redefine `is_profile_visible()`** against `friendships`, dropping `is_private` from the
      predicate. Keep `SECURITY DEFINER STABLE`; **add `SET search_path = ''`** and fully-qualify,
      which the original lacks.
- [ ] **3. Replace the `profiles` SELECT policy with a call to the function.** Drop
      `"Users can read visible profiles"` and recreate it as
      `USING (public.is_profile_visible(id))`. This is the step that makes the rule single-sourced
      and is the reason this migration cannot be split.
- [ ] **4. Drop `is_private`** from `public.profiles`.
- [ ] **5. `drop table public.follows;`** — last, because step 1 reads it.
- [ ] Leave `is_book_visible()` (`supabase/migrations/20260815040337_compliment_uniqueness.sql:32-36`) and the avatars storage policy
      (`supabase/migrations/20260819154523_add_profile_avatar.sql:74-84`) **untouched**. Both call the function and inherit the new rule.
      Verify that they do rather than assuming it.

**Expected backfill numbers**, derived from `migration_data/07_follows.sql`: 37 edges → 25 distinct
pairs → **12 friendships**, **13 one-way edges dropped**, and **0** of those 13 aim at a private
profile. **Re-run this against production immediately before migrating** — the numbers are from the
import dump — but write the migration so it does not depend on them.

`follows.created_at` exists but is useless: the import inserted only the two ids, so every row carries
the import timestamp. "Who asked first" is unknowable, which is the second reason the 13 cannot become
directed requests.

**Tests:**

- [ ] Rewrite `supabase/tests/avatar_policies_test.sql`. **It currently asserts the bug**: line 46
      sets `is_private = true`, lines 59-61 insert a _unilateral_ follow, lines 91-93 assert the
      follower can read. Probe 2 becomes a `friendships` row; probe 3 becomes "the friendship is
      deleted"; the `is_private` setup goes with the column. Probes 1 and 4 stand as written.
- [ ] A role-switched probe per call site — profiles, shelves, books, memos, compliments, avatars —
      asserting a non-friend reads nothing and a friend reads all six. **Six probes, because five of
      them are inherited and inheritance is exactly what this task must prove.**

---

## Task 3: `poke_user()` — friendship, `search_path`, and the guard bug

> **Done.** `20260828120200_poke_requires_friendship.sql` + `supabase/tests/poke_test.sql`
> (6 cases, passing).
>
> The guard-split fix is pinned by probe 5, which asserts on the recorded `net.http_post`
> call rather than on `poke_events`. That is the only way to see it: the old bug left no
> audit row — it was correctly blocked — while still firing a push with a `NULL` title.
> Invisible in the events table, visible only in what the function tried to send.
>
> Self-poke needed no separate clause. `user_a < user_b` means a pair with itself matches
> nothing, so the friendship check refuses it for free.

The live definition is `supabase/migrations/20260818020000_poke_events.sql:77-116`.

- [ ] `supabase/migrations/20260828120200_poke_requires_friendship.sql`.
- [ ] Require friendship before either effect. Poke is person-level, so under friends-only it is
      simply not available between strangers.
- [ ] `SET search_path = ''` and fully-qualify. It is `SECURITY DEFINER` with an unpinned path today,
      which is the trap `supabase/migrations/20260821100303_add_profile_handle.sql:57` documents.
- [ ] **Fix the guard split.** The function has two `IF` blocks: the `poke_events` insert is guarded
      on `poker_id IS NOT NULL`, but the `net.http_post` is guarded only on
      `target_token IS NOT NULL`. An anonymous caller therefore cannot write the audit row but **can**
      still fire the push — and with `poker_id` null, `poker_username || '님이…'` is `NULL`, so the
      notification ships with a null title. Both effects move under one guard.
- [ ] Preserve the existing silent-no-op contract. `:97-100` guards rather than letting the CHECK
      raise, deliberately, so that recording history never turns a no-op into "poke failed". A
      non-friend poke must return silently for the same reason.

> **This does not close the hole, and the plan must not claim it does.** > `supabase/functions/send-notification/index.ts` authenticates nothing — 42 lines, taking
> `target_user_id`, `title` and `body` straight from the body — so anyone can bypass `poke_user()`
> entirely. The friendship check is defence in depth. See _Deliberately not in this plan_.

---

## Task 4: create and redeem

> **Done.** `20260828120300_invite_rpcs.sql` + `supabase/tests/invites_test.sql` (9 cases,
> passing).
>
> Two additions beyond the plan. `redeem_invite` returns a composite `(result,
inviter_id)` rather than a bare enum — the consent screen has to name the inviter before
> the reader decides, and the redeemer cannot read `friend_invites` themselves. And there
> is an `already_friends` result distinct from `ok`: re-tapping a link you have used is not
> a failure, but showing the success screen again would be a lie.
>
> Ordering inside the function is load-bearing and commented as such: revoked before
> expired (revoked is the more specific fact, and the one the inviter chose),
> `already_friends` before `exhausted` (or a repeat tap on a spent link reports
> "exhausted", which is true and useless).

- [ ] `supabase/migrations/20260828120300_invite_rpcs.sql`.
- [ ] `create_invite()` → token. 8 characters from an alphabet **without `O/0/I/1`**, because the
      bottom tier of the ladder is a human reading it aloud. `expires_at = now() + interval '48
hours'`.
- [ ] `redeem_invite(token)` → an enum-like result, not a boolean. The drawings distinguish
      **expired**, **revoked** and **exhausted**, because the recovery differs: two mean _ask for a
      new link_ and one means _you already used this_. A boolean cannot carry that.
- [ ] Redemption is one transaction: validate, insert the normalised friendship, insert the
      redemption row, increment `used_count`. `on conflict do nothing` on the friendship, so
      redeeming twice is idempotent rather than an error.
- [ ] Refuse self-redemption. The inviter tapping their own link is the most likely accident.
- [ ] Both `SECURITY DEFINER SET search_path = ''`, execute revoked from `anon`.

**Tests** in `supabase/tests/invites_test.sql`:

- [ ] Redemption writes a friendship, a redemption row, and `used_count = 1`.
- [ ] Expired, revoked and exhausted each return their own distinguishable result.
- [ ] Redeeming twice is a no-op, not a second friendship and not a second count.
- [ ] Self-redemption is refused.
- [ ] **Dismissal writes nothing and does not consume a use.** The consent screen's `✕` is the
      refusal, and a sender's link must not be silently spent by someone who changed their mind.

---

## Task 5: the Dart data layer

> **Done.** `friendsProvider` queries `friendships` with `.or(...)` and picks whichever id
> is not yours; `followerCountProvider` and `followingCountProvider` collapsed into one
> `friendCountProvider`. `UserActions.removeFriend` orders the pair with `least`/`greatest`
> before the `DELETE`, because the table stores it that way and an unordered delete matches
> nothing. New `lib/models/invite.dart` and `lib/providers/invite_provider.dart`.
>
> Two things beyond the checkboxes. The exit-condition grep is clean in `lib/`, `test/` and
> `supabase/` **except** for prose — the migrations and their tests explain _why_
> `is_private` is gone, which is the point of writing it down; `migration_data/` is a
> historical dump and is left alone. And `friendship_symmetry_test.dart` was added for the
> two rules no widget test can reach: reading a row from both sides, and canonicalising a
> pair before writing. Both are one-line functions, and both fail in exactly one direction.

- [x] `lib/providers/user_provider.dart`. Delete `searchUsersProvider` (`:140-151`),
      `isFollowingProvider` (`:100`), `followerCountProvider` (`:74`), `followingCountProvider`
      (`:87`), `followerListProvider` (`:152-166`), and `follow`/`unfollow` (`:178-207`).
- [x] Rename `followingListProvider` → `friendsProvider` and repoint it at `friendships`.
      **14 references across 10 files**, so do this with a rename, not by hand:

  | file                                                                                                                                                                                         | refs                                                 |
  | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
  | `lib/providers/user_provider.dart`                                                                                                                                                           | 5 (the definition, plus a doc-comment link at `:39`) |
  | `lib/ui/pages/home_page.dart`                                                                                                                                                                | 1 (`:450`)                                           |
  | `lib/ui/pages/settings_page.dart`                                                                                                                                                            | 1 (`:1014`)                                          |
  | `lib/main_shell_preview.dart`                                                                                                                                                                | 1 (`:211`)                                           |
  | `test/friend_navigation_test.dart`, `library_clearance_test.dart`, `library_bar_test.dart`, `shell_tab_bar_test.dart`, `library_back_navigation_test.dart`, `support/home_page_harness.dart` | 1 each                                               |

  An earlier draft of this plan said "six override sites" and listed seven. Both were wrong — it
  missed `library_back_navigation_test.dart`, `home_page_harness.dart` (a helper imported by 12
  test files), and the doc-comment reference. Verify with
  `grep -rn "followingListProvider" lib/ test/` returning nothing.

- [x] `friendsReadingProvider` **derives its ids from this provider** (`user_provider.dart:39`), so
      it moves with the rename — including the `[followingListProvider]` link in its doc comment,
      which is load-bearing documentation for why the batching exists. Its behaviour does not change:
      one `in` filter for the whole list, which is the entire reason it was written.
- [x] **`userLibraryProvider` stays.** It is load-bearing — `home_page.dart:502-513` for the in-shell
      visit, `book_details_tab_view.dart:147` for a friend's book. The page and route go; the
      provider does not.
- [x] Add `inviteActionsProvider` wrapping the two RPCs.
- [x] **Delete the Allow-profile-search row first** — `settings_page.dart` (that switch is deleted), the
      `_SettingsMenuItem` whose `Switch.adaptive` reads `!(profile?.isPrivate ?? false)` and calls
      `updatePrivacy`. It is the only caller, so deleting `updatePrivacy` before this **does not
      compile**. The row is dead twice over under friends-only: it gates a search that no longer
      exists, and the column behind it is gone in Task 2.
- [x] Retire the `allowProfileSearch` l10n key from `app_en.arb:277` and `app_ko.arb:250`. There is
      no rename to consider: with search gone the switch has nothing left to describe, which is why
      it goes rather than becoming "Let anyone view my library" (that is the `public-profiles`
      version's answer, and it is the branch we did not take).
- [x] `lib/models/profile.dart`: drop `isPrivate` (`:30`, `:41`, `:54`).
- [x] `lib/providers/profile_provider.dart`: delete `updatePrivacy` (`:195-202`).
- [x] Fix two stale comments that quote the old predicate verbatim:
      `lib/models/book_compliment.dart:11` and
      `lib/ui/widgets/library_card/share_destination_row.dart:29`.
- [x] `test/profile_avatar_test.dart:21` carries `'is_private': false` in a fixture. It will not
      break — an unread key is ignored — but remove it in the same change.
- [x] `grep -rn "is_private\|isPrivate\|allowProfileSearch\|updatePrivacy" lib/ test/ supabase/`
      returns nothing outside generated l10n. **Run it as the task's exit condition** — the switch was
      missed once already because the spec named it in prose and no checkbox carried it.

---

## Task 6: the screens

> **Done**, with three deviations worth naming.
>
> **The long press survives.** The plan reads as though the gear replaces it; it does not —
> `friends_sheet.dart` still opens `ManageFriendPage` on a long press, now pointed at the
> page instead of the deleted dialog. The gear exists because nothing _advertised_ the
> gesture, which is a different complaint from the gesture being wrong.
>
> **`_FollowListSheet` took a fourth thing with it.** The Settings header had a branch
> swapping the Edit-profile button for a blank box while that sheet was open, because
> `_EditProfileButton` can be a native `CNPopupMenuButton` — a platform view, which paints
> above anything Flutter puts over it. Nothing covers that row any more, so the branch and
> its `_isFollowListVisible` flag went too.
>
> **The quiet empty state is gone, and the checkbox above it is wrong.** It was built as
> drawn — a banner above the list for "friends exist, nobody is mid-book" — and then removed
> on sight of it running. The drawings' reasoning is sound and its premise is not: that
> state was drawn against a row showing a _read count_, and the row this app actually ships
> already prints `friendNothingInProgress` on its own second line. With three idle friends
> the sheet stated the same fact four times — once per row, then again in a summary of the
> rows immediately beneath it.
>
> A summary earns its place when it says something the list does not. This one could not,
> and it had no action to offer either, since inviting is not the fix for friends between
> books. **The state still exists and is still legible; it is expressed by the rows.**
> `noFriendsReading` and `noFriendsReadingBody` are retired from both locales, and
> `friends_empty_states_test.dart` now pins the row-level behaviour instead: exactly one
> "Nothing in progress" per idle friend, no invite CTA, and a blank subtitle rather than a
> premature claim while the batch query is in flight.
>
> **The same floor broke the _other_ empty state, and it shipped visibly.** `_NoFriends`
> uses `SheetBodyCenter`, like every other empty state in the app — and that widget pinned
> its child to the visible slice's exact height through an `OverflowBox`, which is right for
> what its doc said it was for: _a single line of text_. This state is a title, a paragraph
> and a button, so at the collapsed detent it overflowed by 20pt and put a yellow-and-black
> bar across the sheet with the CTA off the card.
>
> **Fixed in `SheetBodyCenter`, not in Friends.** The first attempt top-aligned this one
> state, which stopped the overflow and lost the centring — and a heading pinned under the
> header with a screen of blank card below it reads as content that failed to load. The
> widget now centres when the child fits and scrolls when it does not, which is the ordinary
> centre-or-scroll idiom and a fix for every empty state rather than for this one: they all
> have the same 20% floor under them, and a single line at a large text scale hits it too.
>
> Six cases in `friends_empty_states_test.dart` pin it, checked against the broken version
> first: `takeException` at the collapsed detent on two screen sizes and at 2× text, a
> geometry assertion that the button is inside the card at the detent the sheet actually
> opens on, a ratio assertion that the state is centred rather than top-aligned, and — for
> the case that rules out simply centring — a scroll-then-tap at 2× text on a 667pt phone,
> where the content is taller than the body at every detent. The existing tests all passed
> while it was broken, because "the CTA is present" was true of the broken version too.

- [x] Delete `lib/ui/pages/search_user_page.dart` and `AppRoutes.searchUsers`
      (`app_routes.dart:21,50`).
- [x] Delete `lib/ui/pages/user_library_page.dart` and `AppRoutes.userLibrary` (`:22,51`). Safe
      because the route has exactly two entry points and both die here:
      `search_user_page.dart` (deleted) and `settings_page.dart` (that sheet is deleted).
- [x] `settings_page.dart`: delete `_FollowListSheet` (`:975-990`) and the Followers/Following pair
      (`:530,533`, opened at `:604`). Under a mutual model they are one number, so the header states
      it once. This also removes two `.count()` round trips.
- [x] `friends_sheet.dart:152`: the header icon becomes **Invite**, not search. Its tooltip already
      says `searchFriends`, which will be wrong in both senses.
- [x] ~~**Two empty states, not one.**~~ **One.** `noFriendsYet` keeps "invite a friend" as its
      action. The second — friends exist, none mid-book — was built and then removed: the row
      already says "Nothing in progress" on its own second line, so a banner above the list
      repeated it once per row plus once more. The reasoning still holds (it is the common state,
      not the edge case, and inviting is not its fix) — it simply needs no banner to be legible.
      See the note under this task.
- [x] New `lib/ui/pages/manage_friend_page.dart`: identity, the two notification toggles, and a
      `Remove friend` row.
- [x] **The gear** in the visit bar's trailing group, inboard of Poke (`home_page.dart:834`, contract
      at `:801`, Poke pill at `:1009-1023`). Not a long press — that gesture exists
      (`friends_sheet.dart:408`) but nothing advertises it.
- [x] Removal confirms with `AlertDialog.adaptive`, matching `user_library_page.dart` (deleted) and
      `friend_info_dialog.dart` (deleted). iOS orders Cancel first and the destructive action second in
      red, which dissolves today's No/Unfollow versus Cancel/Confirm split into the platform.
- [x] `friend_info_dialog.dart` loses its follower counts (`:32-33`) and its unfollow path
      (`:119-120`); `manage_friend_page` replaces it.
- [x] `AppTextStyles.hero` — 30pt serif, borrowing `figure`'s metrics. **The one size in the drawings
      not lifted from `app_text_styles.dart`.** Add it before building any sheet.
- [x] l10n: retire `followers`, `following`, `unfollow`, `unfollowConfirmTitle`,
      `unfollowConfirmMessage`, `unfollowFailed`, `searchFriends`. Add the invite, consent, manage and
      removal strings. **Never hand-edit `lib/l10n/app_localizations*.dart`** — they are generated.

---

## Task 7: the invite flow

> **Done.** `invite_sheet.dart`, `invite_consent_page.dart`, `invite_done_page.dart`,
> `invite_code_page.dart`, `invite_dead_page.dart`, and a shared `ShelfDuo` mark.
>
> **The mark was built twice.** The first pass drew plain rounded rectangles for spines,
> which is the version the drawings explicitly rejected — "the reading equivalent of a grey
> box". The second is made of the app's own `GeneratedCover` at `kGeneratedCoverMinWidth`,
> so the books carry real titles in the real palette, on a real plank, over a brand wash.
> The whole scene is a `FittedBox(scaleDown)`: its natural width comes from the book's width
> and from translated pill captions, so it is not a number this file gets to choose.
>
> **The invite sheet is full-bleed.** Its horizontal inset moved from the scroll view onto
> each block, so the mark can span the phone. Three shelves of two books do not fit inside
> 24pt of padding on a 393pt screen, and a gradient that stops short reads as a panel rather
> than a horizon.
>
> **A typed code skips consent.** The plan implies one path; there are two. Typing eight
> characters _is_ the consent, and the friendship is written by the time the RPC returns —
> the consent screen exists for the tapped-link path, where the reader arrived without
> deciding anything.
>
> **The notification toggles were removed 2026-08-31, which is this drawing's own fallback
> for them.** `docs/mockups/friend-requests` left it open whether they ship at all: "If they
> slip, this screen is identity plus Remove." They slipped, and shipping them anyway was
> worse than omitting them — two `Switch`es backed by nothing but local `setState`, so a
> toggle held until the page was popped and then silently reverted. `When they finish a book`
> also defaulted to **on**, promising every reader a notification that does not exist.
>
> There was nothing to persist _to_ and nothing to persist _for_: there is no start/finish
> notification anywhere in the app. The only push is `poke`, and `send-notification/index.ts`
> still posts to the decommissioned legacy FCM endpoint — so a preference column would have
> been the smallest part of the work. The copy stays in both `.arb` files; restore the
> switches with the feature, not before.
>
> **The code screen's formatters were in the wrong order**, and `invite_flow_test.dart`
> caught it: filtering ran ahead of the case fold, so a lowercase code was tested against an
> uppercase-only alphabet and every character was deleted as it was typed. A code read aloud
> and typed in lowercase produced an empty field, silently.
>
> **Two chrome defects found on device, after the fact, by looking at a screenshot.** Both
> were geometry, and both are now measured in `invite_sheet_chrome_test.dart` — verified to
> fail against the code that shipped them.
>
> 1. _The sheet's ✕ was 36pt._ Copied from the library visit bar, where the ✕ is crowded in
>    beside Poke and every point is contested. Nothing crowds this one and it is the only way
>    out of a full-height sheet, so it is 44 — the platform's minimum target, and what Add
>    Book, Manage Shelves, the scanner and the share card all use. The consent and dead-link
>    screens keep 36: those are pages, not sheets, and their ✕ sits in a page's top-left where
>    a back chevron would (`adaptive_back_button.dart` is 36 for the same reason).
> 2. _Share and the read-aloud code sat behind the floating tab bar._ `ShellChrome` hosts that
>    bar above the `Navigator` so it stays in front of the _first_ modal over the shell — which
>    this sheet is — and `SafeArea` clears only the home-indicator strip. Measured, Share's
>    bottom edge was 42pt inside the glass. It now reserves `ShellTabBarGeometry.reserve`, the
>    same object the bar positions itself from, so the two cannot drift. **Gated on
>    `shellBarVisibleProvider`**: the sheet also renders with nothing over it (the mark
>    preview, any widget test), and reserving unconditionally would put 66pt of dead air at
>    the bottom of those.
>
>    The lesson is the one this file keeps re-learning: every other shell sheet makes this
>    reservation, and this one was written as a standalone modal without asking what floats
>    over it. Anything new drawn at the bottom of a sheet in this app needs the same check.
>
>    **The overlap was the code line, not the button** — measured, the button's rect was
>    `710..758` against a native bar top of `769`, so it cleared by 11pt. An earlier note
>    here claimed the button itself was covered and that this was why Share did nothing;
>    that was wrong, and it came from reading `find.text('Share invite')`'s rect, which
>    matches the read-aloud row. The reservation is still right — the code was genuinely
>    under the bar — but it was never the reason the button appeared dead.
>
> **`_share` swallowed everything, which is why "nothing happens" was the whole bug report.**
> It was a bare `await Share.share(...)`: the `ShareResult` discarded, no `try`. Three very
> different outcomes — presented-and-dismissed, refused by the platform, and thrown — were
> indistinguishable from the outside, and none of them left a trace. Now:
>
> - **`sharePositionOrigin` is passed**, from a `GlobalKey` on the button. Not a nicety:
>   `FPPSharePlusPlugin.m:378-393` refuses the presentation outright when a popover
>   controller exists and the origin is zero, so on iPad — which this app builds for,
>   `TARGETED_DEVICE_FAMILY = "1,2"` — an unanchored share is a guaranteed silent no-op.
>   `share_library_card.dart` has always passed one; this did not. Asserted, and verified to
>   fail without it.
> - **Failures reach the reader** via `EasyLoading.showError`, as every other failed action
>   in this app does, behind a new `inviteShareFailed` string in both locales.
> - **`ShareResult.status` is logged in debug**, which is the diagnostic that tells a
>   simulator's `unavailable` apart from a real dismissal.
>
> The root cause on the simulator is still **unconfirmed** — an iOS simulator has no share
> destinations and commonly declines `UIActivityViewController`. The logging exists to settle
> that on the next tap rather than to assert it here.

- [x] Invite sheet: the three-shelf mark, two descriptive paragraphs, the 48h/10-use contract,
      and one button. **Sells the payoff, not the link** — Flighty shows
      neither a link nor a code on theirs, and after three corrections neither does this.

      > **Two of three "gaps" I closed on 2026-08-31 were reverted on the same day, and the
                              > pattern is worth more than the code was.** Both were built on internal reasoning
                              > without checking the reference the whole design is modelled on — and the reference
                              > settles both against me.
                              >
                              > 1. **`Turn off this link` — removed.** Flighty has no revoke control. I added one
                              >    because `revoke_invite()` existed and was unwired, and treated "an RPC with no
                              >    caller" as a gap to fill. It is not: the fine print promising a 48-hour link is
                              >    the design's answer to a mis-sent invite, and a link that expires on its own
                              >    needs no button. The RPC stays for a future settings surface.
                              > 2. **Reuse of a live link — reverted** (`20260831130000_revert_invite_reuse.sql`).
                              >    Justified as making revoke coherent; with revoke gone, what remained was that a
                              >    sender "cannot reason about their outstanding invites", which the app never asks
                              >    them to do — there is no list of links, only the code on the sheet. The reference
                              >    mints a new id per share, which was *observed*, not assumed. Case 10 of
                              >    `invites_test.sql` now pins mint-always, because re-adding reuse is one line and
                              >    nothing else would notice.
                              > 3. **The fake notification toggles — removed, and this one stands.** See Task 7.
                              > 4. **The code on the sheet — removed.** "Or read them the code: K7M2QP4X", tappable
                              >    to copy, defended in the class doc as a deliberate divergence because "a sender may
                              >    need to read it down a phone". The copy did not parse — *them* refers to nobody on
                              >    a screen the sender is looking at alone — and the premise was invented: **the
                              >    recipient gets the code from the landing page, not from the sender.**
                              >    `libstack.app/i/<token>` prints it and copies it inside the tap that leaves for the
                              >    App Store, and `InviteCodePage` reads it back. The typed tier is complete and none
                              >    of it passes through the sender's eyes. The sheet is now the reference's shape
                              >    exactly.
                              > 5. **The link is minted on tap, not on open** — which fixed a real bug reported from
                              >    the device: **the button arrived greyed out and came alive a second or more later.**
                              >    `create()` ran in `initState` and `activated` was gated on its result, so the
                              >    sheet's only action was dead on arrival for as long as an RPC took.
                              >
                              >    The eager call was justified by "the code has to be on screen before anyone decides
                              >    how to send it", which stopped being true at (4). What remained was a fear of a
                              >    spinner between the intention and the share sheet — backwards: **latency belongs
                              >    after the commitment, not before it.** Two things fell out: opening and closing the
                              >    sheet no longer writes a row to `friend_invites`, which matters now that reuse is
                              >    reverted; and it matches the reference, which mints on button press.
                              >
                              > The common fault: four times in this phase I built past the reference on the strength
                              > of an argument that sounded tidy — and in the last case invented the user scenario that
                              > justified it. Cost: two migrations, two widgets, six strings and a test file.
                              > **Check the drawings and the reference before adding a control.**

                              Also fixed, and this one was a real defect: **a link tapped while the app was already
                              running did nothing.** `pendingInviteTokenProvider` was read only by `SplashPage` and
                              `AuthPage`, both startup-only, so the *common* arrival case was the broken one.
                              `InviteLinkListener` fixes it; `test/invite_link_listener_test.dart` pins it.

                              **The CTA is `Continue`, not `Share invite`** — the reference's label. It reads wrong
                              for a second, which is why `invite_sheet.dart` carries a note: this sheet is an
                              explainer standing between the reader and the system share sheet, so the button
                              advances past the explanation rather than naming the destination. "Share invite" made
                              the tap feel like the commitment, and then the real share sheet asked again — two
                              share-shaped buttons in a row, the first of which does not share.

- [x] Consent screen: full-screen, one button. **No Decline** — `✕` is the refusal.
- [x] Success screen with the seal, `Done`, and the outlined per-friend notification action.
- [x] The `invite-code` entry screen. **Continue with the field empty is the skip** — that is what
      "optional" means here, and it is why there is no second action. It must never block signup.
- [x] Distinguish expired / revoked / exhausted, using Task 4's result.

---

## Task 8: tests and verification

> **Done.** Five new files — `invite_flow_test.dart` (19), `manage_friend_test.dart` (5),
> `friends_empty_states_test.dart` (7), `friendship_symmetry_test.dart` (7),
> `visit_bar_gear_test.dart` (3) — plus `invite_mark_render_preview.dart`, which is a
> renderer rather than a test: the mark either sells the payoff or looks like three grey
> rectangles, and no assertion can tell those apart.
>
> **`flutter test`: 901 passing, 3 failing, and the count moved for a reason.** The baseline
> was 826/5. Two of those five failures were in `library_read_books_test.dart`'s
> `UserLibraryPage` group, which is deleted along with the page — so three pre-existing
> failures remain, all in the same file, none touched.
>
> **`flutter analyze lib test`: zero errors and zero warnings.**
>
> The harness gained a routes table. `pumpHome` built a `MaterialApp` with `home:` and no
> routes, so any `pushNamed` from the shell threw instead of navigating — which is the
> difference between a test that exercises a destination and one that proves a button
> exists.
>
> **All four checkers green**, and the citations had drifted exactly as the risk table said
> they would: six in the drawings and eleven across the spec and plan pointed at deleted
> files or moved lines. Those naming `user_library_page.dart`, `friend_info_dialog.dart` and
> `search_user_page.dart` are now marked deleted rather than repointed — they are historical
> claims about why this work happened, and a line number for a file that does not exist is
> worse than no citation at all.

- [x] Widget tests for the four new screens, Given-When-Then per `flutter-tester`.
- [x] `test/library_read_books_test.dart` (that override is deleted with the page) — the one broken override. Repoint or delete.
- [x] Friendship is symmetric read from both sides.
- [x] Removing a friend revokes both directions.
- [x] `flutter test` — **expect 826 + new, still exactly 5 pre-existing failures.**
- [x] `flutter analyze lib test` — no new issues in a touched file.
- [x] `python3 docs/mockups/friend-requests/verify.py` and `cite_check.py --show`. The drawings cite
      27 line numbers across files this plan edits, and **they will drift as you work.** `--show`
      prints the content at each cited line; range checking alone cannot detect drift, and it already
      passed a citation pointing at an unrelated `Padding`.

---

## Task 9: the link tiers — deferred, and not blocking

> **Specced 2026-08-30:** `docs/superpowers/specs/2026-08-30-invite-landing-design.md` covers the
> receiving half — the `/i/<token>` route, the two association files, and the app-side listener.
> Read it before starting any of the below; it carries three findings this checklist predates.
>
> 1. **There is currently no way for a recipient to accept an invite at all.** `libstack.app` has
>    no HTTPS listener, and `InviteCodePage` is registered in `AppRoutes.routes` but **nothing
>    pushes it** — so neither the link tier nor the typed-code floor beneath it has an entry point.
>    The "working floor" this plan relies on is not actually wired.
> 2. **The page cannot name the inviter without a new RPC.** `friend_invites` SELECT is
>    owner-scoped (`supabase/migrations/20260828120000_friendships.sql:126-127`), so an anonymous
>    visitor reads nothing. A display-fields-only `invite_preview()` is the one backend change the
>    landing page needs.
> 3. **The App Store listing is live but two years stale.** Verified 2026-08-30 against
>    Apple's lookup API: `trackId` 1643321634, v1.0.6, **last updated 2022-09-24**.
>    `APP_IDENTITY.md:46` was right and `2026-08-19-phase-5-card-sharing-plan.md:62` was wrong;
>    both are corrected in place. The shipped binary predates the Supabase migration and cannot
>    redeem an invite — **which is an argument for releasing, not for building a holding state
>    into the landing page.** The installed tier went first only because it is testable on a
>    development build.

> **Built 2026-08-30.** The receiving half now exists: `~/dev/libstack-web` (**its own repo** —
> a public website is not one of this app's backends, and it brought 343 MB of `node_modules`
> with it), `invite_preview()` + 6 SQL cases, `InviteLinkService` + 10 Dart cases, and the iOS
> entitlement. **Deployed the same day:** `https://libstack.app/i/<token>` is live on the
> `andrew-chung` Vercel scope, AASA serves `200 application/json` with no redirect, and
> `invite_preview` is applied to production (11 friendships and 10 invites unchanged; the
> 6-case suite passes against prod). The Team ID turned out to be in the repo already —
> `58P4CVB7L8`.
>
> Outstanding: a route into `InviteCodePage` (the clipboard handoff's landing point), and an
> App Store release. Android remains deliberately absent.
>
> **Corrected same day:** the page briefly shipped a `NEXT_PUBLIC_STORE_READY` gate that hid
> the store CTA and said "about to land on the App Store" while the listing was stale. Wrong
> — this work _is_ the release, so a pre-release mode is a state nobody should ever see, and
> a real recipient saw it. The CTA is unconditional now.
>
> **Trap recorded in the spec:** `vercel alias set` attaches a domain to a _deployment_, not
> to the project, so Deployment Protection still applied and AASA answered `302` to an SSO
> page — which would have killed Universal Links silently. Register the domain on the
> project instead.

- [x] Add `app_links`. **The listener filters to `/i/` before acting** — `main.dart:36-41`
      recorded a race between a second `app_links` subscriber and Supabase's OAuth observer
      over a single-use PKCE code. `inviteTokenFromUri` refuses every other URI, including
      the custom-scheme callback, and the test asserts that case first: a regression presents
      as intermittent sign-in failure, not as an invite bug.
- [x] ~~**Give `InviteCodePage` a route.**~~ **Reverted, and the page deleted.** See the
      note at the end of this task.

      Offered once after sign-in from `AuthPage` only, gated by a persisted flag. Not
          after a tapped link (that path burned the chance — the reader had already spent a
          token), and never from the splash page, whose branch is an _existing_ session and
          would ambush every current user with a "One last thing" signup step on first launch.

          Building it surfaced a design fault worth recording: the first version read
                                  `sharedPreferencesProvider`, which throws unless overridden, so `AuthPage` — and
                                  three of its existing tests, which have no reason to know invites exist — broke.
                                  That was the coupling being wrong, not the tests. `InviteCodePrompt` read the
                                  `SharedPreferences` singleton directly and sign-in depended on nothing new.

> **Superseded: the typed-code tier is gone entirely.** `InviteCodePage`,
> `InviteCodePrompt`, the `/invite_code` route and their l10n strings were deleted. **Do
> not re-add them.** Two reasons, in order:
>
> 1. **"Invite code" is the shape a referral code will want.** Those are different things
>    with different lifetimes and different server logic, and one eight-character field
>    cannot serve both without rejecting the other's input under a misleading error. The
>    name is reserved for referrals.
> 2. A per-install "offered once" flag cannot tell a new reader from a new _device_, so
>    every reinstall and every second phone met an existing user with a signup step. The
>    fix for that (comparing `auth.users.created_at` against `last_sign_in_at`) was
>    written and then deleted with the rest of the tier.
>
> **A friendship is now created by following a link and by nothing else.** The accepted
> cost is the deferred tier: a reader who installs from `libstack.app/i/<token>` and opens
> the app cold has no invite until they tap the link again. The landing page's
> copy-to-clipboard (in `~/dev/libstack-web`) is now vestigial and should be dropped there.

- [ ] iOS Universal Links: `associated-domains` in `Runner.entitlements`, which today holds only
      `aps-environment`. Bundle ID `com.unicorn.bookwormFriends` is permanently frozen
      (`APP_IDENTITY.md:40`), so AASA is stable as soon as the Team ID is to hand. **This can go
      first.**
- [ ] **Android App Links must wait.** `assetlinks.json` is keyed to package name plus signing
      SHA-256, and `APP_IDENTITY.md:82-95` expects `applicationId` to change on Play re-registration —
      `com.unicorn.bookworm_friends` may not even be reusable. Publishing now pins it to a name that
      is about to change.
- [ ] A trap for whoever writes the two files: iOS is `com.unicorn.bookwormFriends`, Android is
      `com.unicorn.bookworm_friends`. AASA takes `<TeamID>.` prefixed camelCase; `assetlinks.json`
      takes snake_case.
- [ ] `bookworm-friends://` is already registered on both platforms (`ios/Runner/Info.plist:28-31`,
      `android/app/src/main/AndroidManifest.xml:42`) and serves the OAuth redirect. It can carry a token today, but dies in
      in-app webviews and cannot do deferred — a bonus tier, not a substitute.

---

## Risks

| risk                                                           | mitigation                                                                             |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Task 2 drops `follows` in the transaction that reads it        | dump first, rehearse on a branch, verify all six call sites with role-switched probes  |
| the `profiles` inlined copy is missed                          | it is step 3 of Task 2 and the reason the migration is atomic; the six probes catch it |
| a write inserts a non-canonical pair                           | normalise with `least`/`greatest` at every site; the check turns a miss into a raise   |
| 13 people silently lose a shelf they could see                 | accepted by decision; none of the 13 targets is private                                |
| backfill numbers are from the dump, not production             | re-run before migrating; the migration must not depend on the counts                   |
| citations in the drawings drift as this plan edits those files | `cite_check.py --show` before and after each task                                      |
| `poke_user()` looks fixed but the relay is still open          | stated in Task 3 and below; do not report poke as secured                              |

---

## Deliberately not in this plan

- **The `send-notification` open relay, and the FCM v1 migration.** A live hole — no auth at all — but
  pre-existing, and folding it into an already-large migration makes both harder to review. It very
  likely does not work today either: it posts to the decommissioned legacy `fcm/send` endpoint with
  `Authorization: key=`. **Its own spec, and it should be soon.** Nothing in Phase 1 depends on it.
- **Whether the inviter gets a push when someone redeems.** The one thing here that would need FCM v1.
- **The two per-friend notification toggles**, if they slip. `manage-friend` becomes identity plus
  Remove, and the success screen loses its secondary button. There is no per-friend notification
  preference anywhere in the app today.
- **PostHog behind the existing `AnalyticsSink`.** One class, zero call-site changes.
- **The five pre-existing `library_read_books_test.dart` failures.**
- **`public-profiles`** stays a browsable rejected version in the drawings, not built.
