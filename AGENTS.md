# Agent notes

Project-specific facts worth not rediscovering. See `README.md` for setup.

## Never ask for these again

App Store Connect credentials live in **`ios/asc.json`** (gitignored, already on
this machine). It holds `keyId`, `issuerId` and `keyPath` pointing at the `.p8`
private key under `~/private_keys/`. Read that file instead of asking; if it is
missing, the shape is in `release_ios.sh`.

Build-time API keys live in **`env.json`** (gitignored). Every build and run must
inject it, which is what `run.sh` / `build.sh` / `release_ios.sh` are for. A plain
`flutter run` silently degrades book search.

### A fresh worktree has neither, and that is not a missing file

Both of the above are **gitignored, and gitignored files do not travel between git
worktrees**. A new worktree under `.worktrees/` therefore starts without them, and
`./run.sh` stops with `error: env.json not found` — which reads like a setup problem and
is really just a copy:

```bash
cp ../../env.json env.json          # always; nothing builds without it
cp ../../ios/asc.json ios/asc.json  # only to ship from this worktree
```

The same is true of anything else ignored: `ios/Pods`, `ios/Flutter/ephemeral` and
`android/local.properties` all regenerate themselves, so those need no action.
`GoogleService-Info.plist` **is** tracked, so Firebase config is never the problem.

## The Crashlytics build phase is patched, and don't revert it

`project.pbxproj`'s `FlutterFire: "flutterfire upload-crashlytics-symbols"` phase no
longer matches what `flutterfire_cli` generates. Two deliberate changes, both of which a
`flutterfire configure` run would silently undo:

**It looks for the SDK where Flutter actually puts it.** The generated script searches
only `DerivedData/<Runner-hash>/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run`,
and its comment claims `BUILD_DIR` "doesn't have run script". That comment is out of date:
Firebase arrives here through **SPM**, not CocoaPods, and Flutter's SPM integration passes
`-clonedSourcePackagesDirPath`, so the checkout lives under the project's own
`build/ios/SourcePackages` and `DerivedData/SourcePackages` is never created at all. The
phase then dies with `ProcessException: No such file or directory` and
`PhaseScriptExecution failed` — on any fresh checkout, worktree or CI machine. It appears
to work in a long-lived checkout only because a stale _pre-SPM_ DerivedData still happens
to hold the SDK. **`main` still has this latent bug**: clear its DerivedData and it breaks
the same way.

**It runs for Release only.** Symbol upload exists so a crash in a shipped build has
readable traces; a debug build produces no dSYM anyone will symbolicate, so running it on
every `flutter run` spends time and network on nothing and puts a network-dependent script
in the inner loop. **Do not do this with `uploadDebugSymbols: false` in `firebase.json`**
— the obvious knob and the wrong one: `upload_symbols.dart` reads that flag and returns
early on _every_ configuration, so it would quietly stop uploading release symbols too.
The flag means "upload dSYMs at all", not "… for debug builds".

When debugging a failed iOS build, note that `DVTDeveloperAccountManager: Failed to load
credentials … missing Xcode-Token` is **expected noise** (see below) and the real error is
usually a thousand lines further down, past every plugin's deprecation warnings. Filter:

```bash
flutter build ios --simulator --debug --dart-define-from-file=env.json > /tmp/b.log 2>&1
grep -nE "ProcessException|PhaseScriptExecution failed|error: .*\.(dart|swift|m):" /tmp/b.log
```

## Shipping a TestFlight build

```bash
# 1. Bump the build number -- TestFlight rejects one it has already seen.
#    Edit `version:` in pubspec.yaml, e.g. 1.1.0+12 -> 1.1.0+13.
# 2. Archive, sign and upload.
./release_ios.sh
```

### The App Group is a portal click, and the capability is not the same thing

Since the streak widget landed, Runner and StreakWidget both claim
`group.com.unicorn.bookwormFriends`, and signing needs **two separate things** that
are easy to conflate:

1. the `APP_GROUPS` **capability** on each App ID, and
2. the App Group **container** itself, created and then associated with both App IDs.

The App Store Connect API does (1) fine — `POST /v1/bundleIdCapabilities` with
`capabilityType: APP_GROUPS` returns 201, and `scripts/asc_key_probe.py` will show
it on record afterwards. It cannot do (2) at all: there is no app-groups resource,
and `GET /v1/appGroups` is a flat 404. So an App ID can carry the capability while
no group exists to attach, which is the state that produces this, with the capability
already enabled:

```
error: Provisioning profile "iOS Team Provisioning Profile: com.unicorn.bookwormFriends"
       doesn't support the group.com.unicorn.bookwormFriends App Group
error: No profiles for 'com.unicorn.bookwormFriends.StreakWidget' were found
error: Authentication failed: Make sure a bearer token was provided ...
```

**The authentication line is a red herring.** xcodebuild prints it for any rejected
provisioning operation, including one rejected because the group does not exist.
Run `.venv/bin/python scripts/asc_key_probe.py` before believing it — if that reads
`/v1/profiles` the key is fine and the problem is the App ID or the group.

The fix is in the Developer Portal, and only there: create the group under
Identifiers > App Groups, then tick App Groups on both
`com.unicorn.bookwormFriends` and `com.unicorn.bookwormFriends.StreakWidget` and
select it. Cloud managed signing reissues both profiles on the next
`./release_ios.sh` once that exists.

`ios/Runner/Info.plist` takes its version from `$(FLUTTER_BUILD_NAME)` /
`$(FLUTTER_BUILD_NUMBER)`, so **`pubspec.yaml` is the single source of truth**.
The `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` still sitting in
`project.pbxproj` (1.0.6 / 7) are stale leftovers and are not what ships —
don't "fix" them to match.

To find the last shipped build without App Store Connect access, check
`build/ios/archive/Runner.xcarchive/Info.plist` and
`~/Library/Developer/Xcode/Archives/`.

### Export compliance is already answered

`ios/Runner/Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false`, so new
uploads skip the encryption question instead of parking at **Missing Compliance**
(which blocks TestFlight distribution until answered). The declaration holds
because the only cryptography here is HTTPS/TLS through the platform's own
networking — no crypto dependency in `pubspec.yaml`, no cipher code in `lib/`.

That key only affects builds uploaded _after_ it was added; it cannot retroactively
answer for a build already on Apple's servers. For those, or to check state:

```bash
.venv/bin/python scripts/asc_compliance.py --version 1.1.0 --build 13        # report
.venv/bin/python scripts/asc_compliance.py --version 1.1.0 --build 13 --set  # answer
```

It reads `ios/asc.json` like `release_ios.sh` does, and needs `PyJWT` +
`cryptography` in `.venv` (`.venv/bin/python -m pip install PyJWT cryptography`).
Build 13 was answered this way; 14 onward should come up clean on their own.

### Why `release_ios.sh` and not `flutter build ipa`

`flutter build ipa` runs `xcodebuild -exportArchive` with no App Store Connect
credentials. This keychain has **no _Apple Distribution_ signing identity** — the
certificate is present but its private key is gone, so `security find-identity -v`
does not list it — and Xcode's saved account is unusable too (`Failed to load
credentials ... missing Xcode-Token`). The export therefore dies with `No Accounts`
/ `No signing certificate "iOS Distribution" found` _after_ archiving
successfully, which also leaves a stale IPA from the previous build number
sitting in `build/ios/ipa/`.

Passing the ASC API key plus `-allowProvisioningUpdates` to `xcodebuild` fixes
this via **cloud managed signing**: Apple signs with a cloud-held distribution
certificate, so no local private key is required and nothing new lands in the
keychain. Verified on the 1.1.0+12 upload — the archive is signed `Apple
Development`, then the export re-signs with a cloud cert (SHA1 `4717DEE1...`,
not in the keychain) against `iOS Team Store Provisioning Profile`.

So **do not** try to repair the local Apple Distribution certificate, and ignore
the 2-certificate account cap: this path consumes neither. The `missing
Xcode-Token` line during export is expected noise, not a failure.

Signing team is `58P4CVB7L8`; export config is `ios/ExportOptions.plist`
(`app-store-connect`, automatic).

The two `.p12` files on the Desktop are from May 2022 and long expired — not a
recovery route.

## Empty-state illustrations

The six empty-state drawings in `assets/icons/empty/` are **AI-generated, not
hand-authored**. Ten rounds of hand-written SVG were rejected for not matching
the app icon's chalk hand; don't restart down that path. The working pipeline and
every dead end are in `docs/mockups/empty-states/PROMPTS.md` (**Route C**) — read
it before regenerating anything.

Two facts that are expensive to rediscover:

- **Bedrock has no general text-to-image model on this account.** Of 14
  image-output models only `amazon.nova-canvas-v1:0` is text-to-image and it 404s
  as Legacy. The Gemini route is blocked by a billing _dunning_ flag only the
  account owner can clear. Generation goes through **xAI Grok Imagine**
  (`XAI_API_KEY` in the environment, never in `env.json` — that ships in the app
  bundle).
- **Don't seed generation with our own vectors.** Style-transfer caps output
  quality at the seed's geometry; it faithfully reproduced a crown-shaped ribbon.
  Describe the composition in words and pass the icon as a texture reference only.

The shipped assets are **alpha stencils**: chalk coverage is in the alpha channel
and the RGB is flat, so one file per piece is tinted per theme with
`BlendMode.srcIn`. This is why there is no light/dark pair — when there was one,
the two themes drifted into _different drawings_. `test/empty_state_art_test.dart`
guards that; don't "optimise" it into per-theme assets.

Details inside a shape are **knocked out**, never drawn on top: the question mark,
the magnifier lens and the ribbon are all holes through the chalk. A dashed-outline
version of `nomatch` passed every contact sheet and still had to be redrawn,
because at 7% ink coverage it read as a smudge beside its 21–35% siblings. Judge
new art with `flutter test --update-goldens
test/empty_state_art_golden_test.dart` and _look at the two images_ — a proof
sheet is not enough.

## The streak flame is Rive, and the `.riv` is built from committed text

`assets/rive/streak_flame.riv` is **a build artifact**. Its source is
`rive/streak_flame/scene.rml`, and the Rive CLI turns one into the other:

```bash
./rive/streak_flame/build.sh                        # verify, inspect, build, install
../../.venv/bin/python rive/streak_flame/smooth.py   # cubic handles + striations, to paste
../../.venv/bin/python rive/streak_flame/paste.py     # splice those into scene.rml, ids intact
../../.venv/bin/python rive/streak_flame/sheet.py    # render `Ignite` and LOOK at it
../../.venv/bin/python rive/streak_flame/motion.py   # `Idle`, its seam, and a GIF of both
../../.venv/bin/python rive/streak_flame/apex.py     # how far the tip travels vs the belly
../../.venv/bin/python rive/streak_flame/flicker.py  # consecutive frames + per-frame deltas
../../.venv/bin/python rive/streak_flame/aspect.py   # flame vs book across the burst
../../.venv/bin/python rive/streak_flame/sides.py    # how angular the left/right runs read
../../.venv/bin/python rive/streak_flame/burst.py    # regenerate the burst spray, then --write
```

Both are committed — the RML because it is the source, the `.riv` because
`flutter build` cannot run the CLI. Edit the RML, run the script, commit both.

It holds **two ordinary timelines**: `Ignite` (78 frames = 1300ms, one shot, seeked by
Dart) and `Idle` (72 frames, looping, advanced and mixed by Dart). This replaced a
`BlendState1DViewModel` of six single-frame poses scrubbed by a bound Number, and the
reason was not tidiness: **that file had no timeline at all, so nothing played it** — not
the editor, not `rive .`, not any runtime. Every review had to go through a contact sheet
and the animation could not be iterated on before it shipped. The easing now lives in the
timelines and Dart drives `progress` linearly.

**There is also a state machine now, `Play`, and this file said for several rounds that
there was not.** It exists only so a human can press play once and watch `Ignite` run into
`Idle`; without a `defaultStateMachineId` the editor and `rive .` fall back to the
artboard's _first animation_, so the sequence could only be reviewed in halves. It is the
same complaint that produced the timelines, one level up.

**The app still does not run it and must not start.** `_FlamePainter` is a
`BasicArtboardPainter`, which only stores the artboard and calls `artboard.advance`; it
instantiates no machine, so the hand-driven seek-and-mix is unaffected by the machine's
presence. `StateMachinePainter`, in the same rive_native file, _would_ run it — switching to
it would give the artboard two clocks.

And **`_preview.py` strips `defaultStateMachineId` from its copies**, deliberately:
`motion.py`, `apex.py` and `flicker.py` reach `Idle` only by reordering the timelines so it
comes first, which a live machine ignores. With the machine running, a request for "Idle
frame 20" renders frame 20 of the _sequence_ — a wrong picture that looks like a plausible
one. `inspect`'s `problems` list is now empty, so any warning there is a real regression;
it used to carry `no-default-state-machine` permanently, which trained everyone to skim it.

`Ignite` is **strain → burst → settle**, not a rise: the flame is established small,
fails to grow twice (with a ±1.4px `linear` judder on `fire.x` for a haptic to pair
with), then bursts and settles about 2.2× the flame it strained from. Haptics belong
at 633ms, 767ms and 1000ms. A single monotonic rise was legible and inert; the brief
is Duolingo's, and its shape **needs the two failures keyed** because the failing is
the point.

### `Idle` flickers, and the difference from a bounce is rhythm rather than amount

A reader's verdict on the first version was exact: Duolingo's flame _flickers_, ours
_bounced_. Both are words about rhythm. Measured, that loop moved the apex 25px up and down
while swelling the belly 15px wide — **1.67:1**, so the flame was breathing sideways almost as
much as it was rising — and it did it on four evenly-eased beats, which is a 1.7Hz sine, and a
sine is a bounce however tall you make it because the eye can predict the next frame.

Three things fixed it, and the second is the counter-intuitive one:

- **Both `scaleX` and `scaleY` on the shapes came down to about ±1%.** A whole silhouette
  pulsing as a unit _is_ the bounce. Raising `scaleY` is the obvious way to buy vertical
  travel and it lifts the belly with the tip.
- **The tips key `Vertex::y` directly** (animatable, property key 25 — `rive schema
StraightVertex`). This is the only way the top of a flame can move while the body holds
  still, because a transform scales the belly by the same factor as the apex. Both flames get
  one: the reader's note was about the inner flame too, and a core that only scales is a shape
  breathing inside a shape that flickers.
- **The beats are irregular and `linear`** — 18 keys on the apex at 3-to-5 frame gaps, with
  amplitudes that vary beat to beat and straddle zero. Same reasoning as the embers' opacity.

Now: apex travel 30px, belly wobble 2px, **12.5:1**.

Two traps worth keeping:

**The tables live in `smooth.py` in raw silhouette units, not as keyframes in `scene.rml`.**
They go through `scaled()` (and `core()`), so a change to `SCALE_Y` or `CORE_SHRINK` moves the
loop with the shape. A hand-written `-253.4` is correct at 1.8× and a mystery at any other
scale, which is the same trap `IGNITE_FRAMES` and the 304×304 preview ground both fell into.

**Moving a tip invalidates the Catmull-Rom fit of the vertex beneath it**, because a tangent at
`i` is computed from `i-1` and `i+1`. Left alone the tip _sharpened on every cycle_, quietly
undoing the rounded tip a reader had just chosen over the pointed one. `smooth.py` re-fits the
neighbours' handles at every keyframe — note this is not the "don't hand-tune cubic handles"
rule being broken, it is that rule being used: the fitter runs at every keyframe as easily as
once, and the frame-0 values it emits match the authored ones to four decimals, which is the
check that there is no step at the seam.

**`MIN_LICK_SPEED` exists because a slow segment is invisible to every amplitude
measurement.** With linear interpolation a long gap carrying a small amplitude becomes a
_drift_ — 1px a frame for an eighth of a second, in the same place every 1.2s, which is exactly
the regular event a flicker must not have. The span is unchanged, so only
`flicker.py`'s per-frame delta row shows it. The check caught three tables that had
already been eyeballed as irregular.

### Sparks are drawn behind the flame, and that is structural

Both spray groups sit _after_ the shapes they belong with — `burst` after `flame_outer`,
`embers` after `fire` — so draw order (declaration order, front first) occludes any spark still
inside the silhouette. A reader called the old arrangement measles, and the count was the
lesser half of it: `burst` opacity peaked at **0.95 on frame 61 while its scale was still
0.41**, so ten pale discs were at their brightest exactly when they were most bunched and most
overlapping. Behind the flame, overlap stops being something to tune around — what reads is
sparks leaving from behind the edge, which is where sparks come from.

Six dots now, not ten, and the scale runs 0.85→1.35 rather than 0.2→1.14: the old range was a
pop _out of the middle_, right for a spray in front and wrong for one behind.

**The artboard is the binding constraint and no amount of tuning gets around it.** At the
burst the flame is 202 units wide in a 300 frame with its tip 21 from the top — so there is a
~49-unit band each side and **no room above**. Sparks go sideways; no dot's `x` exceeds 84,
past which it leaves the artboard at the burst's peak `fire.scaleX` of 1.28.

### The core is a teardrop, and must not go back to being a small flame

`FLAME_INNER` is a symmetric belly — widest a third of the way up, tapering to a rounded point
— at 39% of the body's width and 46% of its height. **This reverses the oldest note about that
shape**, which said the core had to reuse the body's outline so the two would read as one flame
rather than as a shape with a dagger inside it. The premise was right and the conclusion
inverted: the body's silhouette is a tall tapering leaf with a lean in it, and shrunk to 40%
that _is_ a dagger. Size was never the problem — it was 37% × 43.5% before, against a
reference measuring 39% × 44%.

A version lifted clear of the book's foot was rendered and rejected; the core stays planted.

### The covers are near-black, and a teal version was built and rejected

They are `kCandleWellTop` / `kCandleWellBottom` — tokens authored for the **shareable library
card**, a dark candlelit scene where a near-black well is correct. This artboard sits on cream,
so those make the book the darkest thing in the frame: 14.4:1 against the ground, 9.3:1 against
the flame, where the reference contains no dark at all.

So `AppColors.light.brandFill` #067657 was built and pushed — 2.8:1 against the flame, close to
orange's complement so the fire reads hotter, and it broke the drawing out of being monochrome
amber. **A reader looked at it and preferred the dark covers, so it came back out.** That is a
preference and not a measurement; the figures describe what teal fixed, not whether the result
was better. Recorded so nobody re-derives the analysis and concludes it was never tried.

Two other candidates, ruled out on their own terms: `kCandleCoverLight` #D9A96B is already the
far stop of the page-edge gradient, so the covers would merge into the pages; `brand` #09BC8A
lands at 1.2:1 and is as bright as the fire.

### The flame's size on screen is a fraction, not a dimension

The artboard is **360×300** and the flame is **52% of it wide and 77% tall**. Both numbers
have moved four times and neither is arbitrary. The trap, which cost a whole round trip:

**Growing or shrinking the artboard buys exactly nothing on screen.** `_FlamePainter` is
`Fit.contain` into a square `SizedBox`, so on-screen flame height is
`(flame ÷ artboard) × size` — the artboard's own dimensions cancel. Tripling the
frame to hold a taller flame and tripling the flame are opposite moves, and doing
only the first is arithmetic that never reaches a pixel. What reaches the screen is
the **fraction**.

The other half is `StreakFlame.stageSize`, **252, and no longer `_Ignition.stageSize`**.
Those were the same 152 because `_Ignition.stageSize` is `flameSize * 2` where
`flameSize` is the _point size of the fallback's font glyph_ — so the Rive flame's
size on screen was set by the fallback flame's metrics — then `kReadingStreakIcon`, a
Phosphor glyph — which was never a decision.

**This section said 480×480 and 84% for two rounds, and that is now wrong in both
directions.** The artboard went 304 → 480 to make the flame bigger, then 480 → 300 when a
reader said the fire overhung the book — and the second move is the instructive one, because
it is the same identity read the other way. Shrinking the flame 40% _inside_ a 480 frame
would have shrunk it 40% on screen too, throwing away the reason the box went to 252. The
artboard came down by the same factor, so the flame held its size and what actually changed
was the **book**, which went from 44% of the frame's width to 69%.

Today, with `stageSize` 252:

|                | units     | of the 360×300 frame | on screen  |
| -------------- | --------- | -------------------- | ---------- |
| flame, settled | 186 × 232 | 52% × 77%            | 195px tall |
| flame, burst   | 270 × 256 | 75% × 85%            | 215px tall |
| book           | 208 wide  | 58%                  | 175px wide |

so the settled flame is **0.890** of the book's width. **That reverses the 0.663 this table
carried for two rounds, and the reversal was an instruction rather than drift.** 0.663 came
from "shrink it just around 40%" and it is what the aspect note below used to be defending;
the later instruction was "a wider shape of similar ratio with the phosphor icon", which is a
width decision and overrides a width decision. `SCALE_X` alone moved, so **the flame is no
taller than it was** — 195px against 194px, i.e. nothing. Only its width changed.

**At the burst it is 1.29× the book and the belly overhangs it**, which is the one cost of
the widening and is not yet accepted or rejected. **This said "the foot leaves the paper" for a
round, and that was wrong in a way that changes what a fix could be:** at the burst peak the
flame spans x 21..290 against the book's 45..253, but measured at the book's own top row the
flame is _two pixels_ across — the silhouette tapers to a narrow contact point and carries its
width halfway up. So the flame never stands off the paper; it bulges out over the book's edges
like a canopy, and only at the peak (at 1100ms and 1300ms the whole flame is back inside the
book's width). Moving the foot is not an available fix, because the foot is not the problem.

The arithmetic is worth having because it also rules out the obvious fix: the burst is
`fire.scaleX` 1.28 times `flame_outer`'s own squash 1.14, so an effective 1.46, and holding 270
down to the book's 208 needs an effective 1.13 — _less than the settled flame's 1.0 plus the
squash_. There is no trim that keeps a sideways
burst on the paper at this width. The live options are to accept it (it is three frames, and
fire does flare), to widen the book past 89% of the frame, or to shrink the flame again.
`aspect.py` prints the window and writes the frames; **look at them before choosing.**

Two things that were feared and are not true, so don't re-litigate them: the book does
**not** shrink when the artboard does (artboard-to-screen scale is 252/300 = 0.840, up from
0.525, so every detail gained), and the burst is **not** clipped — its apex clears the top by
21px, measured, and the golden's top row is a point rather than a cut.

What the earlier enlargement cost: **the burst lost height.** The old 1.48 overshoot ran off
the top of any frame worth having, so `fire.scaleY`'s peak is 1.17 and the overshoot moved
sideways into `scaleX`, where there is room. And `StreakFlame` now boxes its **fallback** to
`size` too — returned bare, the celebration's column was 100pt shorter whenever the artboard
failed to resolve, i.e. its layout depended on whether a gitignored dylib was present.
`streak_celebration_test.dart` pins 375×667 as well as 393×852; before this, nothing in the
suite set a surface short enough to fail.

### The artboard is 360×300, and the box is no longer square

**The width was bought for the burst spray and it cost nothing.** The spray is drawn behind the
flame, so a bit reads only once it is clear of the silhouette — and in a 300 square the field
between the settled body (half-width 93) and the frame's edge (150) was 57 units, falling to
**10** at the burst peak. Measured off the Duolingo still the brief came from, its particles reach
about **2.0–2.5×** their flame's half-width; ours reached **1.61×**. At 360 it is **1.94×**.

**On-screen flame height is `(flame ÷ artboard) × box`, so growing both cancels exactly** — 195px
before and after, and `StreakFlame.stageSize` is untouched at 252. What changed is that `stageSize`
is now the box's **height** and the width comes from `StreakFlame.artboardAspect` (360/300), giving
a 302.4 × 252 box. **The box has to carry the artboard's aspect or `Fit.contain` letterboxes**:
`contain` takes `min(W/artboardW, H/artboardH)`, so a square box around a 6:5 artboard would scale
by the width ratio and draw the flame a sixth smaller — spending the new room on shrinking the
drawing instead of on the spray it was bought for.

**Horizontal, because that is the axis with slack.** Doing the same thing by shrinking the drawing
inside a square artboard and raising `stageSize` reaches the same ratio and grows the box in _both_
directions; the 33%-of-frame share that would match the reference's crop needs a **475pt** box,
wider than the phone, and every point of height comes out of the ~40pt the celebration has left on
an iPhone SE. Widening costs none of that: the celebration pads itself 28pt a side, so the width
budget is 319 on a 375pt phone and 302.4 leaves 17. `streak_celebration_test.dart`'s shortest-phone
case asserts the box's size for exactly this reason — a squeeze shows up as a width below 302.4
rather than as an overflow.

**Note the reference's crop includes part of a numeral below its flame**, so it is a card region
rather than a tight box, and "share of the frame" overstates what is wanted. Reach in flame
half-widths is the comparable number. 380 would give 2.04× and leave zero slack on an SE; 446 would
give 2.40× but needs the flame to break out of the 28pt padding.

Content is centred by hand: the artboard's origin is top-left, so widening grows it rightward and
`fire`, `embers`, `book` and `pool` all moved +30, as did `fire.x`'s tremor keys and `book.x`'s
slide. `_preview.py` reads the size off the `<Artboard>` tag, so the review scripts followed.

### The burst spray is generated

`rive/streak_flame/burst.py` owns it — twelve bits, each with its own flight, clock and morph, from
one seeded RNG (`SEED = 3`). Change the seed or the count there and re-run with `--write`; the
script replaces its own output, and a re-run with no edits is a byte-for-byte no-op.

**It replaced six circles on one clock.** Those were children of the group while it carried
`scaleX`/`scaleY` 0.85 → 1.35 and a single shared opacity envelope, so they left on the same radial
line at the same speed, brightened and died on the same frame, were circles within 2 units of one
size, and sat in near-mirrored pairs. A reader compared them to Duolingo's and named both halves of
the problem exactly: "the shapes morph, and initial position and travel paths of each are more
random."

Four things not to undo:

- **Morph is `width`/`height`/`cornerRadiusTL` on each `Rectangle`, not `scaleX`/`scaleY` on its
  `Shape`.** Scaling the node is a zoom — the corner radius scales too, so a rounded square stays
  the same rounded square and only gets bigger. Keying the parametric path is what turns a bar into
  a stub.
- **The group no longer carries `opacity="0"`.** Rive multiplies a parent's opacity into its
  children, so with the reveal moved onto the individual bits an authored-invisible group renders
  an **empty frame** — which looks exactly like a broken keyframe table. Each `Shape` is authored
  at 0 instead, the way `embers` does it.
- **`ID_BASE` is 2000 so the generated ids are four digits.** `OWN_KEYS` matched `objectId="0:2\d+"`
  for one run, which also matches `0:20` — the `fire` node — and that run deleted the flame's
  strain, tremor, gleam, core lick and squash keys. It still built and still verified clean; only a
  diff against a copy taken beforehand caught it.
- **`aspect.py` measures the flame as the connected blob through the centre line**, not every warm
  pixel. The spray uses the flame's own two tokens on purpose, so a plain colour match counted
  twelve confetti bits as silhouette and reported a burst 6 units wider than it is plus a
  non-existent overhang at 1100ms.

**`smooth.py` owns the flame's size, not `scene.rml`.** `SCALE_X` / `SCALE_Y` scale the
small point list. They are **2.3869 and 1.8** and no longer equal (both were 3, then both
1.8); see the aspect note below for why they parted, and note `SCALE_X` has to be **re-solved
whenever `FLAME_OUTER` moves** — bowing the sides added width of its own and dropped the aspect
to 0.8142, which nothing in the suite would have caught. `BASE_Y` then lifts the whole path so
its lowest vertex sits 4 units into the paper rather than 24 — the base's bite is a contact
detail with a physical size, and scaled with everything else the foot comes out through the
underside of a 22-unit page block. The flame stands **on the paper**, not down in the gutter.
Edit the constants, re-run, paste.

### The aspect is 1:1.23, which is Phosphor's, and the fork that got there is closed

Duolingo's flame measures about **1:1.15** wide-to-tall. Ours was **1:1.74**, and after colour
and motion were dealt with a reader's "theirs is cute and ours is not" was mostly this.

**`SCALE_X` and `SCALE_Y` are no longer equal, and the note that used to defend their being
equal was overstated twice over.** It said the aspect "was never mine to spend", on the
evidence that 3-and-2 once stretched the flame to 1:2.4 and was called weird immediately. That
evidence is real and it does not generalise: what was wrong there was using anisotropic scale
to fix a _width-against-the-book_ problem, and stretching **taller**. Going deliberately wider
toward a measured reference is a different decision, and it is the one that was instructed.

`aspect.py` used to render a three-way fork — current, squat (keep width, lose height), widen
(keep height, gain width) — because those two routes to 1:1.45 are not equivalent and picking
one silently would have thrown away a decision. **The instruction was "a wider shape of
similar ratio with the phosphor icon", so widening won, and it went past what that script
offered:** Phosphor Fill `fire` measures 704 × 864 in its 1024 em, so **0.8148**, and
`SCALE_X` is solved to land `icon.py`'s fitted curve on that to four places. 1.8 → **2.3869**.

| flame     | aspect | flame/book | top gap |
| --------- | ------ | ---------- | ------- |
| 186 × 232 | 1:1.23 | 0.890      | 42      |

**And the widening needed a shape change after it, which is the part worth expecting next
time.** A reader's verdict on the wide flame was "looks too fat .. maybe bc the left and right
sides are too angled?" — and the diagnosis in that sentence is right where the obvious reading
(a fat shape needs narrowing) would have undone the widening just asked for. **Anisotropic
scale does not preserve a tangent's angle**: it flattens every slope toward the horizontal, so a
silhouette tuned at 1.8/1.8 has straight-looking sides at 2.39/1.8. Measured as the outline's
deviation from the apex-to-widest chord, the side bulge was **5.5%** — a plank with a kink at
the widest point, where the curve passed going straight down. `FLAME_OUTER`'s two upper side
points moved out and up, which put it at **8.7%**, and max width did not change (0.815 →
0.814). Five candidates were rendered and a reader picked the mildest; the record of the others
is in `smooth.py` and the sheet is `rive/streak_flame/sides.py`, including that bowing harder
pushes max width up and starts swallowing the notch, and that **lifting the widest pair is the
lever for "fat" specifically** if it comes back.

So what widening cost is exactly what the old table said it would: the 0.663. What it did not
cost is height — `SCALE_Y` never moved, so the on-screen flame is the same 195px tall it was.
The live question the widening opened is the **burst overhanging the book**, which is in the
size note above. Two things the widening also moved that a reader would never connect to a
scale constant, both now fixed in `scene.rml` and both worth expecting next time:

- **`gleam` is a 40-unit band, so widening the body narrowed the sweep's share of it** from 29%
  to 22% and it stopped reading as a highlight. On a broad flame a thin band is a crease, and
  the settle frame showed a hard diagonal line down the left shoulder. Scaled by the same
  1.3249 to ±26.5. Note `fire.scaleX` needs no accounting for — the band is a child of `fire`,
  so the burst scales both — it is only a **path** change that moves the ratio.
- **The burst sparks are placed just outside the burst-time silhouette**, which is now 135
  half-units rather than 101, so the low pair at x ±84 falls inside it at the peak. Left as
  is: the peak lasts two or three frames, all six read at 1000ms and 1100ms, and clearing 134
  would put them within 5 units of the artboard edge. Checked by looking, not assumed.

**There is a `rive` CLI, at `/opt/homebrew/bin/rive`.** A previous session asserted
there was not — that `.riv` is editor-only with no CLI and no public serializer —
and wrote a whole document addressed to a human with the Rive Editor on that
basis. `rive docs` and `rive schema <Type>` are the references; RML postdates
training data, so look types up rather than guessing them.

**`rive . --verify` and `rive inspect . --summary` will bless a scene that draws
nonsense.** They are not supersets of each other (`--verify` does scripts and
shaders; only `inspect` reports a `problems` list) and _neither looks at a pixel_.
This scene passed both with zero problems on its first attempt and drew the pages
behind the covers, an egg instead of a flame, and a black peg under it. `sheet.py`
is the third check and the one that finds real defects. Also: **`--advance=1` is
mandatory** on a screenshot — `--advance=0` renders the _authored_ pose, which here
is a finished flame over an open book and looks convincingly like a broken file.

**And `sheet.py` is not enough either — run `motion.py` after any keyframe change.**
There is **no `--animation` flag**, and the previewer plays only the artboard's
_first_ animation, so `sheet.py` cannot see `Idle` at all: the loop was committed
once with every ember hidden behind the flame it came off, and nothing caught it.
`motion.py` builds a reordered copy, and it is also the only check that shows the
loop **seam** — frame 0 and frame 72 must be the same picture, or the flame jumps
once a second for as long as the screen is up. (`between.py` is gone: it existed
because a blend state interpolates each property independently, so the keyed poses
and the blends between them were two different things to check. Sampling a timeline
by time _is_ sampling the in-betweens.)

**The preview scripts hold copies of the scene's numbers, and both have gone stale
once.** `motion.py`'s `IGNITE_FRAMES` sat at 46 for two revisions after `Ignite` grew
to 54, so the GIF silently stopped short of the part being iterated on; `_preview.py`
hardcoded a 304×304 cream ground, and the first render after the artboard grew to 480
came back with a black L down two sides of every cell — which looks exactly like a
scene bug and is not one. The ground now reads `width`/`height` off the `<Artboard>`
tag. `IGNITE_FRAMES` still cannot be derived, so change it in the same commit as the
RML's `duration`.

**Nothing translucent may cross-fade over something dark, in either direction** —
five instances so far, most recently a dark cover fading over the cream ground (a
grey plank) and a cream filler fading over that same cover (grey again). Where a
light thing and a dark thing have to swap, switch both on one `hold` keyframe under
the fastest part of the motion — or, better, **remove the thing that needs the
cross-fade**, which is what the spine hinge did: the book animates on four
continuous transforms and not one opacity.

**The book opens on a hinge, and the spine is it.** Opening used to be `scaleX`
0.52 → 1 plus `scaleY` 1.9 → 1 on one node, which contains no spine anywhere: the
shut pose came out as two parallel dark bars and read as an equals sign. From this
camera the spine is a _point_, so opening is `leaf` — the front cover and the half
of the page block above the midline — rotating **−177° about it**. Sign it positive
and the cover sweeps down through the table on its way round.

**Page-edge hairlines run across the block, parallel to the cover.** They were
vertical for several passes, which corresponds to nothing physical: pages are sheets
stacked through the thickness, so their edges are horizontal bands. They were called
"a comb" and "a ruler's graduations" three times before anyone named the cause.

**The authored pose is the _resting_ pose, not the starting one.** `Idle` keys only
the flame, so everything the opening moves falls back to its authored value — and
authored shut, playing `Idle` alone shows a flame on a _closed_ book. Invisible in
the app, obvious the moment a human scrubs the loop in the editor. `motion.py` had
been hiding it by patching the authored values in a copy before rendering; that
mechanism is gone.

**Don't hand-tune cubic handles — `smooth.py` fits them.** A `CubicMirroredVertex`
spends one angle and one length on both of its segments, so a tangent that suits one
neighbour kinks the other; three attempts by eye all came out faceted.
`CubicDetachedVertex` plus a Catmull-Rom fit makes them a calculation.

**`_flame` in `streak_celebration.dart` is its own drive — don't collapse it back
into `_ignite`.** `_ignite`'s `easeOutBack` crossed 0 → 1 in 185ms and then overshot
past the last frame, so **62% of the window was one held frame** and the whole
choreography played in three. A case in `streak_celebration_test.dart` fails if the
overshoot returns.

### The flame keeps moving after the sequence lands, on purpose

This file and three others used to say the opposite — **nothing moves after the last
cell lands, and there is no idle loop.** That was overruled deliberately: a flame
that freezes the instant it arrives reads as a decal. The cost is that
**`pumpAndSettle` never returns anywhere the Rive path is live**, which is not
hypothetical — it took out four cases in `reading_streak_page_test.dart` that have
nothing to do with the flame.

So any test that pumps the celebration and then settles must call
`useStillStreakFlame()` (`test/still_streak_flame.dart`). It also fixes the older
problem of which flame a test inspects; see below.

### `flutter test` needs a library that worktrees do not get

```bash
dart run rive_native:setup --verbose --clean --platform macos
```

`rive_native`'s dylib lands in **`build/`, which is gitignored**, so like
`env.json` it does not travel between worktrees. Without it `File.asset` fails,
`StreakFlame` draws the hand-built fallback, and the suite stays green — the
failure is _printed_, not thrown. So this is not a required setup step; it is the
switch that decides **which flame a test sees**, and now also whether a test that
settles hangs. `useStillStreakFlame()` takes the machine out of it.

### Three things not to "fix" back

- **`kStreakFlameFactory` is `Factory.flutter`, not `Factory.rive`.** The Rive
  Renderer wants a GPU context; a headless test shell has none, so `File.asset`
  trips a native assert (`file.cpp:206`) and the shell dies with **SIGABRT** —
  uncatchable, and it takes every case that pumps the celebration with it.
- **`_FlamePainter.advance` returns `_liveness > 0` and nothing else.** The obvious
  extra term — also return true while `progress` is strictly between 0 and 1, to save
  a ticker stop/start per frame during the ignition — means an artboard _parked_ at
  any mid value asks for frames forever. `streak_flame_golden_test.dart` renders six
  of those side by side and times out on all of them. Returning `false` does not stop
  the drawing being drawn: it gates the ticker, not `paint`, and `scheduleRepaint`
  restarts it when either drive moves.
- **`StreakFlame` forces `liveness` to 0 under reduced motion.** It cannot be gated
  in `streak_celebration.dart` like every other beat, because that gate jumps the
  controller to 1 and for this one beat 1 _is_ the moving state.

The long version, with every defect and every rejected alternative, is
`docs/streak-flame-rive.md`.

### Viewing it in the Rive Editor, and the one command that would destroy the source

`rive.yaml` records `push: projectId 1996083 / fileId 2597430`, so `rive push
rive/streak_flame` updates that same file instead of creating a new one each time.
Open it from the editor's file browser: **aschung's workspace → Personal Files →
`streak_flame`**. `--rev=<path>` writes an openable document to disk instead, and
both need `rive login`.

**It plays in the editor now**, which it did not before the timelines existed. A push
also **writes ids into `scene.rml`** — 413 of them the first time — which is how it
matches objects up to update the same file. That is harmless and does not regenerate
anything (comments and formatting survive), but it means a push shows up as a large
diff. Expect it rather than investigating it.

**Do not push while the file is open in the editor.** Three pushes in one session,
with the tab open throughout, left the editor showing an **empty stage and an empty
Animations panel** — no artwork, no timelines, nothing — while the source on disk was
intact (441 objects, 2 `LinearAnimation`s, `rive inspect` clean) and the last push had
reported `0 created, 56 updated, 0 deleted, 387 unchanged`, which accounts for every
object. The document was fine; the editor was holding a copy that had been rewritten
underneath it. Closing the tab and reopening from the file browser is the fix.

So the order is: **close the tab, push, reopen.** Or skip the live file for review
altogether — `rive rive/streak_flame --once --rev=/tmp/streak_flame.rev` writes a
standalone document that can be opened directly and cannot be out of sync with
anything. Both need `rive login`.

**Never run `rive pull`.** It overwrites the project _from_ the Rive file, which
would replace `scene.rml` with a machine-generated equivalent and take every
comment in it — the whole record of which geometry was tried and why — with it.
The same is true of round-tripping through the editor at all: `rive create
--from-rev` regenerates the RML from the binary. **The editor is a viewer here,
not an authoring surface.** Edits belong in `scene.rml`.

## Applying one migration without dragging the others

**`supabase db push` cannot cherry-pick.** It applies every pending migration in
order, and this checkout usually has several from parallel work. Pushing to ship one
of your own would take someone else's schema change to production as a side effect.
Always check first:

```bash
supabase migration list --linked      # blank Remote column = pending
supabase db push --linked --dry-run   # names exactly what would go
```

To apply **only** yours, use the Supabase MCP server's `apply_migration` (project
`fkynxmfnsgtafrsbzwtu`, "Libstack"), which takes a single statement set.

One gotcha it leaves behind: `apply_migration` stamps
`supabase_migrations.schema_migrations.version` with **the current timestamp**, not
the version in your local filename. That drift makes the CLI treat your file as
still-pending, and a later `db push` then re-runs the DDL and fails on
`already exists`. Fix it in the same session with an `update` against
`schema_migrations` setting `version` to the local file's timestamp, then re-run
`supabase migration list --linked` and confirm the two columns match.

## The streak page and its celebration, as they now stand

Four things shipped on this branch that earlier notes contradict. Every one of them was a
reversal, so the reasoning that lost is kept rather than deleted.

**The celebration's ground is white and its ink is the flame.** `kStreakCelebrationGround`
is `Colors.white` — a constant so the widget, the test and the golden cannot drift apart —
and `_kStreakCelebrationInk` is `kCandleFlame` #F2A93F. That **reverses the documented
#B54708 choice**, which was picked because it measures 5.43:1 on white where the flame
measures **2.00:1**; it was overruled on instruction, so the numbers below describe what
the trade costs rather than whether to make it. Darkening the flame's hue until white on it
clears 3:1 lands on `#BF8632`, an ochre: **saturation runs out before lightness does**, so
there is no compliant version of "the flame's colour". `_WeekCard` lost its `Colors.white`
@45% fill in the same move — a white wash on white is nothing — and carries a
`kCandleStockTop` @12% hairline instead.

**The seal is retired.** `streakCelebrationMilestone` and `streakCelebrationSealed` are
deleted; `streakCelebrationChasing` ("{days} more days to beat your best.") and
`streakCelebrationRecord` ("Your longest run yet.") replace them, and `StreakCelebration`
takes a `required int best` wired from `longestStreakProvider`. The distance is
**`best + 1 - streak`**, because beating a record is not matching it — which is why the
chasing string has **no `=1` case**: the sentence only appears while `best > streak`, so the
floor is 2 and "1 more day" is unreachable. (That gate used to be described as gating a
_bar_; the bar is gone — see below.) `kStreakMilestones` and `streakMilestoneTarget` still
exist and **nothing in `lib/`
reads them**; they are kept because making the spans real would start there. The noun had
to go because there was no seal: no award, unlock or earn path anywhere in `lib/`, and
`_Seal` in `shareable_library_card.dart` is the app's **logo emboss**, on every Library Card
regardless of any streak. `docs/mockups/card-seal/` had already costed that corner.

**The week row is a label above a token, not a letter in a box** — option E in
`docs/mockups/streak-week/index.html`. `ReadWeekPalette` went **nine roles to six**
(`stampFill`, `stampMark`, `emptyFill`, `todayEdge`, `label`, `labelToday`) because the
token now says what happened and the label only says which day it is. Four things not to
"fix" back:

- **The token is a rounded square, not a circle.** A raked disc is a no-op, and the rake is
  the gesture the week shares with `read_calendar_month.dart`. That is the whole reason E
  was chosen over the four circular candidates.
- **The weekday labels are one character.** Duolingo sets two and the drawing shows two;
  `narrowWeekdays` under `en` collides (two S's, two T's) and we keep it anyway, because the
  window is a _rolling_ seven days ending on today so the order says which day each cell is,
  because `ReadCalendarMonth`'s header on the same page uses the same alphabet, and because
  the collision is `en`-only — Korean narrow weekdays are already unambiguous, so a blanket
  `substring(0, 2)` would be wrong. `DateFormat.E` would also need
  `AppLocalizations.localizationsDelegates` in every harness that pumps the row or it throws
  `UninitializedLocaleData`.
- **`freshLast` lifts rather than inverts.** Two tests used to assert the inversion. It was
  a real escalation when neighbours were a 10% wash; every read day is now already solid and
  already carries a reversed-out check, so there is nothing left to invert _to_. The shadow
  plus `decorateLast`'s overshoot and tilt is what marks the closing cell.
- **`stampMark` is `Colors.white`, never `colors.surface`.** `surface` is #1E1E1E in dark,
  so the old `freshInk` put the reversed-out mark on `brandFill` at about 1.4:1 and a
  stamped day was a blank green token. `brandFill` is the token for _fills that carry white
  text_ and is dark in **both** themes for exactly that reason.

**The span ladder is one track, and it lives only in the celebration.** `StreakSpanTrack`
(`lib/ui/widgets/streak/streak_span_track.dart`). **It shipped on the streak page first,
between the week row and the month card, and was moved on instruction — don't put it back
to fill that gap.** The gap is deliberate (the page's own comment says so) and the move
reconciles the two options the record had left fighting: **F** wanted a ladder, **G** wanted
no standing reminder of what the reader has not done and the whole reward in the
celebration. F's object shown only at G's moment is both — a reader meets the ladder on the
night they just added to it, never as a permanent list of four things they have not managed.
It also puts the track on the ground it was drawn for, since it paints in `kCandleStockTop`
and `kCandleFlame` and was the only candlelit object on a `pageBackground` page.

**It replaced `_MilestoneBar`, which is deleted.** That bar filled `streak / (best + 1)` and
vanished on a record night. Two amber rails 10pt apart is one duplication; the worse one is
that the sentence under it — "8 more days to beat your best." — _was_ the bar, in words. The
ladder says what the sentence cannot, and is present every night. **Its fill does not
animate.** The `_Rise` is the reveal.

**The fill reads `streak`, the run in progress, not `best`, the record — and it read `best`
for one round, which was a defect rather than a design.** The reasoning at the time was that
the record never falls, so it was the more honest number to put on a rail. That is backwards:
right after a lapse, when `streak` has just reset to 1, a rail filled from `best` sits most of
the way to a rung the _new_ run has no claim on, with nothing on screen saying the fill is the
old run rather than this one. The record still has a home — `streakCelebrationChasing` /
`streakCelebrationRecord` name it in words, from `best`, directly under the track.

Segments are **even, not proportional**: to scale, 7/30/100 all land inside the leftmost 27%
and two thirds of the rail stays empty until someone has read every day for a year. Earned
is **derived** from `longestReadingRun`, so there is no new field and no way to desync. The
marks are **white 2×7 hairlines**, and getting there took three cuts: 19px circles read as a
_slider_ (a filled bar with a round handle promises dragging), squaring them off made earned
rungs vanish as amber-on-amber bulges, and a white halo turned the bulge into a bead. It
replaced four ring badges, which are still drawn under `span-row`.

**The celebration is now within about 40pt of overflowing an iPhone SE**, at roughly 624pt
of fixed-height content in a column between two `Spacer`s with no scroll view. Measure
anything added to it at 375×667 first — `streak_celebration_test.dart`'s "shortest phone"
case is the one that fails. And note that **`flutter_test`'s default 800×600 surface is
shorter than any phone the app supports**, so both `streak_celebration_test.dart` and
`reading_streak_page_test.dart` now set a real size in their `_pump`. Without that, moving
the ladder in failed 31 cases with a `RenderFlex` overflow naming a widget none of them
mentioned.

### Two defects a green suite could not see, so render and look

Both were found by putting the built screens on screen — `flutter test
test/read_week_row_render_preview.dart` writes to `build/week_preview/` for exactly this.

**The celebration's progress bar had no track.** The bar itself is gone now, but the trap
is general and the widget is still in the toolbox. Its `SizedBox` had a height and no width;
the parent `Column` centres its children, so the width arrived loose, a `ColoredBox` sized
itself to its child, and that child was a `FractionallySizedBox` — a fraction _of the space
it is given_. The stack collapsed onto the fill, so the track was exactly as long as the
filled part and the bar drew as a short amber dash floating mid-screen. Note that measuring
the `FractionallySizedBox` cannot catch this: it is an _overflow_ box and sizes itself to the
constraints it was handed, so a case written against it passes on the bug. Measure the inner
`ColoredBox`. `StreakSpanTrack` is immune (a `LayoutBuilder` over the width it is handed).

**`StreakSpanTrack`'s last label was half off the page.** The end rung sits _at_ the rail's
right edge by construction, so a 60pt box centred on it drew `1 year` from `width−30` to
`width+30`. A widget test cannot see a clip by the screen; a render can. The end label now
hugs the edge and is right-aligned, and the case that used to bless the overhang says the
opposite.

### The app has one flame now, and it is generated from this project

`StreakFlameMark` (`lib/ui/widgets/streak/streak_flame_mark.dart`) replaced
**`kReadingStreakIcon`**, a Phosphor Fill codepoint, in all four places the app drew a flame:
the library bar's chip, the streak page's hero, the record button, and the celebration's
fallback. The constant is deleted and `phosphor_flutter` is out of `pubspec.yaml` — it was
carried for that one glyph and nothing else.

**The defect was not the font, it was the count.** The celebration's flame is
`assets/rive/streak_flame.riv`; the glyph was a completely different drawing; and the glyph
was what the celebration fell back to when the artboard was missing. So the one code path
guaranteed to stand in for the Rive flame drew something that looked nothing like it. Three
earlier notes argued the _opposite_ — that the flame had to stay a font glyph precisely so the
chip and the celebration could not drift — and all three have been corrected in place. The
premise was right; the arithmetic was backwards.

**So the geometry is generated, not drawn.** `rive/streak_flame/icon.py` imports
`FLAME_OUTER`, `FLAME_INNER`, `CORNERS`, `RADII` and `CORE_RADII` out of `smooth.py`, applies
the same Catmull-Rom fit, reimplements Rive's corner rounding as a fillet, normalises into a
unit box and prints Dart tables, an SVG, or a proof render:

```bash
../../.venv/bin/python rive/streak_flame/icon.py            # the Dart tables, to paste
../../.venv/bin/python rive/streak_flame/icon.py --svg      # the SVG the design record uses
../../.venv/bin/python rive/streak_flame/icon.py --sheet    # render it beside the artboard
flutter test test/streak_flame_mark_render_preview.dart     # and at all four app sizes
```

Four things not to undo:

- **The corner fillet is the one thing reimplemented**, because Rive rounds a
  `StraightVertex`'s `radius` inside the renderer and there is no path data to import. `--sheet`
  puts the generated path beside the artboard's own frame; that side-by-side is the only check
  worth anything, since matching numbers say nothing about whether a curve came out as a flame.
- **`size` boxes the mark square**, holding a 1:1.6 flame centred. That is what made the swap
  invisible at every call site — a narrower box would have re-centred the chip's row and the
  button's label. The aspect is **1:1.607**, not `FLAME_OUTER`'s raw 1:1.674, because the radii
  round the tip in; and it is measured off the _curve_, because the control hull reports 1:1.58
  and fitting to that drew the mark 6% small.
- **The core is derived by lifting HSL lightness, not by lerping to white.** White desaturates,
  which turns a rust `flame` core into tan mud where a brighter orange reads as heat. A `color`
  that is already white gets a core it cannot show, which is correct: the mark on the green
  record button should be one solid shape.
- **`docs/mockups/streaks/index.html` draws the same two paths**, and its `verify.py` imports
  `icon.py` and asserts they are byte-for-byte what the generator emits _today_. That replaced
  a check on Phosphor's codepoint. It is the reason the record cannot quietly drift from the
  app, so don't paste a hand-tweaked path into either.

### The streak reads in one orange, `kCandleFlame` #F2A93F, and `colors.flame` is now unread

Read days on the streak page went green → rust → **amber**, and the second move reverses what
this section said for two rounds. The first was the easy one: `ReadWeekPalette.page`'s
`stampFill` left `brandFill` for the same reason `ReadCalendarMonth`'s today-rule had already
left it — _the run is what this page is about, and the flame above is the run_ — because with
green the page drew three accents at once and the week was the odd one out.

The second is the instruction **"use the same bright orange used in this screen"**, and it
took the last two holdouts with it. Every flame-coloured thing in the streak feature is now
`kCandleFlame`: the celebration's ink, the page's hero mark, the week row's tokens and its
today label, **`ReadCalendarMonth`'s today rule and numeral**, and **`ReadingStreakChip`** —
its mark and numeral. (It was "the capsule's mark, numeral, 12% fill and 55% border" when this
was written; the fill and the border are gone — see the chip note below.) Those last two were
documented here as
deliberately staying on the theme token, on the grounds that the page should be theme-aware
and the chip's 13pt numeral needs contrast. The instruction overrides that, and the argument
it overrides is why: a _rust_ flame in the library bar and an _amber_ flame one tap later is
the same "one object looked like two" defect the hero and the week row were changed to fix,
left running on the screen the reader sees every day. `StreakFlameMark` draws all of them from
one generated silhouette, so two hues meant two flames again.

**What it costs, and it is light mode only.** #F2A93F is 2.00:1 on `surface`, 1.89:1 on
`pageBackground`, 1.80:1 on `sheetBackground` and 1.68:1 on `surfaceVariant`, where #B54708
measured 5.43/5.15/4.90/4.58:1 and cleared AA on all four. Dark mode is not a trade but an
improvement — 8.35:1 on the dark surface against the token's 7.46:1, because `flame` is
already the bright `#FF922B` there. Rendered, what this lands on is the chip's numeral and the
month's today numeral; the week's tokens are fills and the month's rule is a 2.5pt bar.
`build/orange_shot/` has the four surfaces if it needs looking at again.

The white check on those tokens is a separate, already-accepted trade: 5.4:1 on light mode's
rust became **2.00:1** on the amber, the same order as the celebration's and as Duolingo's own
2.18:1. A theme-dependent mark — dark on a bright orange, 7.7:1 — would fix it and is
deliberately not taken; the white check was chosen explicitly.

**So `AppColors.flame` has no reader left in `lib/`, and it is kept rather than deleted.** It
was authored for the chip and for nothing else. `test/color_contrast_test.dart` still holds it
to AA on all four light surfaces, which is now a record of what the compliant orange was
rather than a guard on a shipped one — and the place to start from if anyone asks for the
contrast back. Same reasoning as `kStreakMilestones` above.

### The chip has no pill, in either state, and the pill was load-bearing

`ReadingStreakChip` draws a mark and a numeral on the bar's own ground — Duolingo's
arrangement — and nothing behind them. It used to draw a `circular(20)` stadium filled
`kCandleFlame` at 12% behind a 1.5pt border of the same hue at 55% once today was recorded,
with the identical decoration kept alive in the cold state at transparent colours.

**Two reversals got here and the second undid the first's exception.** The chip originally
drew a grey-outlined pill _every_ day, which made it a fourth chrome control in a row of three
real buttons (the density toggle, the shelves button, the avatar). That objection deleted the
cold outline and kept the warm one, on the reasoning that there was now something to mark. It
applies just as well to the warm one: a status readout is not a control, so it should not be
drawn like one on the good days either.

**What it costs is real, and it is the one thing to know here.** The amber numeral is 2.00:1
on `surface`, so the fill and the border were deliberately carrying a state the ink could not
— the pill's _shape_ said "recorded" at a glance, and the chip's own contrast note said so.
With them gone, hot against cold is two hues: #F2A93F against `secondaryText` #626A72 is
**2.75:1** in light mode and **1.5:1** in dark, where the two are near enough the same
lightness that hue is doing all of the work. Same bet Duolingo makes. `Semantics` carrying the
run in words is therefore no longer a nicety, and the amber is still the first thing to revisit
if anyone asks why the chip is hard to read — but the answer can no longer be "the shape is
doing it".

**The footprint did not move, and the padding looks odd for that reason.** It is
`EdgeInsets.symmetric(horizontal: 16.5, vertical: 14.5)` — the three old insets summed,
8 + 7 + 1.5 and 11 + 2 + 1.5 — so the bar's row lays out to the same pixel and the touch target
is the same 48.5pt tall. Measured before and after: ink 60.25 × 19.5 and footprint 94.5 × 48.5,
both. Two of those terms belonged to the pill, and the border one is the trap: `Container` folds
a border's width into its own effective padding **only when a border is present**, which is
also why the cold decoration used to be kept alive with transparent colours rather than set to
`null` — nulling it took 2 × 1.5pt out of the layout and moved the tap target by three points
depending on whether the reader had read yet. Rounding to 8 and 11 would have re-introduced the
same 3pt shrink on purpose.

`_chipHasNoBox` in `reading_streak_chip_test.dart` looks for **`DecoratedBox`**, not
`Container`: a `Container` carrying only padding is still a `Container`, so a type check would
pass on a chip that had quietly grown a fill back. An earlier draft of that helper also
inspected `Container.decoration` reached through `find.byType(ReadingStreakChip)`, which yields
the chip widget and never a `Container` — a dead clause that passed unconditionally. Verified by
re-adding a decoration and watching five cases fail.

### The Library Card's streak tile is filled, opens the streak page, and its cool fill is a frozen literal

`StatTileVariant` has **four** values now — `hero`, `tile`, `warm`, `cool` — and the streak
tile is the only non-hero tile on that card with a fill of its own. It earns that by being a
**state rather than a stat**: pace and most-read author are true all week, and this one
changes tonight. Warm (`kCandleFlame`) once today is recorded, cool before.

**Keyed on `readToday`, never on the count.** `readToday` is threaded `home_page.dart` →
`LibraryCardSheet` → `LibraryCardBody`, off the same `readTodayProvider` the bar's chip uses,
so the two cannot disagree about whether today counts. The count is intact all day and only
the day's status changes at the 4am rollover, so a tile keyed on the number would be warm at
9am on a day nothing had been read. Both states read the full count, because the record does
not scold.

**Cold is filled, and the alternative was the chip's own rule.** `ReadingStreakChip` recedes
to nothing painted when cold — see the chip note above — and the same move here would make
the streak tile identical to Pace until the day is recorded. Not taken: the chip lives in a
bar the reader passes constantly, where a loud object is a nuisance, whereas the card is
somewhere they go on purpose to look at figures, and a tile that changes _shape_ between
visits is harder to read than one that changes temperature. So the shape is constant and only
the ground moves.

**`kStatTileCool` is `const Color(0xFF626A72)` and must not go back to being
`AppColors.secondaryText`.** It shipped from a candidate that used the token, which is
#626A72 in light and #949599 in dark — so the cold tile was a dark slate block on a white
card and a _pale_ block on a dark one. Measured: 0.301 relative luminance against the hero
green's 0.137, i.e. 3.04:1 against the ground where the hero is 2.97:1, which made "you have
not read yet" the loudest object on the card, and white on it fell from 5.49:1 to **2.99:1**.
Same trap `read_week_row.dart` records for `stampMark`: a token chosen for its role as _text_
promises nothing about its lightness, so using one as a fill is a coin flip per theme.
`AppColors.brandFill` is the shape of the fix — authored to carry white text, and #067657 in
both themes for exactly this reason.

The value is the light theme's `secondaryText`, frozen, which makes it a **neutral twin of
the hero's fill** and the numbers say so almost exactly: white 5.49:1 against the hero's
5.62:1, `statTileHeroMutedText` 4.68:1 against 4.75:1, and 5.49:1/3.04:1 against the light
and dark grounds where the hero is 5.62:1/2.97:1.

**The warm fill does not clear AA, and that is chosen rather than overlooked.** White is
**2.00:1** on `kCandleFlame` and 3.23:1 on the darker stop; at `statTileHeroMutedText`'s 88%,
1.84:1 and 2.85:1. A readable version was built and shown beside it — the same tile on
`AppColors.flame` #B54708, where white is 5.43:1 rising to 7.83:1, within a hair of the
hero's own 5.62:1 — and the amber was preferred. `library_card_contrast_test.dart` asserts
this as an **upper** bound (`lessThan(_aaNormal)`, plus `closeTo(2.0)`), so darkening the
fill into compliance _fails_ rather than leaving a documented exemption describing a tile
that no longer needs one.

**The mark is white with the fill's base as its `coreColor`.** `StreakFlameMark` derives a
core by lifting HSL lightness and white has none left to lift, so a plain white flame is one
solid shape and reads as a droplet. Handing it the ground it sits on puts the fill back
through the middle of the flame.

**Tapping the tile opens the streak page**, the same `AppRoutes.readingStreak` the chip
pushes, on the root navigator. `StatTile.onTap` is null for every other tile and
`library_card_body_test.dart` asserts that asymmetry — pace and most-read author are terminal,
and the card must not become a grid of buttons that mostly go nowhere. `HitTestBehavior.opaque`,
because a stat tile is mostly empty fill and a button that only responds where something is
painted is not one. No `InkWell`: no guaranteed `Material` ancestor here, and a ripple on a
gradient is not a gesture this app makes. The sheet withholds the callback during an edit
(`isEditMode ? null : onStreakTap`), the same rule as the year rail — a tap that pushed a
full-screen page out from under a drag would strand a reader holding covers.

Four treatments were rejected before this one and are worth not re-deriving: an amber
**figure** on the ordinary grey tile (1.68:1 falling to 1.48:1 across the gradient — fainter
than anything the app ships, because the tile's grey gives the amber less to work against
than the bar's white does), a flame **watermark** bleeding off the corner, an amber **mark**
with the figure left in body ink, and a chevron. The last two are still available and
compose with what shipped.

**The final hop in `home_page.dart` is not covered by a test.** Reaching it needs the whole
home fixture plus selecting the Card tab and opening the sheet; the body and sheet tests
cover everything below it.

### Recording a night has two doors, and the celebration is a route rather than an overlay

`showStreakCelebration` (`lib/ui/widgets/streak/streak_celebration_route.dart`) is the only
way the celebration is raised, and both callers use it: `ReadingStreakPage._recordToday` and
`BookDetailsTabView`. It used to be a `Positioned.fill` inside the streak page's own `Stack`,
driven by `_celebrating` and `_celebratedStreak`, which was right while that page was the only
thing that could write a `reading_days` row.

**The band's percent wheel now stamps the night, and it did not before.** That was the gap:
nudging a bookmark is the shortest "I read some of this" in the app and the path most readers
actually use, and it was the only one that left the streak untouched — so the reader most
likely to have a run going was the one whose run grew silently, with no celebration, from a
screen that never mentioned it. The status sheet's tick already wrote the day; it just never
celebrated.

**The long comment above the status sheet's two writes still stands and is not contradicted.**
It says keeping the calls apart is what makes it impossible for a change of status to stamp a
day _by accident_. Nothing about accident has changed: `onProgressSelected` is gated on the
percent sheet's own `_touched`, so confirming a pre-filled position writes neither the column
nor the day. What the wheel asserts is a reading of intent — someone who just told the app
where they are in a book read it today. The cost, stated in place: correcting a percentage the
reader got wrong last week also stamps _today_, and there is no way to tell that apart, because
the wheel records a position and not a date. The narrower rule (stamp only when the position
moved forward) is one comparison away and would refuse the night to someone re-reading a
chapter.

**Celebrate on the transition, never the state.** `readToday` stays true for the rest of the
day, so celebrating on the state would raise the screen on every later nudge.
`_celebrateIfTonightIsNew` takes both halves as arguments rather than reading the second back,
because the callers already know them.

**`BookDetailsTabView.build` watches `readingDaysProvider` for its side effect.** Nothing there
draws the streak. Both write paths ask `readTodayProvider` whether today was already recorded,
and that getter is derived from an _async_ set — so it answers `false` while the fetch is in
flight rather than "not known yet". Unwatched, two things broke: the status sheet opened with "I
read today" unticked on a day that **was** recorded, and saving it called `setRead(read: false)`
and took the night away; and every first nudge looked like the first of the day, so the
celebration fired on a run it had already celebrated. Both survive on device only because the
library bar's chip watches the same provider and the route below stays in the tree, so the set
is nearly always already cached — the failure showed up the moment a test pumped the page with
nothing else alive to have asked.

**Do not "fix" that watch into an `await ref.read(readingDaysProvider.future)` before opening
the sheet.** That was tried. It is airtight about the tick and it puts a network read in front
of the form, so a stalled fetch means the reader cannot edit their dates at all —
`band_doors_test.dart` caught it immediately. A wrong checkbox is the lesser failure than an
unreachable one.

`readingWeekEndingOn` moved out of the streak page into `lib/models/streak.dart`, because three
surfaces now ask for the same rolling window.

### The hero says the run and nothing about today, and the evening warning left with it

`_Hero` draws one label under the figure — `streakDays`, "day streak" — in every phase.
`streakDaysOpen` ("day streak, and today is open") is **deleted from both ARBs**, and the
italic line that sat under it is gone with `kStreakTodayLineKey`: that line was the app's
whole implementation of the reading-streaks design's `sc-risk`, choosing between
`streakTodayOpen` ("A page is enough. Today counts until midnight.") and `streakTodayLate`
from the warning hour.

**Withdrawn on instruction, and the reason it holds is that the page was saying it four
times.** Whether tonight is in is already the flame's tint above the figure, the week row's
last cell below it, and whether the foot of the page offers a record button or a
confirmation. The words were the page explaining its own drawing.

**The two strings are still live and must not be deleted.** `streak_widget_sync.dart` ships
them to the home-screen widget, which has no flame, no week row and no button, so words are
the only channel it has — `docs/superpowers/specs/2026-09-22-streak-widget-design.md` carries
a correction in place saying the page no longer draws them. And if a warning is ever wanted
back on the page, note why it was a line and not a colour: `kCandleFlame` is what _recorded_
means, so an amber warning would be the same hue as the state it warns about.

`readingDayPhaseProvider` is still what the page watches and reads `recorded` off — one clock
for the fact, already invalidated on both boundaries by `main.dart` — it simply no longer
tells `open` from `openLate`. `reading_streak_page_test.dart`'s `the evening warning is not on
this page` group pins that the page reads identically either side of the warning hour.

### The undo footer is debug-only

`streakUndoVisible` in `reading_streak_page.dart` gates the whole "Today is recorded. / Undo"
footer on `kDebugMode`. Un-recording a reading day — deleting a `reading_days` row via
`setRead(read: false)` — is a developer's need while working on the feature;
a reader offered an Undo is being invited to treat their own record as provisional, and the
month grid in front of them already shows what happened.

**The whole footer, not just the `Undo` inside it** — a confirmation banner whose only control
has been removed is a line of text restating the week row and the month card above it. If that
ever needs reversing, drop the button from `_DoneFooter` rather than the footer from the page.
The padding goes with it: an empty band under the month reads as a control that failed to load.

**`debugStreakUndoVisibleOverride` exists because `flutter test` runs in debug.** A bare
`kDebugMode` at the call site would make the shipped behaviour the one state no case can reach.
Same reasoning as `debugStreakFlameAssetOverride`.

### The home-screen widget has a cat, a colour ladder and seven lines

`ios/StreakWidget/` draws a mascot on a ground that deepens and warms toward midnight, with one
line of copy whose voice changes by the hour. Four things here are expensive to rediscover:

- **Three rules in the design record were amended to allow it**, deliberately and in writing:
  _the record does not scold_, _amber and never red_, and _state the deadline rather than the
  threat_. The reasoning that lost is kept in place in
  `docs/superpowers/specs/2026-09-22-streak-widget-design.md` (see **The ladder, as chosen**) and
  in `sc-risk` in the 2026-09-12 spec. **Only the widget is amended; the app's own page is not.**
  What replaced "never red" is measurable and is now a test: _late must not be confusable with
  recorded_, worst pairing 4.71:1.
- **The seven lines are ARB keys (`streakWidgetLine*`) and the Korean is written, not
  translated.** The tile's copy column fits about 7 full-width syllables a line, so Korean gets
  ~14 characters where English gets 30, and the box allows three lines for that reason alone.
- **The font Swift asks for is `Nunito-ExtraBold`, never `Nunito`.** `build_fonts.py`'s subset
  carries the family name _Nunito ExtraBold_, so the obvious name returns nil from `UIFont` and
  the numeral silently becomes SF Rounded. `pubspec.yaml`'s `family: Nunito` is a Flutter-side
  declaration and proves nothing about the file. `streak_widget_palette_test.dart` parses the
  TTF's `name` table and pins it.
- **The cat art's prompts are in the _main checkout_, not this worktree**:
  `docs/mockups/mascot/art/manifest.json` (every prompt ever run, with model, route and cost),
  `scripts/gen_mascot_art.py` (the `WIDGET` dict and `core_edit()`), and
  `docs/mockups/mascot/CHARACTER.md`. There is no `PROMPTS.md` for the mascot — that file belongs
  to the empty-state illustrations, which used a different pipeline. The eight cut-outs ship as
  `ios/StreakWidget/Assets.xcassets`, resampled **by height** because the puddle pose is wider
  than it is tall and a long-edge resize draws it short.

### The widget's review page cannot see the widget, so measure a screenshot

`docs/mockups/streak-widget/final.html` is generated from the shipped sources and is still not
enough: it is a browser drawing the same numbers, so **anything WidgetKit or CoreText does around
the tile is invisible to it.** Two defects shipped through that gap and were only found by
measuring a simulator screenshot against the page:

```bash
xcrun simctl io booted screenshot /tmp/home.png
python3 scripts/measure_widget_shot.py /tmp/home.png --seed 880 300   # any pixel on the tile
```

It walks the tile's edges out from that seed and prints the content inset, the cut-out's box and
whether it reaches the bottom edge. The two it found:

- **The numeral sat 7.5pt low**, because Nunito ExtraBold's natural line box is **1.364 em**
  (ascent 1011, descent −353 on a 1000 em) and SwiftUI lays `Text` out in all of it, where the
  page sets `line-height: 1`. `.frame(height: figureSize)` on the figure is that CSS rule spelled
  in SwiftUI — **don't remove it.** The symptom is not an error but a 9pt dead band across the top
  of the tile with the run row pressed toward the cat, i.e. a tile that reads as a smaller, more
  timid version of the design.
- **`contentMarginsDisabled()` was missing.** iOS 17 adds ~16pt of its own margins around the
  view, on top of `StreakWidgetView`'s `.padding(14)`. It needs **no `#available` guard** and
  cannot have one: it is `@available(iOS 15.0, *)` and `@_alwaysEmitIntoClient` with Apple's own
  body doing the 17 check, and an `if #available` here would give the two branches different
  opaque types.

The same exercise cleared the cat: it measures 70% of the tile, cropped 8%, exactly as drawn. A
report that it was **not** cropped was the run row's drift read one object lower down.

**A third one came off a device for a different reason: the page was only ever shown a flattering
cover.** `cover_color` is sampled from the real jacket, so a white-paper cover comes back near-white
(`#FDFDFB`), and an unbordered rectangle of it on the recorded tile's cream ground is invisible — it
reads as a cover that failed to load. `Jacket` now draws a 1pt `strokeBorder` in **the ground's own
ink at 28%** (a fixed dark hairline would vanish on the 23:00 tile), and `render_final_widget.py`
draws every medium section with both `DARK_COVER` and `PALE_COVER`. The page could always have shown
this; it had just never been handed the input. Same trap as `kStatTileCool` above — a colour sampled
for one role promises nothing about its lightness.

### The widget draws the real cover, and the colour is the fallback that must stay

`cover_color` was never a cover — it is one sampled colour, and for a white-paper jacket it is
near-white. The app now fetches a **120px-wide PNG** and writes it into the App Group's `covers/`
directory; `Jacket` loads it with `UIImage(contentsOfFile:)` and falls back to the colour.

That fallback is why this shipped with **`v` still at 1** and no coordinated release, so don't
"simplify" it away: it is what the tile draws on the first render after a book change, for a reader
who was offline then, and for any cover URL that 404s. Five things not to undo:

- **The snapshot is written first, the cover second.** Reversing it makes a recorded night wait on a
  download. The extra timeline reload is affordable only because `write` is deduplicated per
  snapshot — the refresh budget is spent by per-rebuild reloads, not by per-book-change ones.
- **`StreakCoverThumbnail` re-fetches rather than reusing `cover_sample.dart`'s decode.** The free
  option entangles the widget-sync path with shelf rendering for good. `test/streak_cover_thumbnail_test.dart`
  pins that every failure returns null and none throws — the caller is a `build` method.
- **The filename is `cover-<bookId>.png`, named in Dart and only _resolved_ in Swift** (`coverFileName`
  → `book.coverFile` → `StreakWidgetCovers.url(for:)`). Keyed on the id so the previous book's jacket
  can never appear under the next book's title. `AppDelegate` validates the name against a whitelist
  and prunes to one file, because this is the only place a Postgres value becomes a path.
- **`clear()` deletes the directory.** A hex rectangle leaked that there was a book; a jacket leaks
  _which_ book to anyone glancing at a shared device.
- **The hairline stays over real covers, and the spine drops to 9%.** The book this was built against
  is artwork on a white field — which is _why_ it sampled `#FDFDFB` — so a photographed jacket is as
  invisible on cream as the placeholder was. At the placeholder's 18% the spine reads as a black
  stripe across the artwork.

### The widget draws the library's bookmark, and it is the third copy of that ribbon

`BookmarkRibbon` + `ReadingBookmarkTrack` in `StreakWidget.swift` draw `assets/icons/bookmarkIcon.svg`
over the tile's jacket, slid in from the fore-edge by `progress` — the same track the shelf and the
Library Card use, so one mark reads one position at three sizes. Read `lib/ui/widgets/book/reading_bookmark.dart`
for the reasoning; none of it is repeated in the Swift.

- **Parametric, not generated, and that is the opposite call from the flame.** `StreakFlameGeometry`
  is emitted by `icon.py` because an organic curve has no description shorter than its control
  points. This shape _is_ five numbers — a rectangle, a notch apex, two corner radii — so it is
  written out and **held to the asset by `test/streak_widget_palette_test.dart`**, which parses
  `static let unit*` back out of the Swift and compares with the SVG and with the Dart constants.
- **That test also compares the two placements' _output_, not just their constants.** Flutter
  positions the asset's 22-wide box and Swift draws only the 13.5-wide ribbon, so the insets are
  measured from different edges; an off-by-the-bleed would misplace the mark at every position
  while every constant still matched. The case walks null/0/0.25/0.41/1 and compares left edges.
- **It draws for a book with no recorded position, where `ProgressBar` draws nothing.** A null
  `progress` pins the ribbon at the fore-edge rather than sending it to the gutter — the app's own
  rule, because every book is null until someone answers the wheel. A bar at zero is a claim about
  how far in the reader is; the ribbon at its pin is the absence of one.
- **Outside the clip and above the edge hairline**, because "a bookmark a clip swallows is not a
  bookmark" and a bookmark sits on top of the book rather than under its outline.
- **The shadow is what makes a white ribbon visible on a white cover**, which is the pale-cover
  problem again one object down. SwiftUI's `.shadow` follows the shape's alpha so the notch is
  respected; the app blurs a copy by hand only because `flutter_svg` will not render the SVG's own
  filter.

**The page's percentages and the Swift's resolve against different origins**, which is a drift the
page cannot show either: an absolutely positioned box's `max-width: 43%` is 43% of the whole 338pt
tile, where `geometry.size.width * 0.43` inside the padded content is 43% of 310pt. Both of
medium's caps are pinned in points now so the two sides can be read as agreeing, and
`QUAD_NUMBERS` in `scripts/render_final_widget.py` makes `--check` read every one of medium's
literals back out of the Swift.

**This machine's Xcode ships no `Simulator.app`**, so once a reboot clears the home screen the
widget cannot be re-added — `simctl` can install and screenshot but not place a widget. Expect to
ask for a screenshot rather than to take one.

## Status and reading position are one sheet, and the band has one door

`showBookStatusBottomSheet` is the whole of it on the details page. The percent wheel is no
longer a second door off the band: `BandProgressRow` and `book_details_tab_view.dart`'s
`_onEditProgressPressed` are deleted, and on that page `showSelectPercentBottomSheet` is
reached only from inside the merged sheet. **It still has its own caller on the streak
page**, in `_recordToday`'s pick-a-book-then-how-far flow, so it is not a private helper and
its contract — hand the value out, let the caller write — has to keep holding for both. The
merged sheet's hero is a reading track, the status **word is derived from the position**, and
`Save` is the only writer **of a position** — the two confirmed status transitions write
themselves; see below.

The full record is `docs/superpowers/specs/2026-09-28-status-progress-merge-design.md` plus
the plan's **Build log** beside it. What follows is the part that is expensive to
rediscover.

### The track is the platform's slider, and its own fallback is the wrong one

`ReadingTrack` (`lib/ui/widgets/book/reading_track.dart`) is `CNSlider` from
`cupertino_native_better` behind `useNativeGlass` and **`CupertinoSlider` everywhere
else** — which means it overrides the package's own fallback, deliberately.

**`CNSlider` falls back to a Material `Slider`, and a Material `Slider` is absolute: a tap
on the track seeks to it.** That is `band-scrubber`, the arrangement this design rejected.
Since `useNativeGlass` is **false under `flutter test`** (it reports Android), letting the
package choose would put the rejected behaviour in every test and on every Android device
while the reviewed behaviour existed only on iOS 26.

**The inert tap is the platform's, not a gate of ours.** `CupertinoSlider` and `UISlider`
are _relative_: `_RenderCupertinoSlider` holds one `HorizontalDragGestureRecognizer`, sets
`_currentDragValue = _value` and adds deltas, so a tap is a drag of zero delta and reports
nothing. Two real gates come with that and are worth knowing before debugging a test:
`hitTestSelf` accepts a pointer only within about **22pt of the thumb** (`_kPadding` 8 plus
`CupertinoThumbPainter.radius` 14), and `_handleChanged` reports only when the value
actually differs.

**So a test must drag from the thumb, and inside a sheet it needs two `moveBy`s** — about
24pt first to win the gesture arena against drag-to-dismiss, then the real delta. Dragging
mid-track reaches nothing and **passes vacuously**, which is not hypothetical: it silently
disabled the celebrate-on-the-transition assertion in `book_details_streak_test.dart`.

**The track ticks every 5%, and 1% would be a buzz.** `HapticFeedback.selectionClick()` **and
`SystemSound.play(SystemSoundType.tick)`**, both copied verbatim from
`CupertinoPicker._handleHapticFeedback`, which is what the percent wheel is. The step is not: the picker's `_kItemExtent` is 34, so one of its ticks costs 34pt of
finger travel, while `CupertinoSlider` maps its value over `width - 44` — 283pt of travel on
this sheet's 327 — so a 1% tick costs **2.83pt**. One twelfth of the wheel's, at every speed,
because the ratio is scale-free. **The value is not quantised to match**, so the ticks are
landmarks rather than detents and 73% stays reachable by dragging.

**The sound is half of it, and it shipped once without — the tick is a pair, not a haptic.**
The first round read "similar haptics" as naming a channel and left the sound out, arguing that
iOS's own sliders are silent. The answer was _"i still don't hear the tick tick sound"_: the
wheel was the specification, not the word. **Don't re-derive that argument** — whether a stock
slider clicks is not the question when the request names the control to copy.

**`SystemSoundType.tick` is the wheel's sound and `.click` is the keyboard's.** `.tick` reaches
`AudioServicesPlaySystemSound(1157)`, `kWheelsOfTimeSoundId` in the engine, which the framework
uses for nothing else; `.click` is id 1306, the keypress. The test asserts the argument **by
name** for that reason, since both are "a tick" in prose.

**Silent mode mutes the sound and not the haptic, and the simulator has no haptics at all.** So
_neither_ channel is sufficient alone, and a report of "I can't hear it" has a cause that is not
a defect — check the ringer switch and check it is a device. This is the reason the pair is not
reduced to whichever one seems to be doing the work.

**It ticks on every platform, and `CupertinoPicker` does not — that is deliberate.** The
picker's switch returns for everything but iOS, but the app's own three selection haptics
(`read_filter.dart`, `friends_sheet.dart`, `library_sheet.dart`) are all unconditional. This
follows the app, not the framework. **The sound needs no such decision**: the framework
documents `.tick` as ignored off iOS and the engine matches nothing there, so it is iOS-only for
free. A `Platform.isIOS` around it would be dead code — and the case
`and the sound is asked for unconditionally too, gate-free` fails if anyone adds one, so read
its comment first: the mock sits in front of the engine, so it records the call on the Android
test platform and proves the absence of a Dart gate rather than anything about audibility.

**Copying the picker's iOS gate breaks every test in a way that looks unrelated, so don't.**
`useNativeGlass` reads `defaultTargetPlatform` too, so
`debugDefaultTargetPlatformOverride = TargetPlatform.iOS` flips the glass branch with it: the
case builds a `CNSlider`, cannot drag a platform view, and fails with **"Found 0 widgets with
type CupertinoSlider"**. Two switches that look independent and are not.

**`_slide` in `reading_track_test.dart` reports exactly once however far it travels** — one
`moveBy`, deliberately, so a case can reason about a landing value. Anything about tick
_density_ has to drive many small moves by hand; written against `_slide` it measures one
report and one tick and looks like proof of something it has not tested.

**Do not add a `TapGestureRecognizer` to make the tap inert.** A lone drag recognizer wins
its arena at pointer-down, so "use a drag recognizer only" does not make a tap inert by
itself; the relative arithmetic is what does. A no-op tap recognizer as a second arena
member fixes the tap and not the vertical pan.

And the thumb is **the platform's**, not the app's bookmark ribbon. That was built — so
that what you set here was what you saw on the shelf — and a reader's verdict was "the
bookmark makes an ugly thumb": it is a tall asymmetric notched shape with a shadow, hung
off a 4pt bar.

### There are two glass idioms and `LiquidGlassContainer` is the broken one

**Do not reach for `LiquidGlassContainer` for a surface that sits on an opaque background.**
It renders a bare `glassEffect(.regular)` layer with **no material of its own**, and glass
refracts what is behind it — so over an opaque sheet, which is what a platform view is
composited over, it comes out flat: no rim, no specular edge, no shadow. `read_filter.dart`
and `adaptive_icon_button.dart` both call it _the thing that does not work_ and say why.
`CNGlassEffect.prominent` is not an escape: the plugin's Swift pins `Glass.regular` either
way.

**The idiom that works is a contentless `CNButton` with `CNButtonStyle.glass`, stretched
behind Flutter's own content** — `Stack(fit: StackFit.passthrough)` with a
`Positioned.fill`, so the content sizes the box and no `getIntrinsicSize` round-trip is
needed. A glass `UIButton`'s material comes from its button _configuration_, which carries
the rim and the shadow whatever is behind it. `read_filter._Capsule._glass` and
`AdaptiveContentButton` are the two worked examples.

**This was rediscovered a third time, on the read sheet's filter popover**, which a reader
said "isn't glassy". It had copied `shelf_picker_popover.dart`, and the plan's own Step 4
said to reuse the existing division of labour and _"not introduce a third glass idiom"_ —
correct instruction, wrong exemplar: there were already two, and it pointed at the one that
does not work. **`shelf_picker_popover.dart` still uses `LiquidGlassContainer` and has the
same defect**; it is deliberately left until the popover's fix has been looked at on a
device, so that two twins are not changed on one unverified diagnosis.

Three details that are easy to get wrong and are all load-bearing:

- **`onPressed` must be a non-null no-op, not null.** `CNButton` sends
  `'enabled': (widget.enabled && widget.onPressed != null)`, so a null callback disables the
  platform button and UIKit draws a **dimmed** material — the same flat result, reached from
  the other direction.
- **Wrap it in `IgnorePointer` when it is material rather than a control.** `CNButton` hangs
  a `Listener` off the platform view to push `isHighlighted` on pointer down, and its own tap
  recognizer joins the arena and usually beats the row's. On a menu that means the whole card
  flashes under a finger aimed at one row, and the wrong row can answer. `_Capsule` leaves it
  interactive on purpose, which is the opposite case, not a contradiction.
- **Do not clip it.** A glass button draws its rim and shadow **outside** its own box —
  `_Capsule`'s row reserves 3pt for exactly that — so a `ClipRRect` around the material cuts
  off the two things that make it read as glass. Clip the content instead, which needs it
  anyway so row ink cannot splash past the corner arcs. And set `config.borderRadius`: null
  means a capsule, which on a 216×97 card is a 48pt arc rather than 14.

**None of this is verifiable from here.** `useNativeGlass` needs an Apple target _and_ iOS
26, and `flutter test` reports Android — so every test and every render preview draws the
`BackdropFilter` fallback. The native path can only be judged on an iOS 26 device or
simulator, which is also why the fallback is what `build/read_filter_preview/` shows.

**Measured, and separate from the above: the fallback is nearly invisible on a uniform
background.** Over the read sheet's plain ground the blurred card composites to
`(238, 238, 237)` against a `(240, 240, 240)` background — a 2/255 difference, so the card is
carried entirely by a 0.5pt hairline and its shadow. Where covers sit behind it the blur has
something to work with and it reads properly. This is the same trap `shelf_picker_popover`
records from the other end (*"a blur of something uniform is that thing"*) and it is **not**
fixed: it is a separate judgement about the non-glass path, and retuning the fill is a change
nobody has asked for yet.

### Erasing a position needed a new flag, because `null` was already taken

`updateBookStatus`'s `progress` parameter uses `null` to mean **do not write**, so "the
reader dragged back to the origin, forget where they were" had no spelling at all. There is
now an explicit `clearProgress` flag on both the provider and `BookStatusEdit`. **Do not
collapse it back into a nullable `progress`** — the asymmetry is the point.

A drag to the **origin writes `null`**, which costs 0% as a recordable position; 0% is
still reachable through the wheel's own `0` stop.

`updateBookStatus` also gained **`fromStatus`**, which gates the `reading_shelf_index`
re-head. Without it, saving a position promotes the book to the head of the Reading shelf —
a reader who nudges a bookmark reorders their shelf.

`recordReadingPosition` is the narrow position writer and `recordTotalPages` is new;
`kMinTotalPages` / `kMaxTotalPages` live beside them in `library_provider.dart`.

### Set aside is its own status, not a reading book with a low number

`bookStatusSetAside = 3`. It was specified as `status 2 + progress < 1` first and that is
not the same thing: a finished book's position is exactly 1, so the predicate would have
made every partially-read _Reading_ book abandoned, and there would be no way to record
"I stopped" for a book with no position at all.

`BookStatusBadge.presentation(l10n, colors, status)` is the one place the word and the
colour are chosen, and the sheet's read-out borrows it so the chip and the running text
cannot disagree. Its `switch` had a silent `_` arm that rendered **"Other"** for status 3
before this.

The vocabulary moved with it: _Interested_ → **Not started**, _Read_ → **Finished**.

### The sheet is one height, 335, and that is a fix rather than a tidy-up

`_kContentHeight` is **336**, the tallest state's content — a set-aside book with a dirty Save —
plus `AppSheet`'s own 48, so **384**. Every state renders at that, so the sheet never resizes.

**384 is taller than both sheets this replaced** (342 for the old status sheet, 368 for the
percent wheel), so the merge's headline claim is false now. Two decisions spent the margin: the
frame itself (275 → 335) and moving Save to the foot, which adds a 60pt commit row to the tallest
state and therefore to every state (335 → 384). The test asserts `greaterThan` both figures, so
the size is something someone has to look at rather than a claim that quietly rotted.

**A bottom sheet is anchored to the bottom of the screen**, so growing moves its _top_ edge up
and every child with it. Both date rows sit **below** the track, so dragging off the origin
added ~70pt and slid the control out from under the finger dragging it. The previous answer was
an `AnimatedSize`, and the test that pinned it argued against itself: _"both happen on the same
gesture, so without the animation the sheet would jump twice under the reader's thumb."_ Easing
a defect is not fixing it.

Four things not to undo:

- **`_kTitleRowHeight` is 32, the Save button's height and not the title's ~21.** Without it
  the title `Row` grew 11pt the instant the sheet went dirty and pushed everything below it
  down — the same defect one level in. **An assertion about the sheet's height passes on that
  bug**; the case measures `ReadingTrack`'s _rectangle_ for exactly this reason.
- **`ConstrainedBox(minHeight:)`, never `SizedBox`.** A fixed height trades a moving control
  for a clipped one at large accessibility text sizes. The `AnimatedSize` survives only for
  that residual case.
- **The 214pt void on Not started is the accepted cost, and it is pinned as a number.** That
  state's content is 122, so **over half** of it is empty cream, on the state a reader meets
  first. It was 165 before the commit row moved to the foot — and the jump the frame prevents
  grew from 115 to 165 in the same move, so both sides of the trade got worse at once. Three
  ways out, written up in the spec and none taken: draw the start-date row at the origin (fills
  60, closes a real gap, costs the no-jump property nothing); frame only the drag range, 288,
  and let the two confirmed status transitions resize; or give the frame up.
- **`BottomSheet` dismisses on a drag past half its own height**, so any test that pans to
  dismiss must measure the sheet rather than hard-code a distance. One case broke twice on
  this — once when fonts were loaded, once when the frame went in — and its own comment had
  recorded the first.

### Save and Discard changes are at the foot, and the read-out ends flush right

Save left the title row on instruction. Two things not to undo:

- **The commit row is pinned to the foot by a `Spacer`, and that needs `IntrinsicHeight`.**
  The frame leaves spare room in every state but the tallest, and top-aligned it fell _below_
  the buttons — 49pt of cream under them on a Reading book. `MainAxisSize.max` inside the
  `ConstrainedBox` fills the maximum, which is most of the screen; a `SizedBox` is bounded but
  clips instead of growing. `IntrinsicHeight` tightens the column to `max(natural, 336)`, which
  is bounded, still at least the frame, and still free to grow. **The mockup cannot show this
  defect** — `.dev` has no height, so every crop is drawn at its natural height and there is no
  slack. It was reported from a photograph. And a test that measures `find.text('Save')` reports
  the row 14pt clear of a foot it is flush with: the label's box is shorter than its 44pt
  button.
- **The recessive button says `Discard changes`, and the ARB key is `discardChanges`.** It was
  `reset` / `Reset` for two rounds; renamed on instruction, because `Reset` names a mechanism
  where this names the consequence the reader is weighing against Save. The cost is width — two
  words in a half-width 44pt button, which only fits because the pair is `Expanded` and sized by
  the row rather than by its labels.
- **It restores the sheet's arguments, not a later snapshot.** Those are the same values
  `dirty` compares against, so a discarded sheet is clean by construction and the commit row
  cannot survive its own press. It is **not** `Cancel`: dismissing already discards, so a button
  that dismissed would be a second spelling of a gesture the reader has. This one stays on the
  sheet, which is the point — someone who over-dragged the track wants the old value back and to
  carry on.
- **The page pair is right-aligned by `WrapAlignment.spaceBetween` over _two nested groups_.**
  Over the flat list of four parts it spreads all four and floats the percent into the middle;
  and a `Row` with a `Spacer` — the obvious spelling — throws away the reason
  `ReadingStateLine` is a `Wrap` at all, since a `Row`'s children have no run to drop to and a
  clipped status word is the one failure that makes the line lie about the book.

**Nothing in the read-out is underlined, and `Add total pages` is.** The two page numerals
carried the mark against a bare percent for two rounds, and the spec defended it through a
re-litigation. It went the other way on instruction: the numerals lost it, `Stop reading this`
and `Start reading again` gained it, and the rule to keep is **an underline marks an action, not
a value.** The offer is not an exception — it is the line's only call to action, and the one
place the mark is load-bearing, since an unmarked grey sentence inside a read-out reads as a
caption. Stated cost, accepted knowingly: nothing announces that `213` opens a wheel. Only the
ink is left, which was never an affordance, plus the 44pt track below. `Semantics(button: true)`
is untouched, so VoiceOver is better served than sight here.

**The page pair takes one ink for both spans, decided by the page's door.** Per-span ink was
invisible while the pair was two doors or two dead spans; freezing Set aside made it visible and
wrong, drawing `p.213` grey beside `/ 462` dark — one phrase in two colours, which reads as a
rendering fault. Do not "fix" the total back to its own ink: since the underline left this line,
ink separates a live value from ambient context rather than marking what is tappable.

**The mockup's underline check passed against a page drawing no underline at all**, because it
looked for `<u>213</u>` and the numerals are still wrapped in `<u>` — what changed is the CSS
that gives `<u>` a rule. Both checks read the stylesheet now. A tag is not a treatment.

**The stop-reading confirmation is one sentence.** It was two: it named `Set aside` as the
destination so the chip afterwards would not surprise anyone. Removed on instruction — a
yes-or-no question about the reader's own book should not require them to hold the app's status
taxonomy — and the cost is that the destination is learned after the fact. `place` became
`progress`, matching `readingProgressTitle`. The test asserts the **absence** of the old
sentence, since matching only the new one passes with both.

**A test for the trailing edge needs a wider box than the sheet's 327.**
`reading_state_line_test.dart` loads no fonts, so every glyph is a one-em square, `Reading` sets
to 151pt against about 75 on a phone, and the two groups do not fit — the pair drops to a second
run and the case measures the wrap instead of the alignment. It uses 500. Real widths live in
`book_status_bottom_sheet_test.dart`, which loads the app's faces.

### Stopping a book is confirmed; resuming it is not

`showStopReadingBottomSheet` sits behind `Stop reading this`, and `Start reading again` takes
the same slot once the book is set aside.

**The confirmation is not about the act's weight.** Setting a book aside is reversible in one
tap and every string in the flow is written to keep judgement out of it. It is about what the
control is: a full-width opaque band of grey text with no fill and no border, directly under a
tappable date row, made wide on purpose because a text-sized target for the least important
label on the sheet is hard to land on. The cost of the width is that it is easy to hit by
accident — and an accidental _resume_ costs nothing, which is the whole asymmetry. **Don't add
a confirmation to `Start reading again` for symmetry**; a matched pair of confirmed actions is
the judgement these strings avoid.

**It writes, and for two rounds this said it must not.** The old note: _"it hands an answer
back and does not write ... Committing straight from it is the obvious alternative — a
confirmation that returns you to a form with a Save button looks like being asked twice — and it
would need arguing against the reason the sheet exists, since `Save` being the only writer is the
entire answer to 'a stray touch could silently rewrite your position'."_ The parenthetical
argument is the instruction now.

**Do not re-derive the old invariant from the stray-touch objection**, which is the trap here.
That objection is about _stray_ touches, and a confirmation answers it better than deferral did:
two deliberate taps, the second on a button naming the act. A drag still writes nothing on
release, the value sub-sheets still hand their answers back, and dismissing still discards
everything they hold. Only the two confirmed acts commit.

**Three consequences that look like bugs and are not.** The sheet is **clean** the instant a
confirmation lands — no Save, no `Discard changes` — because `baseStatus`/`baseStart`/`baseFinish`
move with the write; offering to discard a committed change would be offering something this
sheet cannot deliver. Dismissing no longer means nothing happened. And a confirmation sends the
position the sheet **opened** with, not the pending one, so a reader who drags and then confirms
has committed the status and still owes a Save for the drag — `editFor(withPendingAnswers:)` is
that switch, and sending `null` instead would read as a move in `book_details_tab_view.dart`,
stamping a reading day for someone who just stopped reading.

**`book_details_tab_view.dart` tracks `priorStatus` because `onSave` can now fire more than once
per sheet.** Left as the captured `book.status`, a stop-then-resume in one visit passes a
status-identical `fromStatus` on the second write, `updateBookStatus` skips the reposition, and
the book rejoins the Reading shelf carrying the `null` `reading_shelf_index` the first write
cleared.

Tests go through `_stopReading` and `_startReadingAgain`, which each tap and confirm.

**`Start reading again` is confirmed too, and this file argued twice that it must not be.** The
claim was that an accidental resume costs a reader nothing. It cost nothing while nothing was
written before Save; it now writes at once, and the write **clears the day the book was closed**
— so `startReadingAgainConfirmBody` says so, which is the whole difference between an honest
confirmation and ceremony. The resume therefore sets `finish = null` in the form as well,
reversing the note that kept it (_"a reader who resumes and stops again does not lose the day
they first closed the book"_): the column is empty the moment the resume is confirmed, so a form
still holding the date would disagree with the database about a field the reader cannot see. Cost:
stopping again stamps today.

**`Start reading again` reverses a decision recorded in five places** — this file's ancestor,
the spec, the plan, the mockup caption and three comments in the sheet — all saying a set-aside
book resumes by moving the thumb, so a link would be a second affordance. The premise was
wrong: the thumb resumes only by _changing the position_, so a reader who stopped at 46% and
wants to carry on from 46% had no move available. Set aside is the one status a position cannot
imply, which makes it the one that needs a control of its own.

**And now it is the _only_ way out, because the track and the two position doors are dead at Set
aside.** On instruction, and it finishes the argument above rather than adding a second one: a
status a position cannot imply should not be one a position can silently overwrite. It also
closes a hole the link alone left open — the wheel's `0` stop would otherwise resume a book _and_
send it back to Not started in a single confirm. **The total's door stays open**, because a page
count is a fact about the book rather than about the reader's place in it, and shutting it would
draw `Add total pages` as an offer nobody can accept in ~65% of the corpus.

**Keyed on the sheet's _pending_ status, never `currentStatus`.** Otherwise `Start reading again`
leaves the track dead until the reader saves, closes the sheet and comes back — so the link looks
broken — and a just-stopped book's track stays live, which is the silent resume the freeze exists
to prevent. Both directions are pinned in `book_status_bottom_sheet_test.dart`.

**`CupertinoSlider` will not draw itself disabled, and `onChanged: null` alone is a trap.**
`isInteractive` gates its gesture recognizer and its semantics; its `paint` never reads it, so a
disabled slider is pixel-identical to a live one — a control that looks draggable and ignores the
finger, which reads as a broken app. `ReadingTrack` therefore wraps **only that branch** in an
`Opacity` at the platform's 0.4. Do not wrap both: `CNSlider` takes `enabled`, which reaches
`UISlider.isEnabled` natively and also gates its own Material fallback, so wrapping it would dim
the native view twice.

**It does not clear `finish`.** Save filters the finish date out for a reading book, so nothing
wrong is written, and keeping it means a reader who resumes and stops again does not silently
restamp the closing with today. Same rule the sheet applies to `start`.

### Two small traps in the strings and one in the sheet's title

**There is no approximate marker on a page number any more, and `U+2248` is why there could
not be a good one.** `progressApproxPage` printed `~ p.213` for a page the app derived from a
fraction, against `p.213` for one the reader typed. It is **deleted** — key and both
translations — on instruction.

The mark existed because in percent mode the wheel has 101 stops, so at 320 pages one stop is
3.2 pages: a reader aiming at p.148 lands on p.147, and the tilde admitted it. So the cost of
losing it is that the read-out states the arithmetic's page as flatly as the reader's. It was
affordable because the same mark appeared **under the wheel too**, and one mark meaning
"derived" in two places and nothing in the read-out those two feed is read as a rendering
glitch rather than as a distinction — which is why both call sites went, not just the one that
was pointed at.

**The derived-versus-typed distinction survives in the data**, where `progress_page` is null
or set, and that is still what makes a typed page round-trip exactly.
`reading_state_line.dart` used to credit the column's existence to the tilde; it does not.

**If a marker is ever wanted back, it cannot be `≈`.** The faces are subset to Latin-1 plus
Hangul, so `U+2248` drew from a platform fallback in a different typeface — which is why the
one that shipped was an ASCII `~`.

**The sheet's heading is `readingProgressTitle` ("Reading progress"), not the book
title.** A sheet that names the book says nothing about what it does, and the book is
already the page behind it.

**The Korean for the twelve new strings was written rather than natively reviewed** — the
plan's build log lists which.

### The band card has two slots, and it had four values for one round

See `ReadingPeriodRow`'s own doc for the rule and the two reversals it records. The short
version: _where or when_ (the position, else the finish date, else nothing), then _how
long_ (the day count, always), with exactly one of the two in `brandText`. **The start date
is gone from the card** — `15 days` is what it was there to say — and both dates are still
editable in the sheet the card opens.

**`ReadingPeriodRow` has no `pageCount`, and it is not an oversight.** The card read
`71% · p.307 / 432`; the page and the total were withdrawn on instruction, so the position
is a bare percent and the widget cannot draw a page at all. Both numbers are derived from
the percent and the total, so that was the card's widest value restating its first third
more precisely than a glance wants. **Don't add the parameter back to make the band more
informative** — the sheet behind the card draws `ReadingStateLine`, whose page and total are
each a tappable span onto the wheel, so the numerals are one tap away and _editable_ there
rather than merely displayed.

Two knock-on facts that look like bugs and are not: the render preview has **five** states
rather than six, because "Reading with a page count" and "Reading without one" stopped
differing; and `band_doors_test.dart` asserts the page numeral is **absent** from the band,
which is the opposite of what it asserted when `BandProgressRow` was deleted. The card's
cases search bare digit runs (`307`, `432`) rather than `p.307`, so bringing the numbers
back under a different separator still fails.

**A `Wrap` that opens at the default text size on the widest phone is not a valve
opening.** That is how this was caught, and it is the check to apply to the rest of the
band: the `Wrap`s in there are for accessibility sizes and long locales, so one wrapping in
English at 1.0 means the content is too much, not that the layout is working.

### Rendering these screens, and the harness that lied about one

`flutter test test/book_status_sheet_render_preview.dart` writes
`build/status_sheet_preview/*.png` — the merged sheet in all four states, and the Reading
state in both themes and both locales on the shortest phone. **The slider in those frames is
`CupertinoSlider`**, since `useNativeGlass` is false under `flutter test`; the native glass
track can only be judged on an iOS 26 device. Everything else in the sheet is settled there.

`flutter test test/reading_period_row_render_preview.dart` writes
`build/period_row_preview/{light,dark}.png` across six states.

**Neither runs in `flutter test`, and the case count is right anyway.** `*_render_preview.dart`
does not match `*_test.dart`, so the default sweep skips every preview in `test/` — which is
why `AGENTS.md` always names them by path. Adding one does not move the 2055, and a preview
that has rotted is therefore invisible until someone runs it. Its first frame came back
with red text and yellow double underlines everywhere, which reads exactly like a defect in
the card and was a defect in the harness: **no `Material` ancestor**, so every `Text` that
inherits its colour fell back to `MaterialApp`'s `_errorTextStyle`, while the spans setting
a colour explicitly survived — a frame that looks _selectively_ broken. `Material` is where
`AnimatedDefaultTextStyle` comes from; a `ColoredBox` is not a substitute.

The other half is the same as `read_week_row_render_preview.dart`'s: **load the real fonts,
icon font included**, or the chevron is an empty square and every glyph is 40% too wide.

## The suite is green — keep it that way

`flutter test` passes completely (2055 cases). There is no expected-failure list any
more, so **any** red is a real regression.

This section used to say the opposite: `test/library_read_books_test.dart` carried 3
failures that were not regressions, because `ReadPile` moved out of the library page into
`FinishedBooksSheet` (`lib/ui/widgets/finished_books_sheet.dart`, presented from
`home_page.dart`) and those cases pumped a bare home page expecting the pile inline. They
are fixed: each one's _library_ claim (a read book is off the plank; the shelves stay
rather than falling back to the add-a-book prompt) was kept, and the _pile_ assertions were
dropped as duplicates of where the pile now lives — `finished_books_sheet_test.dart` for the
spines, `read_month_grid_test.dart` for the "no books read yet" state.

One case is known to flake under full-suite load: `friend_navigation_test.dart`'s "your own
library is empty" case failed once and has passed every run since, in isolation and in
full. Re-run before investigating.

## Reading `flutter analyze`

`lib/` and `test/` are clean of **both** errors and warnings. The remaining noise is
entirely from vendored SPM checkouts under `build/ios/SourcePackages/`, so filter before
drawing conclusions:

```bash
flutter analyze 2>&1 | grep -E "^\s*(error|warning) •" | grep -vE "•\s*build/"
```

## App identity

The app displays as **Libstack** but bundle IDs and the Dart package name say
`bookworm`, deliberately. Read `docs/APP_IDENTITY.md` before touching any bundle
ID, `applicationId`, URL scheme, or the `pubspec.yaml` package name.
