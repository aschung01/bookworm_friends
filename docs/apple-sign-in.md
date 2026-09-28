# Sign in with Apple

Recorded 2026-09-26, when the provider was found to be off and the 1.1.0 submission
blocked on it. Every value below was verified against the App Store Connect API rather
than assumed — see the inventory section.

## The one fact everything else follows from

**The app uses Apple's _web_ OAuth flow, not native Sign in with Apple.**
`auth_provider.dart` calls:

```dart
supabase.auth.signInWithOAuth(
  OAuthProvider.apple,
  redirectTo: 'bookworm-friends://home',
);
```

That is `signInWithOAuth`, which opens `SFSafariViewController` and goes through Apple's
REST API — not `signInWithIdToken`, which is what a native `ASAuthorizationAppleIDProvider`
flow would use. Three consequences, and they are the whole reason this document exists:

1. The client ID Apple sees is a **Services ID**, not the app's bundle ID.
2. A **client secret** is required, and Apple expires it every six months. A native-only
   setup needs no secret and never rotates.
3. The **Services ID's Return URL** must point at Supabase, and it is configured in the
   developer portal — not anywhere in this repo.

Native SIWA is Apple's documented best practice for this case ("It is best practice to
use native Sign in with Apple capabilities on those platforms instead"), and it would
remove the rotation chore. It is deliberately **not** done for 1.1.0: it needs a plugin,
a new code path and a test pass, and — more importantly — the 2022 app signed people in
through this same Services ID, so the relay addresses sitting in `auth.users` were minted
against it. Changing flow at the same time as reviving the listing would put that
recovery path at risk for no release-critical gain. Revisit for 1.1.1.

## Inventory — what already exists

Read from `/v1/bundleIds` with the App Store Connect key in `ios/asc.json`:

| Identifier                    | Type        | Capability                                                     |
| ----------------------------- | ----------- | -------------------------------------------------------------- |
| `com.unicorn.bookwormFriends` | `UNIVERSAL` | `APPLE_ID_AUTH` ✅ + App Groups, Associated Domains, IAP, Push |
| `com.bookwormFriends.signin`  | `SERVICES`  | `APPLE_ID_AUTH` ✅                                             |

So **both halves were already registered in 2022** and neither needs creating. The App ID
carries Sign in with Apple, and the Services ID exists under the name "Bookworm Friends
Sign in". Note the account also holds `com.exonverse.signin`, `com.lawi.barGpt` and
`com.exonverse.exonApp` — **other projects on the same team. Do not touch them.**

Fixed values:

|                       |                                                             |
| --------------------- | ----------------------------------------------------------- |
| Team ID               | `58P4CVB7L8`                                                |
| App ID                | `com.unicorn.bookwormFriends`                               |
| Services ID           | `com.bookwormFriends.signin`                                |
| Supabase project      | `fkynxmfnsgtafrsbzwtu`                                      |
| Callback / Return URL | `https://fkynxmfnsgtafrsbzwtu.supabase.co/auth/v1/callback` |
| Domain                | `fkynxmfnsgtafrsbzwtu.supabase.co`                          |
| App redirect          | `bookworm-friends://home`                                   |

## The setup, in the order it has to happen

### 1. Developer portal — the Services ID's Return URL

**This is portal-only.** `/v1/bundleIds` reports the Services ID's `APPLE_ID_AUTH`
capability as enabled but with `settings: null` — the domains and return URLs are not in the
App Store Connect API's surface at all, the same way App Groups are not (see `AGENTS.md`).
There is no scripted path; it has to be done in a browser, once.

**And the list hides it by default**, which is the actual reason it is hard to find: the
Identifiers list filters to _App IDs_, and a Services ID does not appear under that filter.
Change the dropdown at the top right to **Services IDs** — the same control that reads
"Services" on the Keys page — or go straight to:

```
https://developer.apple.com/account/resources/identifiers/list/serviceId
```

Open **"Bookworm Friends Sign in"** / `com.bookwormFriends.signin` (internal resource id
`79G8H6CK83`; the other Services ID in the account, `com.exonverse.signin`, is Exon's).
Then the **Sign in with Apple** row → **Configure**:

- **Primary App ID:** `com.unicorn.bookwormFriends`
- **Domains and Subdomains:** `fkynxmfnsgtafrsbzwtu.supabase.co` — bare host, no scheme, no path
- **Return URLs:** `https://fkynxmfnsgtafrsbzwtu.supabase.co/auth/v1/callback` — full URL with path

Two more snags. **It saves twice**: once in the modal, then again on the identifier page;
leaving after the first discards it. And if Apple offers a domain-association file to verify
ownership, that belongs to _Sign in with Apple for Email Communication_, a different
feature — not needed here, and impossible anyway since nobody can host a file on
`supabase.co`, which is precisely the host Supabase's own docs tell you to enter.

**Expect the existing values to be wrong rather than empty.** The Services ID dates from
2022, when the app talked to a Django/Amplify backend that no longer exists
(`APP_IDENTITY.md` records that the shipped 1.0.6 binary "talks to the defunct
Django/Amplify backend"). Whatever return URL is in there points somewhere dead. Apple
rejects any redirect that is not an exact match, and the failure surfaces as
`invalid_request` or a blank browser sheet, never as anything naming the URL.

The **Primary App ID** selection is the load-bearing one for returning users. Apple scopes
a private-relay address to the primary App ID, so as long as this stays
`com.unicorn.bookwormFriends` the 21 Apple-relay users in `auth.users` get their original
address back and Supabase links them to their existing library. Point it anywhere else and
they land on new, empty accounts.

### 2. The signing key — `G3N83XAQCR`, and it is not on this machine

**There was no existing secret to inspect.** The Supabase field looked populated on first
look, but that was 1Password autofilling a password into it. Clear that field before
saving, or Supabase stores the junk, masks it, and the next person to look decodes a
1Password password and loses an hour.

The Keys section of the portal settles which key is which. Read 2026-09-26:

| Key ID       | Service                | Name                                 | Created    |                                 |
| ------------ | ---------------------- | ------------------------------------ | ---------- | ------------------------------- |
| `39H75C8AHT` | **Sign in with Apple** | (new, 2026)                          | 2026-09-26 | ⬅ **in use** — see below        |
| `G3N83XAQCR` | Sign in with Apple     | Libstack Apple Sign in               | 2022-09-01 | superseded — its `.p8` was lost |
| `YMMSXZTXAG` | Sign in with Apple     | Exon Apple Sign in                   | 2022-05-06 | another project — do not touch  |
| `T43LQX67XD` | APNs                   | Libstack APNs (Sandbox & Production) | 2022-09-01 | push                            |
| `QKZ8QK6SWU` | APNs                   | Libstack APNs Sandbox                | 2026-09-19 | push                            |
| `ZZ9W9FGB8T` | APNs                   | ExonNotification                     | 2022-04-14 | another project                 |

So `~/Downloads/AuthKey_QKZ8QK6SWU.p8` — the only plausible-looking candidate on disk — is
an **APNs key**, and cannot sign an Apple client secret. Its HTTP 401 against the App Store
Connect API was consistent with a service key, which is as far as that test could get; the
portal is what distinguishes APNs from Sign in with Apple. Had it been revoked on the
assumption it was a stale sign-in key, sandbox push would have broken instead.

**`AuthKey_G3N83XAQCR.p8` was not anywhere on this machine** (searched `~/private_keys`,
`~/Downloads`, `~/Desktop`, `~/Documents`, `~/dev`, `~/.ssh`, iCloud Drive). Apple allows a
`.p8` to be downloaded exactly once, so it was unrecoverable. **A replacement key
`39H75C8AHT` was created 2026-09-26**, and lives at `~/private_keys/AuthKey_39H75C8AHT.p8`.
`G3N83XAQCR` can be revoked whenever convenient; nothing uses it.

#### Replacing the key was safe, and here is why

The instinct is that a 2022 key is load-bearing for the 2022 users. It is not. The signing
key authenticates **our server to Apple's token endpoint**; the user's `sub` and their
private-relay address are derived from the Apple ID and the App ID group. **Apple mandating
that this secret be rotated every six months is itself the proof** — identities could not
survive a mandatory twice-yearly rotation if they were tied to the signing key.

So revoking `G3N83XAQCR` cannot affect the 21 relay users' route back to their libraries.
That depends entirely on the Primary App ID in step 1. The only thing that ever used
`G3N83XAQCR` was the Django/Amplify backend, which no longer exists.

Create the replacement under Keys with **Sign in with Apple** enabled and
`com.unicorn.bookwormFriends` as its primary App ID, and save the `.p8` into
`~/private_keys/` beside the App Store Connect key rather than leaving it in `~/Downloads`.
If Apple refuses because of a per-service key limit, revoke `G3N83XAQCR` first — it is ours
and already unusable. **Do not revoke `YMMSXZTXAG`**; that is Exon's.

Then mint the secret:

```bash
.venv/bin/python scripts/apple_client_secret.py --mint \
    --key ~/private_keys/AuthKey_39H75C8AHT.p8 --key-id 39H75C8AHT
pbcopy < build/apple_client_secret.txt
```

It writes to `build/apple_client_secret.txt` at mode 0600 rather than printing, so the
secret stays out of shell history and scrollback; `pbcopy` then moves it to the clipboard
without showing it either.

**Minted 2026-09-26, expires 2027-03-25.** Put a reminder in the calendar for early March —
when it lapses, every Apple sign-in fails at once and nothing in the app or the logs says
why.

```bash
.venv/bin/python scripts/apple_client_secret.py --mint \
    --key ~/private_keys/AuthKey_<NEW_KEY_ID>.p8 --key-id <NEW_KEY_ID>
```

It writes to `build/apple_client_secret.txt` at mode 0600 rather than printing, so the
secret stays out of shell history and scrollback.

### 3. Supabase — the Apple provider dialog

| Field                        | Value                                                    |
| ---------------------------- | -------------------------------------------------------- |
| Enable Sign in with Apple    | on                                                       |
| **Client IDs**               | `com.bookwormFriends.signin,com.unicorn.bookwormFriends` |
| Secret Key (for OAuth)       | the minted JWT from step 2                               |
| Allow users without an email | **off**                                                  |
| Callback URL                 | read-only; this is what step 1 registers                 |

**The Services ID must come first, and this is the trap.** Supabase uses the _first_
entry in Client IDs for the web `signInWithOAuth` flow, while the native
`signInWithIdToken` flow accepts any entry as a valid audience regardless of order. Put
the bundle ID first and native sign-in would still work while web sign-in is rejected by
Apple — which is the flow this app actually uses, so it would simply stay broken. The
bundle ID is included second purely so a future native migration needs no config change;
it is inert today.

**Leave "Allow users without an email" off.** Every recovery path in
`docs/store/listing-1.1.0.md` (Finding 1) works by Supabase matching a provider's
verified email against an existing confirmed-email row. A user admitted without an email
can never be linked to their old library, and would silently get a fresh empty account
instead. Apple returns an address — real or relay — on every sign-in, so the toggle buys
nothing here.

### 4. The redirect allow list, which is not in that dialog

Authentication → URL Configuration → Redirect URLs must include:

```
bookworm-friends://home
```

`signInWithOAuth` passes that as `redirectTo`, and Supabase refuses to redirect anywhere
not on the list. Google sign-in already works through the same scheme, so it is probably
already present — but it is a separate screen from the provider dialog and is the usual
reason a correctly-configured provider still fails on the last hop.

## Verifying it actually worked

A green dialog proves nothing. The app had never once produced an Apple identity, so the
check is whether a row appears:

```sql
select provider, count(*) from auth.identities group by 1;
```

Before this work: 2 `google`, 1 `email`, **zero `apple`**. After enabling the provider and
signing in on a device: **1 `apple`**, created 2026-09-27 21:02. So the mechanism works and
App Review can get into the app — which was the submission blocker.

### But Apple returned no email — which looked like it broke the recovery story

**Resolved further down: this was the repeat-authorization rule, and linking does work.** Kept
because the reasoning is what narrowed the question, and because a future no-email result
should be read the same way rather than investigated from scratch.

The identity that arrived carries no `email` claim at all:

```json
{
  "iss": "https://appleid.apple.com",
  "sub": "000286.eec5a94f080548408bbff66a9853bc0a.0936",
  "email_verified": true,
  "custom_claims": { "auth_time": 1790542926 }
}
```

`auth.users.email` is **NULL** on that row, a fresh profile was created for it (138 now,
from 137), and it holds **0 books**. Three consequences:

- **Supabase cannot link it to anything.** Every recovery path in Finding 1 works by
  matching a provider's verified email against an existing confirmed-email row. With no
  email there is nothing to match, so the account is an orphan rather than a reunion.
- **"Allow users without an email" must now be ON.** With it OFF, GoTrue rejects a
  provider that returns no email, so the sign-in would have failed instead of creating
  this row. That is the toggle this document told you to leave off, and the reason it gave
  is exactly what happened.
- **There is no fallback identifier.** `public.profiles` has no legacy provider-id column
  (`id, username, emoji, fcm_token, created_at, updated_at, avatar_path, handle`), and the
  migrated rows have no identities, so no Apple `sub` was ever stored for the 21
  relay-address users. They cannot be matched by `sub` either.

### Two explanations, and the one test that separates them

**A: the repeat-authorization rule.** Apple returns `email` only on the _first_
authorization of an App ID by a given Apple ID; afterwards the app is listed under Settings
→ Apple ID → Sign in with Apple and only `sub` comes back. If this Apple ID authorized
`com.unicorn.bookwormFriends` in 2022 — which the 20 `privaterelay.appleid.com` rows say
_someone_ did — then this is expected, and it means **every one of those 21 users will hit
the same wall**.

**B: the email scope was never requested.** `signInWithOAuth(OAuthProvider.apple)` passes
no explicit `scopes`, so if the default omits `email`, Apple would never send one even on a
first authorization.

The test that distinguishes them, on the same device — **after** deleting any existing Apple
identity for that Apple ID, for the reason in "The leftover test account" below:

1. Settings → [your name] → Sign in with Apple → Libstack → **Delete**, then **Stop Using**.
   The button is called Delete now; Apple renamed it when Apple ID became Apple Account, and
   their iOS 26 guide spells it "Tap Delete, then tap Stop Using". **Do not touch "Manage
   Hide My Email" or Settings → iCloud → Hide My Email** — deactivating or deleting a relay
   _address_ is a different action, and Apple retain a deleted one for 30 days and then
   destroy it permanently without ever reissuing it. That would wipe out the only key
   linking a 2022 Apple user to their library. Revoking preserves it: "If you choose to use
   Sign in with Apple again, you're signed in to the same account that you previously used."
2. Sign in again, choosing **Hide My Email** at the consent screen — the path 20 of the 21
   migrated users took.
3. Re-run the query above plus
   `select email from auth.users order by created_at desc limit 1;`

An email arriving means **A** — the flow is correct and returning Apple users need either
that revoke dance or a manual merge. No email still means **B**, fixable by passing
`scopes: 'email name'` in `auth_provider.dart`.

**Do not flip "Allow users without an email" back off before running that test.** With it
off, a returning 2022 Apple user cannot sign in at all — an opaque failure, which is
arguably worse than an empty library. Which way that trade falls depends on the answer.

#### Answered 2026-09-28: it is **A**, and linking works. ✅

The test was run with **Share My Email** rather than Hide My Email, against the Apple ID
whose address already had a 2022 account. Apple returned `email` **and** `name`, and GoTrue
attached the identity to the existing user:

```
user aschung1005@gmail.com   created 2022-08-24, 75 books
  raw_app_meta_data {"provider":"google","providers":["google","apple"]}
  identity google  2026-08-10  sub 116562595125455951580
  identity apple   2026-09-28  sub 000286.eec5a94f080548408bbff66a9853bc0a.0936
                              email aschung1005@gmail.com, email_verified true
```

Totals unchanged across it — 137 users, 137 profiles, 473 books; identities `apple:1,
email:1, google:2`. So:

- **B is dead.** Apple sends `email` and `name` with no explicit `scopes`. **No change to
  `auth_provider.dart`** — and if one is ever made, it is not for this reason.
- **The email-matching path is proven end to end**, which is the mechanism all 21 Apple-route
  users depend on. It linked rather than duplicating, so the Services ID is correctly grouped
  under the primary App ID and step 1 needs no revisiting.
- **The earlier no-email result is explained**, not outstanding: that Apple ID had authorized
  the App ID before, which is precisely A.

What remains unproven is one notch narrower than the original question: whether a **returning
2022 user** is handed back their _original_ `@privaterelay.appleid.com` address. Share My
Email cannot answer that, and neither can any Apple ID that did not authorize this app in 2022. See "The relay check, for later" below for the query that settles it the moment a real
one signs in.

One side effect worth knowing about, since it is now the expected shape of an account:
`app_metadata.provider` stayed `"google"` while `providers` grew to both. Settings drew its
provider mark from the singular field and so showed Google alone on an account where Apple
demonstrably works — fixed in `lib/ui/widgets/sign_in_identity_row.dart`, which draws one mark
per entry in `providers`.

### What this costs the listing copy

The en-US What's New, already published, says "Sign in with the same Apple ID or Google
account you used before and your shelves will be waiting." For Google that is proven. For
Apple it is **now proven too — for an Apple ID that shares a real address.** What is still
unproven is the Hide My Email case, which is 20 of the 21 Apple-route users.

So the sentence is no longer false, but it is broader than the evidence. The safety-net
sentence after it — "If your shelf comes up empty, reach out and I will reconnect it by hand"
— remains load-bearing. Softening the Apple half is a judgement call rather than a
correction; re-publish with `scripts/asc_version.py --publish-copy` if it changes.

### The leftover test account

`11ccb8fe-09f8-4bb2-a248-2b638853e681` was the orphan created by the first test: null
email, 0 books, one profile. **Deleted 2026-09-27**, and the profile cascaded with it — back
to 137 users, 137 profiles, 473 books, 0 Apple identities.

**It had to go before the test could mean anything, and the reason generalises.** GoTrue
resolves an OAuth sign-in by looking up the identity by `(provider, sub)` _first_, and only
falls through to matching a verified email against an existing user when no identity is
found. The Apple `sub` is stable across revoke-and-reauthorize — it is scoped to the Apple
ID and the App ID group, not to the consent — so with that orphan in place, signing in again
would have matched it by `sub` and never reached the email step at all. The test would have
shown whether an email arrives while saying nothing about whether linking works.

So any future test of the _linking_ path has to start from no Apple identity for that Apple
ID. Deleting the app's authorization in Settings is not sufficient on its own.

### One note on the toggle

"Allow users without an email" was confirmed **OFF** after the fact, which reconciles with
the orphan only if it was on during that first sign-in and turned off afterwards — the
likely sequence, since the provider was being configured at the time. OFF is the
configuration to keep: with it off, an Apple response carrying no email makes the sign-in
**fail** rather than silently minting another unlinkable account. A hard error is the better
signal, and it cannot fragment a returning reader's data.

The warning above about not turning it off before the test is therefore spent — the test has
been run, with the toggle off, and it succeeded.

### The relay check, for later

An Apple sign-in does return an email now, so this is live: it says whether the 21 are being
reunited or duplicated, the first time one of them signs in.

```sql
select email, created_at::date from auth.users
where email like '%privaterelay.appleid.com' order by created_at desc limit 5;
```

A brand-new relay row dated today means the relay is being minted fresh and those users are
**not** being reconnected — which points at the Primary App ID in step 1. The 20 existing
relay rows are all dated 2022, so a new one is unambiguous.

## The button, which App Review checks separately

Apple's HIG says plainly: **"App Review evaluates all custom Sign in with Apple
buttons."** Ours is custom, it is the first thing on the first screen, and per
`docs/store/listing-1.1.0.md` the review notes tell the reviewer it is their only way
into the app. It had three faults at once, all fixed 2026-09-27:

**It drew the wrong artwork.** `appleBlackIcon.svg` and `appleWhiteIcon.svg` were
Apple's _logo-only button_ files — "Black Logo Square" and "White Logo Square" — each
carrying an opaque 44×44 plate behind the glyph. On our black button the white-plated
one rendered as a pale square with a black apple inside it, so what read as the logo
was the plate. Apple: "Use the logo file to position the Apple logo in a button; never
use the Apple logo as a button", and "within a button, both items must be either black
or white". Both files are gone, replaced by `assets/icons/appleLogo.svg` — Apple's own
path, plate removed, cropped tight to the glyph, tinted at the call site.

The same asset was drawn at 18pt in Settings' provider row, where the white plate was
invisible on the light theme's white surface and a bright square on the dark theme's
`#1E1E1E`. **That is why the fix is one tintable glyph rather than a swap**: picking
between two plated files meant picking a background as well as an ink, and getting it
wrong was invisible in one theme and glaring in the other.

**The logo was a third of the right size.** `height: 20` on a 56-unit canvas holding a
19-unit glyph put the Apple logo at **6.8pt in a 48pt button — 14%**, where Apple's
artwork puts it at 19-in-44, or 43.2%.

**The title was two thirds of the right size.** It inherited Material's 14pt, which is
29% of a 48pt button against Apple's published 43%.

The button is now **44pt**, Apple's recommended default and iOS's minimum touch
target, which makes both derived numbers integers: Apple's artwork is a 19-unit glyph
in a 44-unit face, so the glyph is exactly **19pt** and the title — 43% — is **19pt**
too. At the old 48 both came out at 20.64.

**The title is w400, and it was w600 for one round.** That first version inherited
`AppTextStyles.label`'s weight, which looked too heavy — correctly, and for a reason
worth keeping: `label` is a **13pt** token, and weight perception scales with size, so
the same w600 at 19pt is a visibly bolder object. Weight is not a compliance question
("Title font. You can also adjust the font's weight and size"), so this was settled by
rendering 400 / 500 / 600 together and looking.

**500 won that comparison and was still refused.** Google's branding guidelines specify
Google Sans _Medium_ for their own button and ask for "similar visual weight" across
providers, so Medium is where both references sit. But Pretendard ships here at
400/600/700/800 — `scripts/build_fonts.py` subsets exactly those — so 500 means a sixth
face and roughly **1.2MB for one label**. That is the purchase this project already
refused for DesignHouse, which "shipped 750KB for one label" and is why it sits in
`assets/fonts/` unregistered. At 19pt the extra size does the work the extra weight was
doing.

Four things not to undo:

- **`kSignInContentRatio` is `19 / 44`, written as a fraction.** It is Apple's artwork
  in its own units; a decimal would hide where it came from.
- **The title's size is in `AppTextStyles.signIn`, not at the call site.**
  `text_style_test.dart` refuses a `fontSize:` in `lib/ui` and was right to catch the
  first attempt: "a call site that needs a size the scale does not have is telling you
  the scale is wrong, not that it needs an exception." The cost is a seam — the 19pt
  and the 19/44 that justifies it live in different files — and
  `sign_in_button_test.dart` asserts they still agree.
- **`GoogleIcon` has no `color` parameter any more.** It is four brand colours and
  Google forbid recolouring it; the old parameter flattened the mark to one blob.
  `AppleLogo`'s colour is required for the opposite reason.
- **`_SignInButton.icon` is a `Widget`, not an asset path.** As a string the two marks
  looked like the same kind of thing, which is how a black apple on a white plate
  ended up on a black button.
- **Don't ask for w500 without registering the face.** Pretendard has no Medium in the
  bundle, so the engine would answer with a neighbouring cut — the same trap
  `AppTextStyles.spine` records for asking Gowun Batang for an 800 it does not ship.
- **The render preview loads Pretendard-Regular, not SemiBold.** `FontLoader` carries no
  weight information, so the cut it is handed is the cut everything draws in. Loading
  SemiBold there would render the title in the weight that was rejected — the preview
  would keep showing the old button while the app shipped the new one.

Judge changes with `flutter test test/sign_in_button_render_preview.dart`, which writes
to `build/signin_preview/` — both themes, plus the old and new glyph side by side. A
green suite blessed the broken button for its whole life, so **look at the render**.
Note `BrandMark` comes out as a bare green plate there; that is the preview's
limitation, not a defect.

## Rotation

The secret expires six months after minting. When it does, every Apple sign-in fails at
once and nothing in the app or the logs says why. Re-run step 2's `--mint`, paste, save.

To check whether an expired secret is the cause, decode whatever is live — a JWT payload
is only base64, so this needs no key:

```bash
pbpaste | .venv/bin/python scripts/apple_client_secret.py --decode -
```

It reports the signing `kid`, the team, the client ID and the expiry, and flags any of
those that disagree with the values in this document. Useless right now (there is nothing
configured yet), but it is the first thing to run the day sign-in breaks for everyone at
once.
