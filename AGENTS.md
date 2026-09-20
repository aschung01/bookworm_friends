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
../../.venv/bin/python rive/streak_flame/sheet.py    # render `Ignite` and LOOK at it
../../.venv/bin/python rive/streak_flame/motion.py   # `Idle`, its seam, and a GIF of both
```

Both are committed — the RML because it is the source, the `.riv` because
`flutter build` cannot run the CLI. Edit the RML, run the script, commit both.

It holds **two ordinary timelines and no state machine**: `Ignite` (54 frames, one
shot, seeked by Dart) and `Idle` (72 frames, looping, advanced and mixed by Dart).
This replaced a `BlendState1DViewModel` of six single-frame poses scrubbed by a
bound Number, and the reason was not tidiness: **that file had no timeline at all,
so nothing played it** — not the editor, not `rive .`, not any runtime. Every review
had to go through a contact sheet and the animation could not be iterated on before
it shipped. The easing now lives in the timelines and Dart drives `progress`
linearly.

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

## The suite is green — keep it that way

`flutter test` passes completely (1769 cases). There is no expected-failure list any
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
