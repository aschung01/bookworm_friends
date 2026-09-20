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
../../.venv/bin/python rive/streak_flame/sheet.py   # render the poses and LOOK at them
../../.venv/bin/python rive/streak_flame/between.py # and the blends between them
```

Both are committed — the RML because it is the source, the `.riv` because
`flutter build` cannot run the CLI. Edit the RML, run the script, commit both.

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
mandatory** on a screenshot, or every frame is the authored rest pose and six
identical renders look like a working filmstrip.

**And `sheet.py` is not enough either — run `between.py` after any keyframe change.**
It renders every 4% rather than only the six keyed poses, because a blend state
interpolates each property independently and linearly: two poses that are both
correct can still pass through something that is not. That is how a half-transparent
page over a near-black cover turned the first fifth of the sequence into a grey slab
while both ends looked fine. **Nothing translucent may cross-fade over something
dark** — that bug had two instances and this is the only check that sees either.

### `flutter test` needs a library that worktrees do not get

```bash
dart run rive_native:setup --verbose --clean --platform macos
```

`rive_native`'s dylib lands in **`build/`, which is gitignored**, so like
`env.json` it does not travel between worktrees. Without it `File.asset` fails,
`StreakFlame` draws the hand-built fallback, and the suite stays green — the
failure is _printed_, not thrown. So this is not a required setup step; it is the
switch that decides **which flame a test sees**, which is why
`streak_celebration_test.dart` pins the fallback with
`debugStreakFlameAssetOverride` instead of leaving it to the machine.

### Two things not to "fix" back

- **`kStreakFlameFactory` is `Factory.flutter`, not `Factory.rive`.** The Rive
  Renderer wants a GPU context; a headless test shell has none, so `File.asset`
  trips a native assert (`file.cpp:206`) and the shell dies with **SIGABRT** —
  uncatchable, and it takes every case that pumps the celebration with it.
- **`_PosedState` clears `controller.active`.** A 1D blend state reports itself as
  always advancing, so `advance` returns true forever and the artboard repaints at
  60fps on a screen a reader opens nightly. It shows up as `pumpAndSettle timed
out`. Clearing `active` does not stop it being painted — `active` gates the
  ticker and hit testing, not `paint` — and writing `progress` schedules its own
  frame, so the drawing still poses.

The long version, with every defect and every rejected alternative, is
`docs/streak-flame-rive.md`.

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

`flutter test` passes completely (1766 cases). There is no expected-failure list any
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
