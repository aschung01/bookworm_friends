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
    # **False on purpose.** The app has no username-and-password sign-in at all --
    # `auth_page.dart` offers only Apple and Google -- so there are no credentials a
    # reviewer could enter. The notes tell them to use their own Apple ID instead.
    # Handing over credentials with nowhere to type them earns a Guideline 2.1
    # rejection.
    "demoAccountRequired": False,
    # Blanked explicitly rather than omitted. A PATCH only touches the attributes it
    # names, and the 2022 record left `aschung01@snu.ac.kr` sitting in this field --
    # so omitting it would leave a reviewer a stale account to fail against even
    # with demoAccountRequired false.
    "demoAccountName": "",
    "demoAccountPassword": "",
}

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


# ------------------------------------------------------------------------- write


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
    attributes = dict(REVIEWER_CONTACT, notes=notes)
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
    parser.add_argument("--locale", help="restrict --publish-copy to one locale")
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

    if wrote:
        print()
    report(bearer, app)


if __name__ == "__main__":
    main()
