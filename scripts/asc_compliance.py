#!/usr/bin/env python3
"""Answer the App Store Connect export-compliance question for a build.

Why this exists: an uploaded build sits at "Missing Compliance" until someone
answers the encryption question, and TestFlight will not distribute it until
they do. Adding ITSAppUsesNonExemptEncryption to Info.plist stops the question
being asked for *future* builds, but it cannot retroactively answer it for a
build already on Apple's servers -- that has to go through the API (or a click
in the web UI).

Usage:
  ./scripts/asc_compliance.py --version 1.1.0 --build 13 [--set]

Without --set it only reports. Credentials come from ios/asc.json, the same
file release_ios.sh uses.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

BUNDLE_ID = "com.unicorn.bookwormFriends"
API = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    """A short-lived ES256 JWT for the App Store Connect API."""
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    with open(os.path.join(root, "ios", "asc.json")) as fh:
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


def find_build(bearer: str, version: str, build: str) -> dict:
    query = urllib.parse.urlencode(
        {
            "filter[app]": app_id(bearer),
            "filter[preReleaseVersion.version]": version,
            "filter[version]": build,
            "fields[builds]": "version,uploadedDate,processingState,usesNonExemptEncryption",
            "limit": 1,
        }
    )
    found = request("GET", f"/builds?{query}", bearer).get("data", [])
    if not found:
        raise SystemExit(f"error: no build {version} ({build}) found")
    return found[0]


_app_id_cache = {}


def app_id(bearer: str) -> str:
    if "id" not in _app_id_cache:
        query = urllib.parse.urlencode(
            {"filter[bundleId]": BUNDLE_ID, "fields[apps]": "name", "limit": 1}
        )
        apps = request("GET", f"/apps?{query}", bearer).get("data", [])
        if not apps:
            raise SystemExit(f"error: no app with bundle id {BUNDLE_ID}")
        _app_id_cache["id"] = apps[0]["id"]
    return _app_id_cache["id"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True, help="marketing version, e.g. 1.1.0")
    parser.add_argument("--build", required=True, help="build number, e.g. 13")
    parser.add_argument(
        "--set",
        action="store_true",
        help="declare usesNonExemptEncryption=false (HTTPS/TLS only; exempt)",
    )
    args = parser.parse_args()

    bearer = token()
    found = find_build(bearer, args.version, args.build)
    attrs = found["attributes"]
    print(f"build {args.version} ({attrs['version']})  id={found['id']}")
    print(f"  processingState:          {attrs.get('processingState')}")
    print(f"  usesNonExemptEncryption: {attrs.get('usesNonExemptEncryption')!r}")

    if not args.set:
        print("\n(report only; pass --set to answer the compliance question)")
        return

    if attrs.get("usesNonExemptEncryption") is not None:
        print("\nalready answered; nothing to do")
        return

    request(
        "PATCH",
        f"/builds/{found['id']}",
        bearer,
        {
            "data": {
                "type": "builds",
                "id": found["id"],
                "attributes": {"usesNonExemptEncryption": False},
            }
        },
    )
    after = find_build(bearer, args.version, args.build)["attributes"]
    print(f"\nset. usesNonExemptEncryption is now {after.get('usesNonExemptEncryption')!r}")


if __name__ == "__main__":
    main()
