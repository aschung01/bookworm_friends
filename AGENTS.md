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

`flutter test` passes completely (1532 cases). There is no expected-failure list any
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
