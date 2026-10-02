#!/usr/bin/env python3
"""Inspect and update the App Store Connect record for a version of Libstack.

Why this exists: the listing for 1.1.0 is assembled from four different API
resources, and the web UI is the only other way to reach them. Keeping it here
means the draft in `docs/store/listing-1.1.0.md` stays the single source of
truth for the copy, and that an edit can be re-applied without re-clicking.

    appStoreVersions              copyright, usesIdfa, release type
    appStoreVersionLocalizations  description, keywords, promotionalText,
                                  whatsNew, supportUrl, marketingUrl
    appInfoLocalizations          name, subtitle, privacyPolicyUrl
    appStoreReviewDetail          reviewer contact, demo account, notes

**Name and subtitle do not live with the description.** They hang off `appInfos`,
not off the version, which is why there are two localization resources here and
why setting them is a separate call.

Usage:
  ./scripts/asc_version.py                            # report only
  ./scripts/asc_version.py --set-idfa false
  ./scripts/asc_version.py --set-review-details
  ./scripts/asc_version.py --publish-copy             # from the markdown draft
  ./scripts/asc_version.py --publish-copy --locale ko
  ./scripts/asc_version.py --attach-build 15          # required before submitting

The report also lists every uploaded build and which one the version points at.

Nothing is written unless one of the --set/--publish flags is passed. Credentials
come from ios/asc.json, the same file release_ios.sh uses.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

BUNDLE_ID = "com.unicorn.bookwormFriends"
API = "https://api.appstoreconnect.apple.com/v1"
VERSION = "1.1.0"

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DRAFT = os.path.join(ROOT, "docs", "store", "listing-1.1.0.md")

# Live and current -- see the status table at the top of the draft. Held here
# rather than in the draft because they are not character-limited fields and the
# same pair applies to every locale.
SUPPORT_URL = "https://libstack.app/support"
PRIVACY_POLICY_URL = "https://libstack.app/privacy"

REVIEWER_CONTACT = {
    "contactFirstName": "Andrew",
    "contactLastName": "Chung",
    "contactEmail": "aschung1005@gmail.com",
    "contactPhone": "+1 628-688-9415",
    # **True now, and this reverses what stood here for the whole of the draft.** It
    # used to be `False` with both credential fields blanked, on the reasoning that the
    # app had no username-and-password sign-in at all -- `auth_page.dart` offered only
    # Apple and Google -- so credentials with nowhere to type them would earn a
    # Guideline 2.1 rejection. That was correct about the app it described.
    #
    # `feat/email-password-auth` merged, so there is an email field, a password field,
    # sign-up and reset, and the notes name the exact labels to tap. Supplying working
    # credentials is the lower-risk path of the two: 2.1 rejections come from
    # credentials that do not work, not from offering them.
    "demoAccountRequired": True,
    # **Re-verify this pair signs in before every submission.** Not paranoia -- the 2022
    # record left a dead `aschung01@snu.ac.kr` in this field, which is exactly the
    # failure it is capable of, and a reviewer who cannot get in does not file a bug,
    # they reject. One call is enough:
    #
    #   curl -s -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
    #     -H "apikey: $PUBLISHABLE_KEY" -H 'Content-Type: application/json' \
    #     -d '{"email":"test@apple.com","password":"..."}'
    #
    # The account is also *seeded* -- 44 books, 3 shelves, a year of reading days,
    # 1 friend -- because an empty library reaches none of the features the screenshots
    # advertise: no shelf to look at, no Library Card, no streak, no friend to visit.
    # `build/demo-account-revert.sql` undoes the seed.
    "demoAccountName": "test@apple.com",
    # The password is **not** here. It comes from `ios/asc.json`, which is gitignored --
    # see `demo_password()`. This file is committed, and a credential a reviewer can use
    # to sign in to production does not belong in a public GitHub repository, however
    # little the account holds.
}


def demo_password() -> str:
    """The App Review demo account's password, out of gitignored `ios/asc.json`.

    Lives beside the ASC key rather than in `env.json` because `env.json` is injected
    into the build and therefore **ships inside the app bundle** -- the same reason
    `AGENTS.md` keeps `XAI_API_KEY` out of it.

    Raises rather than defaulting to an empty string. A PATCH only touches the
    attributes it names, so blanking this one silently would leave whatever is already
    on the record -- and what is already on the record, historically, is a dead 2022
    account. A missing password should stop the publish, not quietly half-apply it.
    """
    with open(os.path.join(ROOT, "ios", "asc.json")) as fh:
        cfg = json.load(fh)
    secret = cfg.get("demoAccountPassword")
    if not secret:
        raise SystemExit(
            'ios/asc.json has no "demoAccountPassword".\n'
            "Add it next to keyId/issuerId/keyPath -- the password for\n"
            f'  {REVIEWER_CONTACT["demoAccountName"]}\n'
            "which App Review signs in with. The file is gitignored."
        )
    return secret

# Draft heading -> (resource, API attribute). The draft is the source of truth for
# every value here; this only says where each one belongs.
VERSION_FIELDS = {
    "Promotional text": "promotionalText",
    "Keywords": "keywords",
    "Description": "description",
    "What's New": "whatsNew",
}
APP_INFO_FIELDS = {
    "Name": "name",
    "Subtitle": "subtitle",
}

HEADING = re.compile(r"^###\s+(?P<field>.+?)\s*\(limit\s+(?P<limit>\d+)[^)]*\)", re.M)
FENCE = re.compile(r"^```\s*$\n(?P<body>.*?)^```\s*$", re.M | re.S)
SECTION = re.compile(r"^##\s+(.+?)\s*$", re.M)
LOCALE = re.compile(r"^[a-z]{2}(?:-[A-Z]{2})?$")


# --------------------------------------------------------------------------- api


def token() -> str:
    """A short-lived ES256 JWT for the App Store Connect API."""
    with open(os.path.join(ROOT, "ios", "asc.json")) as fh:
        cfg = json.load(fh)
    with open(os.path.expanduser(cfg["keyPath"])) as fh:
        private_key = fh.read()
    now = int(time.time())
    return jwt.encode(
        {
            "iss": cfg["issuerId"],
            "iat": now,
            # Apple rejects anything over 20 minutes.
            "exp": now + 600,
            "aud": "appstoreconnect-v1",
        },
        private_key,
        algorithm="ES256",
        headers={"kid": cfg["keyId"], "typ": "JWT"},
    )


def request(method: str, path: str, bearer: str, body=None):
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {bearer}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")
        print(f"error: {method} {url} -> HTTP {err.code}\n{detail}", file=sys.stderr)
        raise SystemExit(1)


def app_id(bearer: str) -> str:
    query = urllib.parse.urlencode(
        {"filter[bundleId]": BUNDLE_ID, "fields[apps]": "name", "limit": 1}
    )
    apps = request("GET", f"/apps?{query}", bearer).get("data", [])
    if not apps:
        raise SystemExit(f"error: no app with bundle id {BUNDLE_ID}")
    return apps[0]["id"]


def version_record(bearer: str, app: str) -> dict:
    query = urllib.parse.urlencode(
        {"filter[versionString]": VERSION, "limit": 1}
    )
    found = request(
        "GET", f"/apps/{app}/appStoreVersions?{query}", bearer
    ).get("data", [])
    if not found:
        raise SystemExit(f"error: no appStoreVersion {VERSION}")
    return found[0]


def editable_app_info(bearer: str, app: str) -> dict:
    """The one appInfo whose state still allows edits.

    A live app has two: the `READY_FOR_SALE` one, whose declarations are immutable
    and answer `409 STATE_ERROR` to any write, and the editable one that appears
    once a draft version exists.
    """
    infos = request("GET", f"/apps/{app}/appInfos", bearer).get("data", [])
    editable = [
        i
        for i in infos
        if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE", None)
    ]
    if not editable:
        raise SystemExit(
            "error: no editable appInfo. Create the draft appStoreVersion first."
        )
    return editable[0]


def localizations(bearer: str, parent_type: str, parent_id: str) -> dict:
    path = {
        "version": f"/appStoreVersions/{parent_id}/appStoreVersionLocalizations",
        "info": f"/appInfos/{parent_id}/appInfoLocalizations",
    }[parent_type]
    data = request("GET", f"{path}?limit=50", bearer).get("data", [])
    return {d["attributes"]["locale"]: d for d in data}


# ------------------------------------------------------------------------- draft


def draft_values() -> dict:
    """Parse the markdown draft into {locale: {field: value}}.

    Deliberately the same shape of parse as `check_listing_limits.py`, so a field
    that validator measures is a field this publishes -- and one it has never
    measured cannot reach Apple.
    """
    with open(DRAFT, encoding="utf-8") as fh:
        text = fh.read()

    sections = [(m.start(), m.group(1).strip()) for m in SECTION.finditer(text)]
    headings = list(HEADING.finditer(text))
    out: dict[str, dict[str, str]] = {}

    for i, h in enumerate(headings):
        end = headings[i + 1].start() if i + 1 < len(headings) else len(text)
        body = FENCE.search(text[h.end() : end])
        if not body:
            continue
        enclosing = next(
            (name for pos, name in reversed(sections) if pos < h.start()), ""
        )
        locale = enclosing if LOCALE.match(enclosing) else "?"
        value = body.group("body").rstrip("\n")
        limit = int(h.group("limit"))
        if len(value) > limit:
            raise SystemExit(
                f"error: {locale} {h.group('field')} is {len(value)}/{limit}. "
                "Run scripts/check_listing_limits.py"
            )
        out.setdefault(locale, {})[h.group("field")] = value
    return out


# ------------------------------------------------------------------------ report


def report(bearer: str, app: str) -> None:
    version = version_record(bearer, app)
    attrs = version["attributes"]
    print(f"app {app}  appStoreVersion {VERSION}  id={version['id']}")
    for key in ("appStoreState", "releaseType", "copyright", "usesIdfa"):
        print(f"  {key:16} {attrs.get(key)!r}")

    info = editable_app_info(bearer, app)
    print(f"\neditable appInfo id={info['id']}")

    ver_locs = localizations(bearer, "version", version["id"])
    info_locs = localizations(bearer, "info", info["id"])
    for locale in sorted(set(ver_locs) | set(info_locs)):
        print(f"\n  {locale}")
        ia = info_locs.get(locale, {}).get("attributes", {})
        print(f"    name             {ia.get('name')!r}")
        print(f"    subtitle         {ia.get('subtitle')!r}")
        print(f"    privacyPolicyUrl {ia.get('privacyPolicyUrl')!r}")
        va = ver_locs.get(locale, {}).get("attributes", {})
        print(f"    supportUrl       {va.get('supportUrl')!r}")
        for field in ("promotionalText", "keywords", "description", "whatsNew"):
            value = va.get(field)
            shown = "None" if value is None else repr(value[:70] + "…" if len(value) > 70 else value)
            print(f"    {field:16} {shown}")

    detail = request(
        "GET", f"/appStoreVersions/{version['id']}/appStoreReviewDetail", bearer
    ).get("data")
    print("\n  appStoreReviewDetail")
    if not detail:
        print("    (none yet)")
    else:
        da = detail["attributes"]
        for key in (
            "contactFirstName",
            "contactLastName",
            "contactEmail",
            "contactPhone",
            "demoAccountName",
            "demoAccountRequired",
        ):
            print(f"    {key:20} {da.get(key)!r}")
        notes = da.get("notes")
        print(f"    {'notes':20} {len(notes) if notes else 0} chars")

    report_builds(bearer, app, version)


def builds(bearer: str, app: str, limit: int = 12) -> list[dict]:
    """Uploaded builds, newest first, across every version train.

    Filtered by app rather than by version: a build belongs to a `preReleaseVersion`
    and is only *related* to an `appStoreVersion` once attached, so asking the version
    for its builds cannot show you the one you are about to attach.
    """
    query = urllib.parse.urlencode(
        {
            "filter[app]": app,
            "sort": "-version",
            "limit": limit,
            "fields[builds]": "version,processingState,uploadedDate,expired,"
            "usesNonExemptEncryption",
        }
    )
    return request("GET", f"/builds?{query}", bearer).get("data", [])


def attached_build(bearer: str, version_id: str) -> dict | None:
    return request("GET", f"/appStoreVersions/{version_id}/build", bearer).get("data")


def report_builds(bearer: str, app: str, version: dict) -> None:
    print("\nbuilds (newest first)")
    for build in builds(bearer, app):
        a = build["attributes"]
        # `usesNonExemptEncryption` False is the export-compliance answer already given,
        # which is what `ITSAppUsesNonExemptEncryption` in Info.plist buys. A build
        # showing None here is parked at Missing Compliance and cannot be distributed --
        # see scripts/asc_compliance.py.
        print(
            f"  +{a['version']:<4} {a['processingState']:<10}"
            f" expired={str(a['expired']):<5}"
            f" encryptionAnswered={a['usesNonExemptEncryption'] is not None}"
            f"  {a['uploadedDate']}"
        )

    current = attached_build(bearer, version["id"])
    shown = f"+{current['attributes']['version']}" if current else "NONE ATTACHED"
    print(f"\n  {VERSION} build: {shown}")


# ------------------------------------------------------------------------- write


def attach_build(bearer: str, app: str, version_id: str, wanted: str) -> None:
    """Point the version at an uploaded build.

    Submission is refused without this, and the web UI's build picker is the only other
    way to reach it. The build must have finished processing -- a `PROCESSING` one is
    accepted by the API and then silently is not there.
    """
    match = next(
        (b for b in builds(bearer, app, limit=200) if b["attributes"]["version"] == wanted),
        None,
    )
    if match is None:
        raise SystemExit(f"error: no build +{wanted} on record -- run without --attach-build to list them")
    state = match["attributes"]["processingState"]
    if state != "VALID":
        raise SystemExit(f"error: build +{wanted} is {state}, not VALID -- wait for processing")

    request(
        "PATCH",
        f"/appStoreVersions/{version_id}",
        bearer,
        {
            "data": {
                "type": "appStoreVersions",
                "id": version_id,
                "relationships": {
                    "build": {"data": {"type": "builds", "id": match["id"]}}
                },
            }
        },
    )
    print(f"attached build +{wanted} to {VERSION}")


def set_idfa(bearer: str, version_id: str, value: bool) -> None:
    request(
        "PATCH",
        f"/appStoreVersions/{version_id}",
        bearer,
        {
            "data": {
                "type": "appStoreVersions",
                "id": version_id,
                "attributes": {"usesIdfa": value},
            }
        },
    )
    print(f"set usesIdfa = {value}")


def set_review_details(bearer: str, version_id: str, notes: str) -> None:
    existing = request(
        "GET", f"/appStoreVersions/{version_id}/appStoreReviewDetail", bearer
    ).get("data")
    attributes = dict(
        REVIEWER_CONTACT, notes=notes, demoAccountPassword=demo_password()
    )
    if existing:
        request(
            "PATCH",
            f"/appStoreReviewDetails/{existing['id']}",
            bearer,
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": existing["id"],
                    "attributes": attributes,
                }
            },
        )
        print(f"updated appStoreReviewDetail ({len(notes)} chars of notes)")
    else:
        request(
            "POST",
            "/appStoreReviewDetails",
            bearer,
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        }
                    },
                }
            },
        )
        print(f"created appStoreReviewDetail ({len(notes)} chars of notes)")


def publish_copy(bearer: str, app: str, version: dict, only: str | None) -> None:
    values = draft_values()
    info = editable_app_info(bearer, app)
    ver_locs = localizations(bearer, "version", version["id"])
    info_locs = localizations(bearer, "info", info["id"])

    for locale, fields in sorted(values.items()):
        if locale == "?" or (only and locale != only):
            continue
        if locale not in ver_locs or locale not in info_locs:
            print(f"  !! {locale}: locale missing on Apple's side; skipped")
            continue

        payload = {
            api: fields[heading]
            for heading, api in VERSION_FIELDS.items()
            if heading in fields
        }
        payload["supportUrl"] = SUPPORT_URL
        request(
            "PATCH",
            f"/appStoreVersionLocalizations/{ver_locs[locale]['id']}",
            bearer,
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": ver_locs[locale]["id"],
                    "attributes": payload,
                }
            },
        )
        print(f"  {locale}: set {', '.join(sorted(payload))}")

        info_payload = {
            api: fields[heading]
            for heading, api in APP_INFO_FIELDS.items()
            if heading in fields
        }
        info_payload["privacyPolicyUrl"] = PRIVACY_POLICY_URL
        request(
            "PATCH",
            f"/appInfoLocalizations/{info_locs[locale]['id']}",
            bearer,
            {
                "data": {
                    "type": "appInfoLocalizations",
                    "id": info_locs[locale]["id"],
                    "attributes": info_payload,
                }
            },
        )
        print(f"  {locale}: set {', '.join(sorted(info_payload))}")


# ------------------------------------------------------------------ screenshots

# Display type -> (frame-file prefix, the exact pixel size Apple accepts there).
#
# **These names are read off the API, not inferred from the marketing size.** There
# is no `APP_IPHONE_69`: Apple folded the 6.9-inch slot into `APP_IPHONE_67`, which
# takes 1320x2868 as well as 1290x2796, and the 13-inch iPad goes to the 12.9-inch
# 3rd-gen type. Guessing earns a 400 *after* the bytes are uploaded. To re-derive the
# list, POST an `appScreenshotSets` with a nonsense `screenshotDisplayType` -- the
# rejection enumerates every valid member and creates nothing.
SCREENSHOT_SETS = {
    "APP_IPHONE_67": ("iphone69-", (1320, 2868)),
    "APP_IPAD_PRO_3GEN_129": ("ipad13-", (2064, 2752)),
}

# The renderer writes one directory per locale under here, named with App Store
# Connect's own locale code -- so the directory name and the locale this script
# iterates are one string. See `test/store_frame_render_preview.dart`.
FRAMES_DIR = os.path.join(ROOT, "build", "store_frames")

# The 2022 sets, which hold eight JPEGs of an app that no longer exists. None of
# these sizes is required any more -- Apple scales 6.9-inch and 13-inch artwork down
# -- and leaving them would ship four screens of a four-year-old UI beside the new
# ones. Deleting is behind its own flag because getting it wrong is not cheap: a
# missing *required* set blocks submission, so upload first, look, then delete.
STALE_SCREENSHOT_TYPES = ("APP_IPHONE_55", "APP_IPHONE_65", "APP_IPAD_PRO_129")


def _png_size(path: str) -> tuple[int, int]:
    """Width and height out of the IHDR, without pulling in Pillow.

    Checked rather than trusted: a frame rendered at the wrong size is accepted by
    the reserve call and rejected on commit, by which point the set holds a
    half-created asset that has to be cleaned up by hand.
    """
    with open(path, "rb") as fh:
        head = fh.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise SystemExit(f"error: {path} is not a PNG")
    return (
        int.from_bytes(head[16:20], "big"),
        int.from_bytes(head[20:24], "big"),
    )


def _upload_part(operation: dict, blob: bytes) -> None:
    """Send one `uploadOperation` to Apple's asset store.

    Deliberately *not* routed through `request`: the URL is pre-signed and the body
    is raw PNG, so adding our Authorization header or a JSON content type makes it
    fail. Only the headers Apple handed back are sent.
    """
    chunk = blob[operation["offset"] : operation["offset"] + operation["length"]]
    req = urllib.request.Request(
        operation["url"], data=chunk, method=operation["method"]
    )
    for header in operation.get("requestHeaders") or []:
        req.add_header(header["name"], header["value"])
    try:
        with urllib.request.urlopen(req) as resp:
            resp.read()
    except urllib.error.HTTPError as err:
        body = err.read().decode(errors="replace")
        print(
            f"error: upload {operation['method']} -> HTTP {err.code}\n{body}",
            file=sys.stderr,
        )
        raise SystemExit(1)


def screenshot_sets(bearer: str, loc_id: str) -> dict:
    data = request(
        "GET",
        f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets?limit=50",
        bearer,
    ).get("data", [])
    return {d["attributes"]["screenshotDisplayType"]: d for d in data}


def _clear_set(bearer: str, set_id: str) -> int:
    """Empty a set, so an upload *replaces* rather than appends.

    The individual screenshots go, not the set: deleting the set and recreating it
    works too and loses nothing, but an empty set that already exists is the state
    the upload wants, and one fewer create is one fewer thing to fail halfway.
    """
    shots = request(
        "GET", f"/appScreenshotSets/{set_id}/appScreenshots?limit=50", bearer
    ).get("data", [])
    for shot in shots:
        request("DELETE", f"/appScreenshots/{shot['id']}", bearer)
    return len(shots)


def _upload_one(bearer: str, set_id: str, path: str) -> str:
    """Reserve, send, commit. Returns the new appScreenshot id."""
    with open(path, "rb") as fh:
        blob = fh.read()
    created = request(
        "POST",
        "/appScreenshots",
        bearer,
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {
                    "fileName": os.path.basename(path),
                    "fileSize": len(blob),
                },
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": set_id}
                    }
                },
            }
        },
    )["data"]
    for operation in created["attributes"].get("uploadOperations") or []:
        _upload_part(operation, blob)
    # `sourceFileChecksum` is an MD5 of the whole file and is how Apple decides the
    # transfer was intact. It is a content hash, not a credential -- hashlib is
    # imported here rather than at module scope because nothing else needs it.
    import hashlib

    request(
        "PATCH",
        f"/appScreenshots/{created['id']}",
        bearer,
        {
            "data": {
                "type": "appScreenshots",
                "id": created["id"],
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                },
            }
        },
    )
    return created["id"]


def upload_screenshots(bearer: str, version_id: str, only: str | None) -> None:
    """Replace every screenshot set from the frames in `build/store_frames/<locale>`.

    **A directory per locale, and that is the fix rather than a tidying.** Every locale
    used to be filled from one flat `build/store_frames`, so `ko` got the English set
    byte for byte -- and the captions are burned into the PNG, so a Korean reader read
    English captions over screens of a Korean app. The cost of the old arrangement was
    recorded here as deliberate, on the grounds that the alternative was rendering and
    reviewing a second set of twelve. That is now what happens: the renderer composites
    per locale, and this reads the locale's own directory.

    Nothing here guesses or falls back. A locale whose directory is missing stops the
    run by name -- quietly uploading the other locale's bytes is exactly the bug being
    fixed, and it leaves no trace in the output.
    """
    if not os.path.isdir(FRAMES_DIR):
        raise SystemExit(
            f"error: {FRAMES_DIR} does not exist.\n"
            "Render the frames first: flutter test test/store_frame_render_preview.dart"
        )
    locs = localizations(bearer, "version", version_id)
    for locale in sorted(locs):
        if only and locale != only:
            continue
        frames = os.path.join(FRAMES_DIR, locale)
        if not os.path.isdir(frames):
            raise SystemExit(
                f"error: {frames} does not exist, so there are no {locale} frames.\n"
                "Render them: flutter test test/store_frame_render_preview.dart\n"
                "If that run fails naming a capture directory instead, the capture "
                f"pass for {locale} has not been run yet."
            )
        existing = screenshot_sets(bearer, locs[locale]["id"])
        print(f"{locale}:")
        for display_type, (prefix, want) in SCREENSHOT_SETS.items():
            # The prefix carries its trailing hyphen, which is also what keeps the
            # renderer's `_sheet-iphone69.png` contact sheets out of the upload. Do not
            # broaden this to `iphone69` -- a sheet is a thumbnail strip, nothing like
            # 1320x2868, so the size check below would reject it, which is the lucky case.
            files = sorted(
                f
                for f in os.listdir(frames)
                if f.startswith(prefix) and f.endswith(".png")
            )
            if not files:
                raise SystemExit(f"error: no {prefix}*.png in {frames}")
            if len(files) > 10:
                raise SystemExit(
                    f"error: {len(files)} {prefix} frames; the App Store takes 10"
                )
            for name in files:
                got = _png_size(os.path.join(frames, name))
                if got != want:
                    raise SystemExit(
                        f"error: {locale}/{name} is {got[0]}x{got[1]}, "
                        f"{display_type} wants {want[0]}x{want[1]}"
                    )
            found = existing.get(display_type)
            if found:
                removed = _clear_set(bearer, found["id"])
                set_id = found["id"]
                print(f"  {display_type}: reusing set, removed {removed} old")
            else:
                set_id = request(
                    "POST",
                    "/appScreenshotSets",
                    bearer,
                    {
                        "data": {
                            "type": "appScreenshotSets",
                            "attributes": {"screenshotDisplayType": display_type},
                            "relationships": {
                                "appStoreVersionLocalization": {
                                    "data": {
                                        "type": "appStoreVersionLocalizations",
                                        "id": locs[locale]["id"],
                                    }
                                }
                            },
                        }
                    },
                )["data"]["id"]
                print(f"  {display_type}: created set")
            ids = []
            for name in files:
                ids.append(_upload_one(bearer, set_id, os.path.join(frames, name)))
                print(f"      {name}")
            # Order is set explicitly rather than left to creation order. The frame
            # filenames carry the slot number precisely so the first three -- the only
            # ones the App Store shows in search results -- cannot silently reshuffle.
            request(
                "PATCH",
                f"/appScreenshotSets/{set_id}/relationships/appScreenshots",
                bearer,
                {"data": [{"type": "appScreenshots", "id": i} for i in ids]},
            )
            print(f"      ordered {len(ids)}")


def delete_stale_screenshots(bearer: str, version_id: str) -> None:
    locs = localizations(bearer, "version", version_id)
    for locale in sorted(locs):
        existing = screenshot_sets(bearer, locs[locale]["id"])
        for display_type in STALE_SCREENSHOT_TYPES:
            found = existing.get(display_type)
            if not found:
                continue
            request("DELETE", f"/appScreenshotSets/{found['id']}", bearer)
            print(f"{locale}: deleted {display_type}")


def report_screenshots(bearer: str, version_id: str) -> None:
    locs = localizations(bearer, "version", version_id)
    print("\nscreenshots")
    for locale in sorted(locs):
        sets = screenshot_sets(bearer, locs[locale]["id"])
        if not sets:
            print(f"  {locale}: NONE -- Apple will not accept the submission")
            continue
        for display_type, record in sorted(sets.items()):
            shots = request(
                "GET",
                f"/appScreenshotSets/{record['id']}/appScreenshots?limit=50",
                bearer,
            ).get("data", [])
            states = {
                (s["attributes"].get("assetDeliveryState") or {}).get("state")
                for s in shots
            }
            flag = "" if states <= {"COMPLETE"} else f"  {sorted(states)}"
            print(f"  {locale:6} {display_type:24} {len(shots):>2} shots{flag}")


def _redact(detail: dict) -> dict:
    """Strip the demo-account password out of a snapshot.

    The 2022 record holds a real 15-character password, and a snapshot is a plain
    file in `docs/`. Its length is kept so the snapshot still records that one was
    set, which is the only thing anyone would come back here to learn -- the
    credential itself is worthless anyway, because every migrated row now has
    `encrypted_password = ''` and the backend it belonged to is gone.
    """
    out = dict(detail)
    secret = out.get("demoAccountPassword")
    if secret:
        out["demoAccountPassword"] = f"<redacted: {len(secret)} chars>"
    return out


def snapshot(bearer: str, app: str, version: dict, path: str) -> None:
    """Write every field this script can overwrite, verbatim, to a JSON file.

    Unlike `report`, nothing here is truncated -- the point is to be able to put a
    value back. Runs before any write in the same invocation.
    """
    info = editable_app_info(bearer, app)
    detail = request(
        "GET", f"/appStoreVersions/{version['id']}/appStoreReviewDetail", bearer
    ).get("data")
    blob = {
        "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "appStoreVersion": {"id": version["id"], **version["attributes"]},
        "appInfo": {"id": info["id"], **info["attributes"]},
        "appStoreVersionLocalizations": {
            locale: rec["attributes"]
            for locale, rec in localizations(bearer, "version", version["id"]).items()
        },
        "appInfoLocalizations": {
            locale: rec["attributes"]
            for locale, rec in localizations(bearer, "info", info["id"]).items()
        },
        "appStoreReviewDetail": _redact(detail["attributes"]) if detail else None,
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(blob, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print(f"snapshot written to {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--set-idfa", choices=("true", "false"))
    parser.add_argument("--set-review-details", action="store_true")
    parser.add_argument("--publish-copy", action="store_true")
    parser.add_argument(
        "--attach-build",
        metavar="N",
        help="point the version at uploaded build N (the number after the + in "
        "pubspec.yaml). Submission is refused until a build is attached.",
    )
    parser.add_argument("--locale", help="restrict --publish-copy / --upload-screenshots to one locale")
    parser.add_argument(
        "--upload-screenshots",
        action="store_true",
        help="replace every screenshot set from the rendered frames in "
        "build/store_frames/<locale>, one directory per App Store locale. Sizes are "
        "verified against the display type before anything is sent, and a locale with "
        "no directory stops the run rather than inheriting another locale's frames.",
    )
    parser.add_argument(
        "--delete-stale-screenshots",
        action="store_true",
        help=f"delete the legacy sets ({', '.join(STALE_SCREENSHOT_TYPES)}), which "
        "hold 2022 artwork. Separate from --upload-screenshots on purpose: upload "
        "and look at the result before removing anything.",
    )
    parser.add_argument(
        "--snapshot",
        metavar="PATH",
        help="dump every field verbatim to a JSON file before writing anything. "
        "Apple keeps no edit history for localizations and the API will not give "
        "an overwritten value back, so this is the only way to keep the old copy.",
    )
    args = parser.parse_args()

    bearer = token()
    app = app_id(bearer)
    version = version_record(bearer, app)

    if args.snapshot:
        snapshot(bearer, app, version, args.snapshot)

    wrote = False
    if args.set_idfa is not None:
        set_idfa(bearer, version["id"], args.set_idfa == "true")
        wrote = True
    if args.set_review_details:
        notes = draft_values().get("?", {}).get("Notes")
        if not notes:
            raise SystemExit("error: no '### Notes (limit N)' block in the draft")
        set_review_details(bearer, version["id"], notes)
        wrote = True
    if args.publish_copy:
        publish_copy(bearer, app, version, args.locale)
        wrote = True
    if args.attach_build:
        attach_build(bearer, app, version["id"], args.attach_build.lstrip("+"))
        wrote = True
    if args.upload_screenshots:
        upload_screenshots(bearer, version["id"], args.locale)
        wrote = True
    if args.delete_stale_screenshots:
        delete_stale_screenshots(bearer, version["id"])
        wrote = True

    if wrote:
        print()
    report(bearer, app)
    report_screenshots(bearer, version["id"])


if __name__ == "__main__":
    main()
