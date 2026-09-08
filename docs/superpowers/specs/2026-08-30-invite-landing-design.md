# `libstack.app/i/<token>`: the receiving half of an invite

Status: **built and deployed 2026-08-30.** `https://libstack.app/i/<token>` is live,
AASA serves correctly, and `invite_preview()` is applied to production. The remaining
gate is an App Store release — see _Outstanding_.

| piece                 | where                                                            |
| --------------------- | ---------------------------------------------------------------- |
| the page              | `libstack-web/app/i/[token]/page.tsx`                            |
| the clipboard handoff | `libstack-web/app/i/[token]/get-the-app.tsx`                     |
| AASA                  | `libstack-web/app/aasa/route.ts` + a rewrite in `next.config.ts` |
| the preview RPC       | `supabase/migrations/20260830120000_invite_preview.sql`          |
| its test              | `supabase/tests/invite_preview_test.sql` (6 cases)               |
| the link listener     | `lib/services/invite_link_service.dart`                          |
| its test              | `test/invite_link_service_test.dart` (10 cases)                  |
| the entitlement       | `ios/Runner/Runner.entitlements`                                 |

**The website lives in its own repository: `~/dev/libstack-web`.** It was built at
`web-invite/` inside this repo and moved out the same day, which was the right
correction: this repo's root _is_ the Flutter app — `pubspec.yaml`, `lib/`, `ios/`,
`android/` — and everything else at that level (`supabase/migrations`,
`supabase/functions`) is a **backend this app talks to**. A public website with its own
domain, its own Vercel project and its own release cadence is not that. It also brought
the repo's first `node_modules`: 343 MB across 9,161 files, against Deno edge functions
that carry none.

The two are coupled by a **contract, not by code** — the token alphabet, the `/i/` path,
and the bundle ID in AASA — all of which are already restated in three runtimes because
nothing can share code across Dart, plpgsql and TypeScript. When the marketing site and
the `/@handle` pages from `docs/mockups/landing-page/` are built, they belong in
`libstack-web` too: same domain, same deploy.

Scope: the web route an invite link points at, the two association files that let an
installed app claim that URL instead, and the app-side plumbing that receives it. It is
the counterpart to `2026-08-28-friends-invites-design.md`, which specified the sending
half and deferred this as Task 9.

## Context

### The sending half works and the receiving half does not exist

`create_invite()` mints a token, the invite sheet shows it, and Share puts
`https://libstack.app/i/<token>` into a message. `redeem_invite(token)` writes the
friendship correctly and distinguishes every failure. All of that is live in production
as of 2026-08-29.

What is missing is everything between the two:

| piece                                     | state                                                                      |
| ----------------------------------------- | -------------------------------------------------------------------------- |
| `libstack.app` DNS                        | resolves (`216.198.79.65`, Vercel)                                         |
| `libstack.app` HTTPS                      | **no listener** — `SSL_ERROR_SYSCALL`; plain HTTP returns 404              |
| `/i/<token>` route                        | **does not exist**                                                         |
| `/.well-known/apple-app-site-association` | **does not exist**                                                         |
| `/.well-known/assetlinks.json`            | **does not exist**                                                         |
| `associated-domains` entitlement          | **absent** — `ios/Runner/Runner.entitlements` holds only `aps-environment` |
| Android `https` intent filter             | **absent** — `AndroidManifest.xml` registers the custom scheme only        |
| `app_links` dependency                    | **absent** from `pubspec.yaml`                                             |
| a route that pushes `InviteCodePage`      | **none** — the page is registered in `AppRoutes.routes` and unreachable    |

So today a shared link is a well-formed URL pointing at a dead host, and the typed code
has no entry point in the running app. **There is currently no way for a recipient to
accept an invite.** That is the gap this closes.

### The drawings already designed this page

`docs/mockups/friend-requests/index.html` carries two frames that are exactly this
route — the `invite-deferred` flow's _Landing page_ and _Store_ screens — plus the
KakaoTalk frame that specifies the OG card. This spec does not re-decide any of that; it
records what those frames commit to and fills in what a drawing cannot say.

Three things the drawings settled, quoted because they are load-bearing:

- **"'Get the app' copies the token inside the click handler, then redirects — the copy
  has to happen in the same user gesture or Safari drops it."** This is the whole iOS
  deferred tier.
- **"The link preview is the whole tier: an unbranded URL in a group chat does not get
  tapped."** The OG card is not decoration; it is the reason the link gets opened at all
  in this app's primary market.
- **"Drawn, not designed: the page itself is being built separately, so this frame
  commits only to what the invite tier depends on."** The visual treatment below is
  therefore proposed, not settled; the _contract_ is what matters here.

### What is not this document

`docs/mockups/landing-page/` is a 6,216-line mockup of a **different** site — the
marketing home page and `/@handle` public profile pages from Phase 5's card sharing. It
has no `/i/` route. The two share a domain and nothing else, and its open questions
(profile-visibility consent, re-implementing `GeneratedCover` in TypeScript) do **not**
gate this route. Ship `/i/` without touching it.

## Decision

### One route, four audiences

`GET /i/<token>` is served to four different visitors and must answer each differently.
They are distinguished by what the _client_ is, never by the token.

| visitor                     | what happens                                                 |
| --------------------------- | ------------------------------------------------------------ |
| a crawler fetching OG tags  | HTML with `og:*` and nothing else that matters               |
| a phone **with** the app    | the OS claims the URL via AASA and the page never renders    |
| a phone **without** the app | the page renders: inviter named, payoff shown, `Get the app` |
| a desktop browser           | the same page, with the code shown and no store redirect     |

The third case is the only one with real logic in it, and the second is the one to get
right first because it is the common case for an existing user.

### The page is a bridge, not a product

Its single job is **to get the token into the app**. Every element earns its place
against that:

1. `ShelfDuo` — the inviter and you, the same mark the consent screen uses.
2. `<inviter> invited you` — the hero. Named, because an unnamed invite is spam.
3. One paragraph of payoff, matching `inviteBody`.
4. **The code, stated in plain text.** `Your code is K7M2QP4X — we'll fill it in for you.`
5. `Get the app` — the primary action, which copies then redirects.
6. `Continue without copying` — the escape for anyone who declines the paste prompt.

No navigation, no footer links, no marketing. A reader who arrived here was sent by a
friend and is one tap from a store; anything else on the page competes with that tap.

### The token is opaque to the web tier, and that is a deliberate limitation

**The page cannot name the inviter without a server-side read, and the client cannot do
that read.** `friend_invites` is owner-scoped by RLS:

```sql
CREATE POLICY "Inviter can read own invites" ON public.friend_invites
  FOR SELECT USING (inviter_id = auth.uid());
```

An anonymous visitor has no `auth.uid()`, so an anon-key fetch returns nothing. That
policy is correct and must not be relaxed — the spec's own reasoning is that a token must
not expose its owner's identity to whoever holds it.

Two ways out, and the choice matters:

- **A. A `SECURITY DEFINER` RPC returning only display fields.** `invite_preview(token)`
  returns the inviter's `username`, `emoji`/`avatar_path`, and whether the link is still
  live — never the `inviter_id`, never anything else on the row. Called from the Next.js
  **server**, with the anon key, at request time.
- **B. Render the page with no name.** "Someone invited you", which the app already has
  a string for (`someone`).

**Recommended: A**, with B as the automatic fallback whenever the RPC returns nothing.
The drawings are explicit that the named inviter is what makes the tier work, and the
information disclosed — a username and an emoji — is exactly what the recipient is about
to see anyway if they accept. The new RPC is small and its shape is the guard: it returns
_display_ fields, so a leak would have to be written in deliberately.

**This is a new migration and it is the only backend change this spec requires.** It must
be `SECURITY DEFINER`, `SET search_path = ''`, `GRANT EXECUTE ... TO anon`, and it must
not increment anything or record a visit — a preview is not a redemption.

A rate limit belongs on it. It is the one anonymous, token-guessing surface in the
system, and 32^8 makes brute force impractical but not free.

### `Get the app` and the same-gesture clipboard write

The iOS deferred tier hangs entirely on one constraint, which the drawings state and
which is easy to get wrong:

```js
button.addEventListener("click", () => {
  navigator.clipboard.writeText(token); // synchronous, inside the gesture
  window.location.href = storeUrl; // then leave
});
```

`await` before the write, or writing it in a `.then()`, loses the user-activation and
Safari silently refuses. The redirect must come after, in the same handler.

`Continue without copying` is a plain link to the store with no clipboard write, for the
reader who declines or distrusts the paste prompt. It is not a second CTA — it is the
opt-out that makes the first one safe to attempt.

### Where `Get the app` points, and the release that gates it

**Resolved 2026-08-30 against Apple's lookup API.** An earlier draft of this section
recorded a contradiction between `APP_IDENTITY.md:46` ("live on the App Store") and
`2026-08-19-phase-5-card-sharing-plan.md:62` ("none — pulled years ago"). The listing is
real:

| field            | value                                       |
| ---------------- | ------------------------------------------- |
| `trackId`        | **1643321634**                              |
| name             | 책벌레 친구들 — 친구들과 함께하는 독서 기록 |
| `bundleId`       | `com.unicorn.bookwormFriends` — matches     |
| version live     | **1.0.6**                                   |
| released         | 2022-09-05                                  |
| **last updated** | **2022-09-24**                              |
| ratings          | 2, average 5.0                              |
| storefront       | KR, free                                    |

So `APP_IDENTITY.md` is literally right and the two plan documents are literally wrong
— but the plans were right about the thing they were using the claim for. Two ratings and
nothing shipped since 2022 is not an installed base worth protecting, and every decision
those plans took on that basis stands.

**The CTA is an App Store link, unconditionally.**

```
https://apps.apple.com/kr/app/id1643321634?pt=invite&ct=invite_link
```

**The live binary is v1.0.6 from September 2022, which predates the Supabase migration**
(`2026-05-04-flutter-supabase-migration.md` describes the backend it talks to as the
"defunct Django/Amplify backend"). It has no `friendships` table, no `redeem_invite`, no
invite UI, and almost certainly cannot sign in. `pubspec.yaml` is at `1.1.0+1`; the store
is two years behind it.

**That is a release problem, not a page problem.** An earlier draft concluded the
opposite — that the page should detect the stale store and show a holding message — and
that was a mistake serious enough to record: it shipped, and a real recipient saw
"Libstack is about to land on the App Store" on a live invite. The page has no
pre-release mode. **The build being made here is the build going to the store**, and
the fix for a two-year-old binary is to submit a new one.

The two tiers still ship independently, which is worth knowing for sequencing:

| tier                        | needs                       | works before a release? |
| --------------------------- | --------------------------- | ----------------------- |
| recipient **has** the app   | AASA + `associated-domains` | **Yes**                 |
| recipient **needs** the app | the store CTA               | once the release lands  |

The installed case is testable today on a development build, which is why it went first.

Android has no listing; the account was closed. The campaign parameters are still worth
carrying on both: the drawings note that `pt`/`ct` on the App Store and `referrer` on Play
give install counts by source for free, and Play's `referrer` is the same channel the
Android deferred tier later reads the token back out of.

**Two things the lookup turned up that are not blockers but should not be lost:**

- **`languageCodesISO2A: ["EN"]`** — the listing is registered English-only despite
  wholly Korean metadata. KO is the primary market. Fix on the next submission.
- **The store name is still 책벌레 친구들, not Libstack.** The rename was display-name-only
  by design (`APP_IDENTITY.md`), and that was correct for the app itself. It is a
  different matter on this page: a landing page headed "Get Libstack" that redirects to a
  store listing with another name is a trust gap on the one screen whose whole job is
  converting a stranger who arrived from a friend. Either the listing name changes with
  the next release, or the page has to acknowledge both names.

### The two association files

Both are static, both live at the domain root, and both are exacting.

**`/.well-known/apple-app-site-association`** — no file extension,
`Content-Type: application/json`, served over HTTPS with **no redirect**. The OS enforces
all three and none can be stubbed locally.

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["<TeamID>.com.unicorn.bookwormFriends"],
        "components": [{ "/": "/i/*" }]
      }
    ]
  }
}
```

`/i/*` only. Claiming `/` or `/*` would hand the app every future marketing page on the
domain, including the `/@handle` profiles that are designed to be _web_ pages.

**`/.well-known/assetlinks.json`** — **do not publish this yet.** It is keyed to package
name plus signing-certificate SHA-256, and per `APP_IDENTITY.md:82-95` the `applicationId`
is expected to change on Play re-registration; `com.unicorn.bookworm_friends` may not even
be reusable. Publishing now pins the file to a name that is about to change.

**The trap, restated because it has its own line in the plan:** the platforms' identifiers
differ in more than case. iOS is `com.unicorn.bookwormFriends` (camelCase, `<TeamID>.`
prefixed); Android is `com.unicorn.bookworm_friends` (snake_case). Neither is `libstack`.

### App-side: receiving the URL

Four changes, and one of them is the thing that has been quietly missing.

1. **Add `app_links`** to `pubspec.yaml`.
2. **`associated-domains`** in `ios/Runner/Runner.entitlements`:
   `applinks:libstack.app`. Requires the Team ID.
3. **A link handler** that parses `/i/<token>`, matches it against the server's alphabet
   (`^[A-HJ-NP-Z2-9]{8}$` — the same rule `invite_code_page.dart` already filters on) and
   routes to `AppRoutesInvite.inviteConsent` with an `InviteConsentArgs`.

   **Two arrival cases, and the first version only handled the rarer one.**
   `pendingInviteTokenProvider` was written by the service and read by `SplashPage` and
   `AuthPage` — both of which run once, at startup. So a link tapped during a cold
   start worked, and a link tapped **while the app was already running** did nothing at
   all: iOS foregrounded the app, the token landed in the provider, and no screen was
   watching. Since the app is usually already running when a message is tapped, the
   common path was the broken one.

   `InviteLinkListener` (in `MaterialApp.builder`, beside `ShellChrome`) fixes it with a
   `ref.listen`. The two paths cannot collide by construction: `ref.listen` never fires
   for a value that already exists when it mounts, and a cold-start token is in the
   provider before `runApp` — so `SplashPage` still owns that case, which it must,
   because consent has to be pushed _onto_ a library that does not exist yet at that
   point. Asserted in `test/invite_link_listener_test.dart`.

4. **A route into `InviteCodePage`**, which today nothing pushes. This is the paste
   target for the deferred tier: the page already reads the clipboard in `initState` and
   accepts a token-shaped string, so the landing page's copy lands correctly the moment
   the page is reachable. Show it once after signup.

**`main.dart` has a warning that applies directly here**, and it is the highest-risk part
of this work:

> There is deliberately no deep link listener here. `Supabase.initialize` already starts
> one (`SupabaseAuth._startDeeplinkObserver`) and exchanges the OAuth code it finds. A
> second listener raced it — `app_links` is a singleton that hands the one URI to every
> subscriber — over a single-use PKCE code, so one of the two exchanges always failed.

So the invite listener **must not** be a second naive `AppLinks().uriLinkStream`
subscriber that reacts to every URI. It must ignore anything that is not
`https://libstack.app/i/...` and leave the OAuth callback strictly alone. This bug has
already been hit once in this codebase; it will look like intermittent sign-in failure,
not like an invite bug.

### Sign-in ordering

`redeem_invite()` returns `not_signed_in` when `auth.uid()` is null, and the model already
handles it. But the _flow_ has to decide what happens next, and the drawings put consent
before signup only for a reader who already has an account.

The rule: **hold the token, sign in, then redeem.** A tapped link on a fresh install lands
on auth; the token survives the round trip and the consent screen is shown after. Losing
the token during sign-in is the most likely way to break this tier, and it is invisible —
the reader simply arrives on their empty library with no idea an invite existed.

## Dependencies

- **A current build on the App Store**, for the deferred tier only. The live binary is
  1.0.6 (2022-09-24) and cannot redeem an invite. The _installed_ tier does not depend on
  this and should go first.
- **The Apple Team ID** is needed for AASA. Nothing else about it is blocking; the bundle
  ID is frozen and known.
- **A Vercel project** on `libstack.app`. There is none — the domain is on Vercel
  nameservers with nothing served.
- **`invite_preview()`** — one new migration, if option A is taken.
- **Android is deliberately out of scope** until the Play account decision.

## Testing

- **AASA is served correctly** — HTTPS, no redirect, `application/json`, no extension.
  Apple's own fetcher is the authority; a `curl -I` that shows a 301 means it is broken.
- **The clipboard write survives the gesture** on a real iOS Safari. This cannot be
  tested in a headless browser, because user-activation is the whole mechanism.
- **The OG card renders** in KakaoTalk specifically, not just in a validator. It is the
  market that matters and its crawler is not Facebook's.
- **`invite_preview()` refuses to leak.** Assert as `anon` that it returns display fields
  and no `inviter_id`, and that a garbage token returns nothing rather than raising.
- **The OAuth flow still works after the link listener lands.** Regression test the
  sign-in path, not just the invite path — see the `main.dart` warning.
- **A tapped link on a device with the app installed never renders the page.** This is
  the common case and the easiest to leave broken, because it looks fine in a browser.

## Risks

| risk                                                                         | mitigation                                                                |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| the new link listener races Supabase's OAuth observer                        | filter to `/i/` before doing anything; regression test sign-in            |
| `assetlinks.json` published against a doomed package name                    | do not publish it; Android waits for the account decision                 |
| AASA served with a redirect or the wrong content type                        | the OS enforces silently — verify with `curl -I`, not by eye              |
| the clipboard write is moved out of the click handler                        | it is one line and it looks harmless to refactor; comment it at the site  |
| `invite_preview()` grows fields over time                                    | it returns display fields only; adding `inviter_id` is the leak           |
| the store CTA ships before a current build, so invitees install the 2022 app | the installed tier ships first; the store CTA is gated on a release       |
| the token is lost across sign-in on a fresh install                          | hold it explicitly; the failure is silent and looks like nothing happened |

## Deliberately not done

- **Probabilistic IP matching.** Carried over from the parent spec: it is the
  fastest-degrading part of the vendor offering and Korean carrier NAT makes it worse
  than average.
- **Android App Links**, until `applicationId` is settled.
- **The `/@handle` profile pages** and the marketing home page. Different mockup,
  different open questions, no dependency in either direction.
- **Any deep-link vendor.** The parent spec rejected all of them with reasons; nothing
  here changes that.

## Outstanding

Two things need credentials nobody in this repo has, and one needs a release. Everything
else is built and verified locally.

1. ~~**The Apple Team ID.**~~ **Resolved — it was already in the repo.** `58P4CVB7L8`,
   in all three build configurations of `ios/Runner.xcodeproj/project.pbxproj` and in
   `ios/ExportOptions.plist`. AASA serves `58P4CVB7L8.com.unicorn.bookwormFriends`. It
   was listed as blocked on an external credential when it needed a `grep`.
2. ~~**`NEXT_PUBLIC_SUPABASE_ANON_KEY`.**~~ Set on the Vercel project, along with
   `NEXT_PUBLIC_SUPABASE_URL`. Not secret — both already ship in the app binary.
3. ~~**Apply `invite_preview()`.**~~ Pushed to production. Verified: friendships and
   invites unchanged at 11 and 10, the 6-case suite passes against production, and an
   `anon` probe of a live token returned the real inviter (`독서하는 유니콘`, 🦄) with
   `used_count` unmoved — a preview spends nothing.
4. ~~**`InviteCodePage` has no route.**~~ **Done.** Offered once after a sign-in, from
   `AuthPage` only, gated by `InviteCodePrompt` (persisted in `SharedPreferences`).
   Three rules, all tested:

   - **Once per install**, surviving relaunch — continuing with an empty field _is_ the
     skip, so re-offering it would turn a decline into nagging.
   - **Never after a tapped link.** That path routes straight to consent and burns the
     one chance, because asking "have you got a code?" of someone who just spent one is
     asking them to repeat themselves.
   - **Never from the splash page.** That branch is a reader who already had a session,
     and the screen opens with "One last thing" — signup language. Offering it there
     would ambush every existing user with a signup step on their first launch after
     this ships.

> **Removed 2026-08-30: the `NEXT_PUBLIC_STORE_READY` gate.** An earlier version of this
> spec had the page hide the store CTA and say "Libstack is about to land on the App
> Store" until a current build shipped. That was wrong, and it went live before it was
> caught.
>
> The reasoning was that the store serves v1.0.6 from 2022, which cannot redeem an
> invite — true, but it does not follow that the _page_ should ship a pre-release state.
> **This work is the version being released.** Building a temporary mode for the window
> before that release invents a state that should never be seen by anyone, and it
> shipped exactly that: a live page telling a real recipient to keep a code and wait.
>
> The correct handling of "the store is stale" is to release, not to add a mode to the
> page. The CTA is now unconditional.

### Deployed

`libstack-web` on the **`andrew-chung`** scope (not `typa`), apex `libstack.app` only.
Verified on the live domain:

| check                         | result                                                |
| ----------------------------- | ----------------------------------------------------- |
| AASA                          | `200`, `application/json`, **0 redirects**            |
| `/i/W78LKADB` (real token)    | `200`, names 독서하는 유니콘 in `<h1>` and `og:title` |
| `/i/w78lkadb` (lowercased)    | `200`                                                 |
| `/i/K7M2QP40` (ambiguous `0`) | `404`                                                 |
| `/i/W78LKADB/x`               | `404`                                                 |

**The trap that nearly shipped: Vercel Deployment Protection.** The first AASA request
on the live domain returned **`302` to `vercel.com/sso-api`**, which would have killed
Universal Links silently — the OS refuses a redirect and reports nothing.

The cause is subtle and worth recording. The project's `ssoProtection` is
`all_except_custom_domains`, which _should_ have exempted it — but `vercel alias set`
attaches a domain to a _deployment_ without registering it as a **project domain**, so
Vercel did not consider it custom and applied SSO. Fixed by adding it through
`POST /v10/projects/:id/domains`. **Use that, or the dashboard, not `alias set`.**

`www.libstack.app` is deliberately not attached: it 404s, and the apex is the only AASA
host.

### What was learned building it

**AASA took four attempts, and three of them fail silently.** Recorded in the route
handler so none is retried:

1. A static file in `public/.well-known/` — extensionless statics are served
   `application/octet-stream`, which iOS declines without a word. Measured.
2. A `headers()` override in `next.config.ts` over that file — the static handler sets
   Content-Type afterwards and wins. Also measured; still `octet-stream`.
3. A route handler at `app/.well-known/…/route.ts` — App Router treats a dot-prefixed
   folder as private and returns **400**.
4. A plainly-named `/aasa` route plus a **rewrite**. A rewrite is invisible to the
   client, so it does not trip the no-redirect rule a redirect would.

Verified end to end: `200`, `application/json`, `num_redirects=0`.

**The token filter is the sign-in guard, not just a parser.** `inviteTokenFromUri`
refuses the `bookworm-friends://` OAuth callback explicitly, and
`test/invite_link_service_test.dart` asserts that refusal first — because a regression
there presents as intermittent login failure, not as an invite bug.
