#!/usr/bin/env bash
# Archives, signs and uploads the iOS app to TestFlight, headlessly.
#
# Usage: ./release_ios.sh [--no-upload]
#
# Why this exists rather than a bare `flutter build ipa`: `flutter build ipa`
# shells out to `xcodebuild -exportArchive` without any App Store Connect
# credentials, so on a machine whose keychain has no *Apple Distribution*
# identity it archives fine and then fails the export with "No Accounts / No
# signing certificate iOS Distribution found". Passing the ASC API key to
# xcodebuild lets automatic signing fetch (or mint) the distribution certificate
# and the App Store profile itself, which is the only way this works without
# someone clicking through Xcode's Organizer.
#
# Requires, both gitignored:
#   env.json      build-time dart-defines (see README)
#   ios/asc.json  { keyId, issuerId, keyPath } for the ASC API key
set -euo pipefail
cd "$(dirname "$0")"

UPLOAD=1
for arg in "$@"; do
  case "$arg" in
    --no-upload) UPLOAD=0 ;;
    *) echo "usage: ./release_ios.sh [--no-upload]" >&2; exit 1 ;;
  esac
done

if [[ ! -f env.json ]]; then
  echo "error: env.json not found -- see README 'Build-time secrets'." >&2
  exit 1
fi
if [[ ! -f ios/asc.json ]]; then
  echo "error: ios/asc.json not found. Create it with:" >&2
  echo '  { "keyId": "...", "issuerId": "...", "keyPath": "~/private_keys/AuthKey_....p8" }' >&2
  exit 1
fi

KEY_ID=$(python3 -c 'import json;print(json.load(open("ios/asc.json"))["keyId"])')
ISSUER_ID=$(python3 -c 'import json;print(json.load(open("ios/asc.json"))["issuerId"])')
KEY_PATH=$(python3 -c 'import json,os;print(os.path.expanduser(json.load(open("ios/asc.json"))["keyPath"]))')

if [[ ! -f "$KEY_PATH" ]]; then
  echo "error: App Store Connect key not found at $KEY_PATH" >&2
  exit 1
fi

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
echo "==> Releasing $VERSION (bundle com.unicorn.bookwormFriends)"
echo "    Bump 'version:' in pubspec.yaml before re-running: TestFlight rejects"
echo "    a build number it has already seen."

ARCHIVE=build/ios/archive/Runner.xcarchive
IPA_DIR=build/ios/ipa

# A stale IPA from an earlier build number is worse than none: a failed export
# leaves it in place and it looks like the thing you just built.
rm -rf "$IPA_DIR" "$ARCHIVE"

# Writes ios/Flutter/Generated.xcconfig (including DART_DEFINES) without
# building, so the xcodebuild invocations below drive the actual compile through
# Flutter's own Xcode build phase. `--config-only` is a `build ios` flag; there is
# no `build ipa` equivalent.
echo "==> Configuring Flutter build"
flutter build ios --release --config-only --dart-define-from-file=env.json

AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$KEY_ID"
  -authenticationKeyIssuerID "$ISSUER_ID"
)

echo "==> Archiving"
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  "${AUTH[@]}"

echo "==> Exporting signed IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath "$IPA_DIR" \
  "${AUTH[@]}"

IPA=$(find "$IPA_DIR" -maxdepth 1 -name '*.ipa' | head -1)
if [[ -z "$IPA" ]]; then
  echo "error: export produced no .ipa" >&2
  exit 1
fi
echo "==> Built $IPA"

if [[ "$UPLOAD" -eq 0 ]]; then
  echo "==> --no-upload given; stopping before TestFlight."
  exit 0
fi

echo "==> Uploading to TestFlight"
xcrun altool --upload-app \
  -f "$IPA" \
  -t ios \
  --apiKey "$KEY_ID" \
  --apiIssuer "$ISSUER_ID"

echo "==> Done. $VERSION is processing in App Store Connect."
