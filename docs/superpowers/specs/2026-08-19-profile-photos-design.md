# Profile photos

**Date:** 2026-08-19
**Status:** Implemented — see "Amendments during implementation" below

## Context

The avatar is one emoji. `profiles.emoji` is `text` capped at 16 code points
(`widen_emoji_columns`), picked from the same sheet as praise, and drawn at
**40×40** by `AvatarCircle`. There is no image anywhere in the identity path, and
no Supabase Storage in the project at all — no buckets, no `storage.from(...)`
call in `lib/` or in any migration. The only `storageBucket` strings in the tree
are Firebase config for FCM.

Two facts about the current code shape the work more than the feature does.

**Every profile read is a bare `select()`.** `profileProvider`,
`followingListProvider`, `followerListProvider` and `searchUsersProvider` all
select `*`, so a new column reaches `Profile.fromJson` with **no query changes**.
All seven test fixtures build `Profile` with named optional parameters, so a new
optional field breaks nothing.

**The avatar is drawn six times, and only two go through `AvatarCircle`.**
`friend_rail.dart:77` and `friends_sheet.dart:256` use the widget; the friend
info dialog (`friend_rail.dart:109`), `settings_page.dart:361`,
`search_user_page.dart:114` and the follow-list sheet (`settings_page.dart:862`)
bypass it with a bare `Text`. Between them the six disagree three ways about the
fallback glyph — `📖`, `📚`, and the empty string. Harmless while every avatar is
an emoji; the moment some users have photos and some do not, it is three
different answers to the same question.

## Decision

**A private bucket, read through the authenticated object endpoint.**

The privacy model is the reason. `is_profile_visible()` gates shelves, books and
memos on _public OR self OR you-follow-them_. Storage does not inherit that, so a
public bucket would make the profile photo the one thing `is_private` does not
cover. That is the worst kind of inconsistency: invisible until it is a support
ticket, and unfixable afterwards, because a public object URL that has escaped
cannot be recalled. Having already paid for `is_profile_visible` three times,
paying a fourth is cheaper than explaining the gap.

The usual objection to private buckets is that signed URLs expire, which costs a
signing round trip per screen and defeats URL-keyed image caches. **That
objection does not apply here**, and it is worth being explicit about why,
because it removes most of the cost:

`storage_client` resolves `download()` to `GET {url}/storage/v1/object/{bucket}/{path}`
with the client's headers attached. That endpoint enforces RLS per request and
its URL contains **no signature**. So the URL derived from `avatar_path` is
_stable and permanent_, and authorisation moves into an `Authorization` header
where an HTTP cache does not see it. No `createSignedUrls` batching provider, no
expiry bookkeeping, no cache key that rotates out from under the disk cache. It
is strictly better than the signed-URL design for this shape of read, and it is
also strictly better than a public bucket, which has the same cache properties
with none of the access control.

## 1. Schema

```sql
ALTER TABLE public.profiles ADD COLUMN avatar_path text;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_avatar_path_owned
  CHECK (avatar_path IS NULL OR avatar_path LIKE id::text || '/%');
```

Store the **object path** (`{user_id}/{random}.jpg`), never a URL. A URL column
would bake in the bucket, the project ref and the public-vs-authenticated choice,
all of which are things we might change; the path survives all three.

The `CHECK` is the interesting half. Without it, `avatar_path` is a
client-supplied string that a user could point at somebody else's object — the
storage read would still be authorised against the _folder owner_, so a private
user could quietly wear a public user's face. The constraint costs one line and
closes it, in the same spirit as `profiles_emoji_length`.

**`emoji` stays.** It is the avatar for the majority of users who will never
upload anything, and it is the mode a profile returns to when a photo is removed.
It is **not** a fallback for a failed photo — see the amendment below, which
reverses the original draft on this point.

Migration created with `supabase migration new add_profile_avatar`, applied with
`supabase db query --linked`, recorded with `supabase migration repair`.

## 2. Bucket and policies

```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', false, 1048576, ARRAY['image/jpeg']);

-- Your own folder, all four verbs. The path's first segment is the owner.
CREATE POLICY "Users manage own avatar" ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Everyone else reads an avatar on exactly the rule that governs the books.
--
-- Joined through `profiles.avatar_path` rather than casting the path's first
-- segment to uuid: a cast throws on any object whose folder is not a uuid, and
-- throwing inside a policy fails the whole evaluation rather than denying one
-- row. The join is also strictly tighter -- only the object a profile
-- *currently* points at is readable.
CREATE POLICY "Users read visible avatars" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'avatars'
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.avatar_path = storage.objects.name
        AND public.is_profile_visible(p.id)
    )
  );
```

`file_size_limit` and `allowed_mime_types` on the bucket are the only size and
type checks that actually bind — the client-side ones are a courtesy to the user,
not a defence. 1MB is far above what §4 uploads and still refuses a raw 12MP
photo outright.

Note what is _not_ here: an upsert path. Supabase's upsert needs `INSERT` +
`SELECT` + `UPDATE` together and fails silently with only `INSERT`, which is a
well-known trap. §4 never upserts — each upload gets a fresh random name — so the
trap is sidestepped rather than navigated.

This leans on `is_profile_visible`, which is `SECURITY DEFINER` sitting in the
exposed `public` schema and therefore directly callable through the Data API.
Pre-existing, not introduced here, but this makes it more load-bearing. Worth its
own ticket to move it to a private schema.

## 3. Reading

Build the URL from the path and hand the session's token over as a header:

```dart
String avatarUrl(String path) => '$supabaseUrl/storage/v1/object/avatars/$path';

// apikey and Authorization, matching what SupabaseClient sends itself.
Map<String, String> get _authHeaders => {
  'apikey': supabaseAnonKey,
  'Authorization': 'Bearer ${supabase.auth.currentSession?.accessToken}',
};
```

Read the token at widget-build time rather than capturing it: `supabase_flutter`
refreshes the session in the background, and a captured token goes stale. A disk
cache hit needs no token at all, so refresh churn costs nothing after first load.

`cached_network_image_ce ^4.10.0` for the widget. The original
`cached_network_image` is on 3.4.1 with its last release in **August 2024** and
300-plus open issues including scroll-jank and memory leaks; the fork is a
99%-compatible drop-in on 160/160 pub points with an active release cadence. It
also happens to fit this design specifically: pluggable TTL/LRU eviction lets the
local cache expire, which is the only lever we have over an avatar that stays on
disk after an unfollow.

## 4. Writing

`image_picker ^1.2.3` (flutter.dev) does the whole pipeline:

```dart
final picked = await ImagePicker().pickImage(
  source: ImageSource.gallery,
  maxWidth: 512,
  maxHeight: 512,
  imageQuality: 80,
);
```

`maxWidth`/`maxHeight` resize natively, preserving aspect ratio and copying EXIF
orientation onto the resized file, and `imageQuality` re-encodes as JPEG. That
lands around 40–70KB.

**No cropper, and no compression package.** Both were considered and both are
unnecessary here:

- `image_cropper` needs a `uCropActivity` entry in `AndroidManifest.xml` and an
  iOS pod, to let the user frame an image that renders in a **40px circle**.
  `BoxFit.cover` inside the existing circular container crops visually for free.
  A crop UI is a feature for a 200px profile header, which this app does not have.
- `flutter_image_compress` is the right tool when you need a guaranteed byte
  ceiling, but `image_picker` already resizes natively and the bucket enforces the
  ceiling server-side, so it would be a second native dependency for a
  belt-and-braces check we already have.

Resizing before upload also keeps us off Supabase's on-the-fly image
transformations, which are **Pro-plan gated** ($5 per 1,000 origin images beyond
a 100-image quota). Nothing in this design touches that meter.

Upload, then point the row at it, then clean up:

```dart
final path = '$userId/${_randomId()}.jpg';
await supabase.storage.from('avatars')
    .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
await supabase.from('profiles').update({'avatar_path': path}).eq('id', userId);
if (oldPath != null) await supabase.storage.from('avatars').remove([oldPath]);
```

The order matters and the failure modes are deliberately lopsided. Uploading
before updating means a crash leaves an orphaned object — invisible, and swept up
by §6. Updating before uploading, or deleting before updating, would leave a
profile pointing at nothing, which the user sees. Prefer the orphan.

The random filename is doing double duty: it is why we never upsert, and it is the
cache-buster. A new photo is a new URL, so no `avatar_updated_at` column and no
cache-purge call.

New entry in `ios/Runner/Info.plist`: `NSPhotoLibraryUsageDescription`. No
`NSCameraUsageDescription`, because the picker is gallery-only — the smaller ask,
and nobody takes a selfie for a reading app. Android needs no configuration
(`minSdk` is already 24, which is `image_picker`'s floor; iOS 15 clears its 13).

The prompt string is also added to `en.lproj` / `ko.lproj` `InfoPlist.strings`,
for the same reason the launcher name is localised there: an English permission
dialog in a Korean app reads as unfinished.

Entry point is the existing `changeEmoji` menu in `settings_page.dart`, which
becomes mode-aware: **Set photo / Change emoji / Change nickname** with no photo,
and **Change photo / Remove photo / Change nickname** with one. The emoji route is
unchanged, just not offered in photo mode.

## 5. `AvatarCircle` and the six call sites

One optional field, emoji-first so nothing existing changes:

```dart
class AvatarCircle extends StatelessWidget {
  final String? emoji;        // null → kDefaultAvatarEmoji
  final String? avatarPath;   // null → emoji, exactly as today
  final double diameter;      // 40 everywhere but the settings header (60)
  final double? emojiSize;    // defaults to diameter / 2
  final bool isSelected;
  final bool filled;          // false for the one glyph-on-dialog site
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
}
```

Emoji and photo are **mutually exclusive modes**, so the emoji does not appear
under a loading or failed photo. Photo mode has its own neutral placeholder.

**Consolidate first.** Move the four bare-`Text` sites onto the widget and settle
the fallback glyph on one character before any image code exists. Otherwise the
image path gets written five times and the `📚`/`📖`/`''` disagreement ships as a
visible bug. The glyph lives on the widget as `kDefaultAvatarEmoji` and the sites
pass `profile.emoji` straight through, so there is no `??` left to diverge.

## 6. Deletion

`auth.admin.deleteUser` cascades the `profiles` row; storage objects are not
cascaded and become permanent orphans in a bucket nobody can list.
`supabase/functions/delete-account/index.ts` already runs on the service role, so
it gains a `storage.from('avatars').remove(...)` over the user's folder **before**
the `deleteUser` call — a few lines in a file that exists.

## Dependencies

`flutter pub add --dry-run image_picker cached_network_image_ce` resolves cleanly
against the pinned `path_provider_foundation` / `shared_preferences_foundation`
overrides, changing neither. It adds 20 packages, of which the ones that matter
are `image_picker 1.2.3`, `cached_network_image_ce 4.10.0`, `hive_ce 2.19.3` (the
fork's cache backend), and `octo_image 2.1.0`. The rest are desktop and web
platform implementations pulled in by federated plugins and never compiled into
the iOS or Android build.

## Testing

- `Profile.fromJson` round-trips `avatar_path`, and `avatarExtensionFor`
  normalises a picked filename to something the bucket's `allowed_mime_types`
  will accept — `test/profile_avatar_test.dart`.
- **Network images throw in widget tests.** Flutter's test binding stubs HTTP to
  return 400, so `avatarImageProvider` is the seam. Existing tests stay green
  because every fixture leaves `avatarPath` null.
- The emoji renders when there is no photo. In photo mode the emoji never renders
  at all: loading and failure both show the neutral placeholder, and a loaded
  photo shows the image, at the full diameter, clipped, with `BoxFit.cover`. The
  existing `find.text('🦊')` assertions keep working —
  `test/avatar_circle_test.dart`.
- The avatar adds no gesture recogniser when given no callbacks, so the two sites
  that sit inside a row-level `InkWell` or `ListTile` keep answering taps.
- `profiles_avatar_path_owned` and the two bucket policies are verified against
  the linked database, not locally: a private user's object must be unreadable by
  a stranger, readable by a follower, and unreadable again after the follow is
  dropped. That last case is the whole argument for §2 and the easiest to get
  wrong. Kept as `supabase/tests/avatar_policies_test.sql` rather than run once
  and forgotten, because it also guards `is_profile_visible` and the `follows`
  policies against future edits.

## Risks

**`cached_network_image_ce` is a young fork.** 95 likes and 46.2k downloads
against the original's 6.9k likes — we would be leaving the ecosystem default for
a package with a fraction of the adoption. The counter is that the default is
_stale_, not maintained-and-boring, and the fork is MIT with 160/160 points, so
the exit is the same one the praise spec took: vendor it. Revisit if it ever
blocks a Flutter upgrade. Its pub score also reports "not compatible with Web"
despite the README claiming IndexedDB caching; irrelevant to an iOS/Android app,
but a sign the README runs ahead of the package.

**Moderation was considered and deliberately declined.** Photographs of faces are
not self-moderating the way emoji are, and the app has no blocking model — only
`follows` and `is_private`. Shipping without a report path means the first abuse
case has no answer. Accepted knowingly rather than overlooked; `is_private` plus
unfollow-revokes is the whole of the control surface.

**Cached photos survive an unfollow.** Server-side revocation is immediate; the
copy already on the ex-follower's disk is not. Mitigated by a short cache TTL,
not solved. Probably fine — it is no different from any content they already
saw — but it should be a decision rather than an oversight.

**A stale session shows the placeholder, not the emoji.** Everything in photo mode
degrades to the neutral glyph, so a token-refresh bug would look like "avatars
stopped loading" — which is at least the right shape of complaint, where the
earlier emoji fallback would have made it look like avatars had silently _changed_.
Still worth a log line.

## Amendments during implementation

Seven things the code or review contradicted, recorded rather than quietly
absorbed.

**The emoji is not a fallback for a failed photo. Photo and emoji are mutually
exclusive modes (§5).** This reverses the draft, which made the emoji the
placeholder while a photo loaded and the error state when one failed, on the
principle that an avatar should never depend on the network.

That principle was real but it was applied to the wrong thing. Showing someone's
emoji in place of their photo flashes a **different identity** at the viewer, who
then cannot tell an emoji person from a photo person whose picture has not
arrived — and the substitution reads as a deliberate choice rather than as a
pending state. So photo mode gets its own neutral placeholder (a muted person
glyph), used identically for loading and for failure, because to a viewer those
are the same thing: a photo that is not on screen.

The consequence is accepted knowingly: **for profiles in photo mode the avatar now
does depend on the network.** Emoji-mode profiles — about two thirds of active
users — are unaffected, and they are the majority precisely because emoji mode
costs nothing.

Two things follow. The menu offers _either_ the photo actions or the emoji action,
never both, so it never implies the two stack. And the photo entry reads **Set
photo** when there is nothing there and **Change photo** when there is, since that
label is the only thing telling you which mode you are in. The stored `emoji` is
untouched while a photo is set, so removing the photo hands the previous emoji
straight back — which is why "Remove photo" needs no confirmation.

**There were six avatar sites, not five, and only two used the widget (§5).** The
sketch missed the follow-list sheet at `settings_page.dart:862` — a fourth bare
`Text` in a circle, with `📖` as its fallback. Found only by grepping for
`BoxShape.circle` rather than for `AvatarCircle`, which is the lesson: the sites
that needed consolidating were exactly the ones that did not mention the widget.

**The read policy joins through `profiles.avatar_path` instead of casting (§2).**
The drafted policy cast the path's first segment to `uuid`. Two problems. A cast
throws on any object whose folder is not a uuid, and an exception inside a policy
fails the entire evaluation rather than denying one row — so one malformed object
written by the service role would take the whole bucket offline. And the join is
strictly tighter: only the object a profile _currently_ points at is readable, so
replacing a photo revokes the old one immediately instead of waiting on the
cleanup delete to succeed. The delete is now purely about reclaiming bytes.

**The selection ring had to become a `foregroundDecoration`.** `AvatarCircle` drew
its ring with `Border.all` on the main `BoxDecoration`, which insets the content
box by 2pt on every side. Harmless for a centred glyph, which is why it survived
until now — but it made every photo 4pt smaller than its circle, with a ring of
`surfaceVariant` showing through. A foreground decoration paints over the child
without taking layout space. Caught by asserting the image's size equals the
diameter _while selected_, which is the only state that showed it.

**Deterministic image providers, not `MemoryImage` and `pumpAndSettle`.** The
first draft of `avatar_circle_test.dart` had two tests that contradicted each
other: image decoding is real async work off the test's fake clock, so the frame
never arrived under `pumpAndSettle` — and `MemoryImage` keys on its bytes, so
whichever test ran second got a _synchronous_ `ImageCache` hit and stopped
exercising the load path at all. Replaced with three explicit providers (loaded /
pending / failing) so each state is stated rather than timed.

**`errorBuilder` swallows the failure, so there is nothing to `takeException`.**
Flutter's `Image` only reports an image error to `FlutterError` when no
`errorBuilder` is supplied. The test asserts the visible contract instead — emoji
shown, no `RawImage` painted, nothing thrown. Worth knowing before writing any
other image-failure test in this repo.

**The seam cannot be `@visibleForTesting`.** `avatarImageProvider` is read by
`AvatarCircle` on every build, so the annotation is a lie and the analyzer says
so. It is documented as the seam instead.

Two smaller notes. The package's library file is `cached_network_image.dart`, not
`cached_network_image_ce.dart` — the fork kept the original name, so the import
path does not double the `_ce`. And the edit-profile menu turned out to be defined
_twice_ — once as a `CNPopupMenuButton` dispatching on a hard-coded index, once as
a `showMenuBottomSheet` — so adding photo entries would have meant adding them
in two places and would have silently mis-routed every entry after the insertion
point. Both presentations now build from one `_ProfileEditAction` list, which is
also what made the mode-aware menu above a single change rather than two.

One native detail worth keeping: an SF Symbol name the OS does not recognise is
discarded **silently**, leaving the native menu row with no icon at all (the
hazard `native_glass.dart` already documents). "Remove photo" was first given
`photo.badge.exclamationmark`, which may not exist; it uses `trash` instead. This
fails only on the real iOS 26 native menu — never in tests, never on the Material
fallback — so symbol names want checking by eye on a device.

**The shared emoji sheet was captioning profile emoji as praise, and the strip it
lived in is now gone.** Not caused by this work, but surfaced by it.
`showEmojiBottomSheet` already accepted a `title` override, which the profile
caller used — but `CurrentPraiseStrip` hardcoded `l10n.yourPraise` for the strip
beneath it, so "Edit profile > Change emoji" showed the right heading over a strip
captioning your avatar emoji as praise you had sent.

The first fix threaded a required label through both the strip and the sheet. The
second, and the one that shipped, **deleted the strip entirely** for praise and
profile alike. The strip restated what the marked grid cell already says, and its
"Remove" button duplicated a path that already existed — tapping the emoji you
hold withdraws it, because `praiseTapFor` reads that as removal. A caption that has
to be threaded through two callers to stay correct is a lot of surface for
something that says nothing new.

What is genuinely lost: the _guaranteed_ withdrawal affordance. Tapping to
withdraw needs you to find your emoji, which is easy in the Recents run and hard
if it is a legacy emoji on a device with no local recents. The live data says that
is not a real cost — 39 praises, 8 praisers, **0 in the last 90 days**, so the path
is dormant. If praise ever revives and withdrawal turns out to be hard to find,
the cheap answer is a Remove row on the praise pill itself rather than bringing
the strip back.

Three ARB keys went with it (`yourPraise`, `removePraise`, and the `yourEmoji` this
work had just added), and `showEmojiBottomSheet` lost both `onRemove` and
`selectedLabel`. `selected` stays: it marks your cell, which is now the whole of
the toggle's legibility, so `praise_toggle_test`'s marked-cell test inherits the
job the strip tests were doing.

## Verification against the live database

The migration was applied to the hosted project and checked there: `avatar_path`
reports `text`, `profiles_avatar_path_owned` exists, and the bucket is private
with a 1MB limit and three mime types.

The `CHECK` was exercised inside a rolled-back transaction: a path in the row's
own folder is accepted, and one in another profile's folder raises
`check_violation`.

The two bucket policies were verified with real role switching — `set local role
authenticated` plus forged `request.jwt.claims`, because `postgres` bypasses RLS
and a test without the role change would pass regardless of what the policies
said. All four cases hold: a stranger reads 0 rows for a private profile's
avatar, a follower reads 1, the same follower reads 0 again after unfollowing, and
the owner always reads 1. The harness was then checked against a mutated
assertion to confirm it can actually fail, rather than passing because the query
found nothing for an unrelated reason.

`flutter test` is green at 418 tests, `flutter analyze lib test` reports no errors
(the two remaining warnings in `settings_page.dart` predate this work), and
`flutter build ios --debug --simulator` succeeds with the two new plugins linked.

## Consequences

- `is_private` covers the profile photo on the same rule as the books, and
  unfollowing genuinely revokes.
- The avatar becomes a network-dependent widget for profiles in photo mode, so
  `AvatarCircle` acquires loading and error states it has never had — and the app
  acquires a neutral placeholder glyph it did not previously need.
- Emoji mode is now a first-class choice rather than a default: roughly a third of
  active profiles have set an emoji, and 28 distinct emoji across 33 setters says
  they are chosen, not accepted. Nothing pushes those users toward a photo.
- Storage enters the project. Bucket policies join RLS as a thing to reason about
  on every future feature that touches files.
- The 40×40 render size is now load-bearing: it is the reason there is no cropper
  and no transformation pipeline. A design that grows the avatar — a profile
  header, a bigger library card — reopens both decisions.
