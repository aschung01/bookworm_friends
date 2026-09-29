# Email and password, beside the two vendors

Add email/password **sign in**, **sign up** and **password reset** to the sign-in screen,
without touching the two OAuth buttons and without adding a second deep-link subscriber.

Nothing in `supabase/migrations/` changes. See _No migration_ below.

## What was asked, and the three things it was not

The request was "username & password sign in & sign up". Resolved, in order:

1. **The first field is an email address, not a username.** A true username login means
   minting synthetic addresses (`alice@users.libstack.app`), which forecloses password reset
   entirely — for an app holding a reading history built over years, an unrecoverable
   account is a data-loss bug with a UI. It would also turn `profiles.username` into a
   credential, so `updateProfile.updateUsername` could no longer let anyone rename
   themselves at will, and the racy `checkUsernameAvailable` lookup would need a real unique
   constraint behind it. **`profiles.username` keeps its current job**: a display name, set
   after signup, and the key for `poke_user()` and search.
2. **Email confirmation is on.** So `signUp` returns a user with **no session**, and the
   flow has a third state — _check your inbox_ — that neither OAuth path has.
3. **Password reset ships in the same change**, because (2) means there is a verified
   address to send it to. Without it, a forgotten password is the same lockout that ruled
   out (1).

## The constraint everything follows from

**`Supabase.initialize` already runs the only deep-link observer this app is allowed to
have.** `main.dart` and `invite_link_service.dart` both carry the long version: `app_links`
is a singleton delivering one URI to every subscriber, and an earlier unfiltered second
listener raced Supabase's own over a single-use PKCE code, so one of the two exchanges
always failed. `InviteLinkService` is safe only because it reacts to
`https://libstack.app/i/<token>` and nothing else.

Confirmation links and recovery links are exchanged by that same existing observer. So this
feature adds **no link handling at all** — it only has to read what the exchange emits.

**And the exchange emits enough.** Verified in the pinned `gotrue-2.20.0`:
`resetPasswordForEmail` stores the event name alongside the PKCE verifier
(`gotrue_client.dart:970`, `'$codeVerifier/${AuthChangeEvent.passwordRecovery.name}'`), and
the exchange replays it (`:382`) to emit `passwordRecovery` rather than `signedIn`.

**Therefore the redirect URL's path is not information and must not be treated as any.**
Both flows reuse `bookworm-friends://home`, already allowlisted for OAuth. A distinct path
like `bookworm-friends://reset-password` is the obvious spelling and the wrong one: it
implies somebody parses it, and the only component that could is a second subscriber. It
also means **no change to the project's redirect allow list**.

## Decisions

### A third button, and a separate page behind it

`auth_page.dart` gains one `_SignInButton` — _Continue with email_ — pushing a new
`EmailAuthPage`. The form does **not** go inline on the sign-in screen.

That page is a centred `Column` with no scroll view, and two fields plus a submit, a mode
toggle and a _Forgot password?_ link is ~230pt of new content with a keyboard up: the
`RenderFlex` overflow the streak celebration is recorded hitting on a 375×667 phone. Inline
would also put form state, error state and submission into the file that already owns
`_leaveIfSignedIn` and `_spendPendingInvite`.

**The email-first two-step flow that Google and Apple use is rejected**, not deferred: the
second step needs an "is this address known?" probe, and Supabase deliberately refuses to
answer one (see _Sign-up never reports a collision_).

### The third button costs 18pt of cat, and `_kLockupHeight` must move with it

`_kLockupHeight` is a spelled-out constant rather than a measurement because `_MascotHero`
sizes itself from it **in the same layout pass** — a `GlobalKey` would only be readable next
frame, so the cat would visibly pop. A third button therefore has to be added to that sum,
`+12 +44 = 56`; forgetting it puts the cat's ears through _Continue with email_.

On an iPhone SE (375×667, top inset 20, bottom 0):

|                   | now   | with 3 buttons |
| ----------------- | ----- | -------------- |
| `_kLockupHeight`  | 300   | 356            |
| room under lockup | 157.5 | 129.5          |
| mascot height     | 132.5 | 132.5          |

The clamp binds in both columns, so **nothing visibly changes** — but it needs
`room ≥ 132.5 × (1 - 0.16) = 111.3`, leaving **18.2pt of slack on the smallest supported
phone**. A fourth button would not fit, and the existing `height < kAuthMascotHeight / 3`
bail still covers landscape and split view.

### The button is brand green, not a second white plate

`colors.brandFill` (#067657) with white text and a white `Icons.mail_outline`, at
`kSignInButtonHeight * kSignInContentRatio` like the other two marks. `brandFill` is the
token authored to carry white text and is dark in both themes for exactly that reason — the
same argument `read_week_row.dart` records for `stampMark`, and the trap `kStatTileCool`
records from the other direction.

White-on-white was the alternative and is worse: Google's button is already a white plate
with black text, so the app's own door would read as a twin of a vendor's. Apple's
prominence rule is satisfied by equal size and first position; they explicitly permit
adjusting logo spacing to align with other providers.

### Recovery pushes **on top**; `_leaveIfSignedIn` is not touched

A recovery session is a real session. `status == AuthStatus.authenticated` is read in four
places — `auth_page`, `splash_page`, `settings_page`, `invite_link_listener` — so a new
`AuthStatus.recovering` would break all four, and gating only `auth_page` misses the cold
start, where the link launches the app and `SplashPage` does the routing.

**So navigation is allowed to happen and the set-password screen is pushed over whatever
lands.** This is the pattern the codebase already argues for twice, in
`AuthPage._spendPendingInvite` and `SplashPage._pushConsentIfPending`: pushed _onto_ the
destination "so dismissing leaves the reader somewhere real", never replacing it.

**The first version of this design had `_leaveIfSignedIn` refuse to navigate while
recovering.** It is recorded here because it is the obvious fix and it is wrong in a way
that only shows up on a cold start — on a warm one it appears to work.

Dismissing without setting a password leaves the reader signed in with the old one. That is
accepted: it is what the session actually is, and a screen that cannot be dismissed is worse
than one that can.

### `_leaveIfSignedIn` must clear the stack, not replace the top of it

One line in `auth_page.dart` does have to change, for a reason that has nothing to do with
recovery:

```dart
Navigator.pushReplacementNamed(context, AppRoutes.home);   // before
Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (_) => false);  // after
```

**`pushReplacement` replaces the navigator's topmost route, not the route that called it.**
Today `AuthPage` _is_ the top, so the two spellings agree. With `EmailAuthPage` pushed over
it they do not: a confirmation link arriving while the reader is looking at _check your
inbox_ disposes `EmailAuthPage`, pushes home — and leaves **`AuthPage` still sitting
underneath it**.

That is invisible on iOS and a live bug on Android, where system back pops home and reveals
the sign-in buttons. `_leaving` is already `true` by then, so `_leaveIfSignedIn` will not
fire again and the reader is **stranded on the sign-in screen while holding a valid
session** — precisely the bug `auth_page_navigation_test.dart` exists to pin, reintroduced
through a route that did not exist when it was written.

The sign-in stack is not history worth keeping once there is a session, so clearing it is
also the honest spelling. `_spendPendingInvite` still pushes consent onto home afterwards,
giving `[home, consent]` exactly as before, and the existing tests still read correctly:
`_RouteLog` counts `didPush` as well as `didReplace`, and the `_leaving` guard is what makes
"navigates once" pass, not the choice of navigation method.

### `recovering` is state on `AuthState`, not an event

```dart
const AuthState.passwordRecovery(User user)
  : this(status: AuthStatus.authenticated, user: user, recovering: true);
```

A flag rather than a one-shot notification, because the exchange can complete **before any
listener mounts** — the same race `AuthPage.initState` documents and the reason
`InviteLinkListener` defers the cold-start case to `SplashPage`. Persisted state is what
lets `PasswordRecoveryListener` catch it with a post-frame read of the current value in
addition to `ref.listen`.

**Every other session-bearing event preserves the existing `recovering` value rather than
clearing it.** `tokenRefreshed` fires roughly hourly for the life of a session; clearing on
it would drop the flag mid-recovery. `signOut` and `deleteAccount` clear it by returning
`AuthState.unauthenticated()`.

`status` stays `authenticated` throughout, so `currentUserIdProvider` and every gate keep
working and nothing downstream learns this feature exists.

### `AuthNotifier`'s new surface

| method              | returns              | notes                                       |
| ------------------- | -------------------- | ------------------------------------------- |
| `signUpWithEmail`   | `EmailSignUpOutcome` | `confirmationSent` \| `signedIn`            |
| `signInWithEmail`   | `void`               | throws `AuthException`                      |
| `sendPasswordReset` | `void`               | `resetPasswordForEmail(…, redirectTo:)`     |
| `updatePassword`    | `void`               | `updateUser`, then clears `recovering`      |
| `dismissRecovery`   | `void`               | clears `recovering` with no password change |

**`signUpWithEmail` returns a value rather than throwing or returning `void`.** With
confirmation on there are two successes — session now, or mail sent — and an exception
cannot carry the distinction. The page renders a different phase for each.

### One page, three modes, two phases

`EmailAuthPage` (route `/email_auth`, in the ordinary `AppRoutes.routes` table) holds
`signIn | signUp | reset` × `form | sent`. _Forgot password?_ is the third **mode** rather
than a fourth route: it is one field and one button, and a separate page would duplicate the
email field, its validation and its error mapping.

`SingleChildScrollView` with `viewInsets` padding — the thing inline placement could not
afford, and the whole reason this page exists.

`autofillHints` on both fields so iOS Keychain offers to save and fill.

**No confirm-password field.** A visibility toggle is the modern answer and reset is the real
backstop for a typo. Client-side minimum is 6 to match Supabase's own default, so the reader
is not round-tripped for it; the server still enforces `weak_password`.

### Sign-up never reports a collision

Supabase's email-enumeration protection returns a deliberately indistinguishable response
for an address that already has an account, so the page shows _check your inbox_ either way
and **never** "that email is taken". Correct posture, and less code than trying to read
`user.identities.isEmpty`, which is ambiguous by design.

### Errors map through a pure function

`String emailAuthError(Object, AppLocalizations)` over `AuthException.code`:
`invalid_credentials`, `email_not_confirmed`, `weak_password`,
`over_email_send_rate_limit`, `validation_failed`, else generic. Pure, so every branch is
unit-testable without pumping a widget.

One branch is not a server code: **`Code verifier could not be found in local storage.`**
PKCE keeps the verifier on the device that _requested_ the reset, so tapping the link on a
different device cannot complete. It gets its own message — "open this link on the device
that asked for it" — rather than falling into the generic case, which would read as a bug.

### No migration

`handle_new_user`, as replaced in `20260821100303_add_profile_handle.sql`, inserts
`(id, generate_handle())` on **any** `auth.users` insert regardless of provider, and the
Google-avatar branch in `20260819160000_auto_import_google_avatar.sql` is gated on
`raw_app_meta_data ->> 'provider' = 'google'`, so an email signup falls through it cleanly.

An email signup therefore lands with a handle and a null `username` — `needsOnboarding` —
which is exactly where an OAuth signup lands, and `SplashPage` already routes that to
`AppRoutes.settings`. The new path inherits onboarding for free.

**Note the pre-existing quirk it inherits along with it**, so it is not mistaken for damage
this change did: `_leaveIfSignedIn` goes to `home` unconditionally, and only `SplashPage`
consults `needsOnboarding`. So a reader who signs up lands on their (empty) library and is
not asked for a display name until the _next_ cold start. That is already true of both OAuth
buttons and is left alone here.

### `closeInAppWebView` stays unguarded

`_apply` calls it on every transition out of signed-out, and email sign-in opens no browser.
Checked rather than assumed: it is a no-op when nothing is presented, and the confirmation
link opens the system browser rather than an in-app one, so there is nothing to suppress and
no provider-specific branch to add.

## Components

| file                                             | change                                                |
| ------------------------------------------------ | ----------------------------------------------------- |
| `lib/providers/auth_provider.dart`               | `recovering`, 5 methods, 1 branch in `_apply`         |
| `lib/ui/pages/auth_page.dart`                    | third button, `_kLockupHeight` 300 → 356, stack clear |
| `lib/ui/pages/email_auth_page.dart`              | new: form, 3 modes, 2 phases                          |
| `lib/core/email_auth_error.dart`                 | new: the pure error mapper                            |
| `lib/ui/pages/new_password_page.dart`            | new: `fullscreenDialog` via `onGenerateRoute`         |
| `lib/ui/widgets/password_recovery_listener.dart` | new: beside `InviteLinkListener`                      |
| `lib/constants/app_routes.dart`                  | `emailAuth`, `newPassword`                            |
| `lib/main.dart`                                  | mount the listener in `MaterialApp.builder`           |
| `lib/l10n/app_en.arb`, `app_ko.arb`              | ~26 keys, Korean written rather than translated       |

`NewPasswordPage` is a `fullscreenDialog` for the reason `shareCard`, `scanBook` and
`readingStreak` are: a focused, dismissible context that is the one thing on screen, with
`CupertinoPageRoute` so the transition is the same on both platforms.

## Data flow

```
sign up ──> signUp(emailRedirectTo:) ──> no session ──> phase: sent
              │
              └─ tap mail link ──> Supabase's observer ──> signedIn
                                          └──> _leaveIfSignedIn ──> home
                                               (clearing EmailAuthPage *and* AuthPage)

reset ────> resetPasswordForEmail(redirectTo:) ──> phase: sent
              │
              └─ tap mail link ──> Supabase's observer ──> passwordRecovery
                                          ├──> _leaveIfSignedIn ──> home
                                          └──> listener ──> push NewPasswordPage on top
```

## Tests

51 new cases; the suite is **1972 green** with no errors or warnings from `flutter analyze`.

- `email_auth_page_test.dart` — mode toggle, validation, submit reaches the notifier, error
  renders, `sent` phase renders, and sign-up with a known address still says _check your
  inbox_. Also the 375x667-with-keyboard case that is this page's whole reason for existing.
- `email_auth_error_test.dart` — every branch of the mapper, including the local-storage
  verifier case and a non-`AuthException` input, since the page hands it whatever `catch`
  caught.
- `password_recovery_test.dart` — `recovering` rides on an `authenticated` status; the
  listener presents on a live event **and** on a cold start; it does not stack a second copy;
  it reopens for a second link; `dismissRecovery` leaves the session intact.
- `auth_page_navigation_test.dart` — a case pinning that `recovering` does **not** stop the
  page leaving for home, so the rejected fix above cannot be quietly reinstated; and one
  pinning that a session arriving **while `EmailAuthPage` is on top** leaves nothing below
  the library.

### Two things found by writing them, both corrections to this document

**`auth_hero_test.dart` needed no change, and this spec predicted it would.** It asserts
behaviour — "the mascot never reaches the buttons on a short phone" — rather than the value of
`_kLockupHeight`, so it _checked_ the 18.2pt arithmetic instead of having to be taught it. The
prediction was wrong in the good direction, and it is a point in favour of how that test was
written.

**The stack guard was tautological on the first attempt, and only re-breaking the fix showed
it.** `expect(find.byType(AuthPage), findsNothing)` is the obvious assertion and it proves
nothing: routes beneath an opaque route are offstage, and finders skip offstage widgets by
default, so it passes whether or not the route is still in the navigator's history. Restoring
`pushReplacementNamed` produced a **fully green run**.

The assertion is now `navigator.canPop()`, which reads the history directly and is also
literally the Android back gesture the bug is about. Re-verified the other way: with
`pushReplacementNamed` restored, exactly one case fails, on `canPop()` being `true`.

This is the same trap the streak notes record for `FractionallySizedBox` — measuring the
widget that sizes itself to the constraints it was handed, and so passing on the bug.

## Out of scope, and not by accident

- **Magic links / OTP.** A fourth door on a screen that now has three, and confirmation
  already proves the address.
- **Changing the password from Settings.** Different entry point, different screen; nothing
  here blocks it.
- **Linking an email password onto an existing OAuth account.** Supabase treats these as
  separate identities; merging them is its own design.

## Manual steps this change cannot make

1. **Enable the Email provider and confirm "Confirm email" is on** in the project's Auth
   settings. No MCP tool reaches auth config; the whole design assumes confirmation on, and
   with it off the `sent` phase becomes unreachable dead code.
2. Nothing in the redirect allow list — `bookworm-friends://home` is already there for
   OAuth, which is the point of reusing it.
