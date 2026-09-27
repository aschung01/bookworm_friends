"""Reports what the App Store Connect API key in `ios/asc.json` can actually do.

Run when a signing step fails with "Authentication failed: Make sure a bearer token
was provided..." — the message xcodebuild prints for *any* rejected key, whether it
is expired, revoked, wrong, or merely lacking the role the operation needs. Xcode
cannot tell those apart for you and neither can the error text.

    .venv/bin/python scripts/asc_key_probe.py

Reads `ios/asc.json` exactly as `release_ios.sh` and `asc_compliance.py` do, mints
the same kind of ES256 bearer token Xcode would, and calls three endpoints in
increasing order of privilege:

  /v1/apps         readable by every role, so a failure here means the key itself is
                   bad rather than under-privileged
  /v1/bundleIds    the App ID list -- needed to see a capability
  /v1/profiles     provisioning profiles -- needed to reissue one, which is what
                   `-allowProvisioningUpdates` is trying to do

A key that reads apps but not profiles is a *role* problem: managing certificates,
identifiers and profiles requires Admin or App Manager, and a Developer-role key can
upload a build while being unable to add a capability to an App ID.

Needs PyJWT and cryptography, which `asc_compliance.py` already documents:
  .venv/bin/python -m pip install PyJWT cryptography
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

ASC = "https://api.appstoreconnect.apple.com"
# Apple rejects anything over 20 minutes for this audience.
TOKEN_LIFETIME_SECONDS = 15 * 60


def load_config(path: str = "ios/asc.json") -> dict[str, str]:
    with open(path) as handle:
        config = json.load(handle)
    config["keyPath"] = os.path.expanduser(config["keyPath"])
    return config


def bearer(config: dict[str, str]) -> str:
    """The same ES256 assertion xcodebuild builds from the same three fields."""
    with open(config["keyPath"]) as handle:
        private_key = handle.read()

    now = int(time.time())
    return jwt.encode(
        {
            "iss": config["issuerId"],
            "iat": now,
            "exp": now + TOKEN_LIFETIME_SECONDS,
            "aud": "appstoreconnect-v1",
        },
        private_key,
        algorithm="ES256",
        headers={"kid": config["keyId"], "typ": "JWT"},
    )


def probe(token: str, path: str) -> tuple[int, str]:
    request = urllib.request.Request(
        f"{ASC}{path}?limit=1",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(request) as response:
            body = json.load(response)
            count = body.get("meta", {}).get("paging", {}).get("total", "?")
            return response.status, f"{count} total"
    except urllib.error.HTTPError as error:
        detail = ""
        try:
            payload = json.load(error)
            errors = payload.get("errors", [])
            if errors:
                detail = errors[0].get("detail") or errors[0].get("title", "")
        except Exception:
            detail = error.reason or ""
        return error.code, detail


def capabilities(token: str, identifier: str) -> None:
    """Prints the capabilities Apple currently has on record for [identifier].

    The point of this is the gap: `Runner.entitlements` is the *request*, and this is what
    the account will actually sign. An entitlement present in the file and absent here is
    exactly the three-error wall xcodebuild puts up, and it cannot be fixed from this
    machine — App Groups are not in the App Store Connect API's surface, so the group has
    to be created and assigned in the developer portal by hand, once.
    """
    request = urllib.request.Request(
        f"{ASC}/v1/bundleIds?filter[identifier]={identifier}"
        "&include=bundleIdCapabilities&limit=1",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(request) as response:
            body = json.load(response)
    except urllib.error.HTTPError as error:
        print(f"could not read capabilities for {identifier}: {error.code}")
        return

    if not body.get("data"):
        print(f"no App ID registered for {identifier}")
        return

    print(f"capabilities on record for {identifier}:")
    found = [
        item["attributes"]["capabilityType"]
        for item in body.get("included", [])
        if item.get("type") == "bundleIdCapabilities"
    ]
    for capability in sorted(found):
        print(f"  {capability}")
    if "APP_GROUPS" not in found:
        print("\n  APP_GROUPS is NOT among them, which is the blocker.")


def main(argv: list[str]) -> int:
    try:
        config = load_config()
    except FileNotFoundError:
        print("error: ios/asc.json not found -- see AGENTS.md.", file=sys.stderr)
        return 1

    print(f"key    {config['keyId']}")
    print(f"issuer {config['issuerId']}")
    print(f"p8     {config['keyPath']}")
    if not os.path.exists(config["keyPath"]):
        print("\nerror: the .p8 private key is missing at that path.", file=sys.stderr)
        print("Without it no token can be signed at all, which is the whole of", file=sys.stderr)
        print("xcodebuild's complaint.", file=sys.stderr)
        return 1

    token = bearer(config)
    print()

    results: dict[str, int] = {}
    for path in ("/v1/apps", "/v1/bundleIds", "/v1/profiles"):
        status, detail = probe(token, path)
        results[path] = status
        mark = "ok  " if status == 200 else "FAIL"
        print(f"{mark} {status}  {path:<16} {detail}")

    print()
    if results["/v1/apps"] != 200:
        print("The key cannot read even the app list, so this is not a role problem:")
        print("the key is expired, revoked, or the issuer/key id do not match the .p8.")
        print("Check Users and Access > Integrations > App Store Connect API.")
        return 1
    if results["/v1/profiles"] != 200:
        print("The key authenticates but cannot manage provisioning profiles, which is")
        print("what -allowProvisioningUpdates needs in order to add a capability.")
        print("Give this key the Admin or App Manager role, or generate one that has it.")
        return 1

    # Deliberately not claiming success outright: reading profiles and being allowed to
    # *modify* an App ID's capabilities are adjacent permissions, not identical ones.
    print("The key can read profiles, so cloud managed signing should be able to")
    print("reissue one — but only for capabilities the App ID already carries.")
    print()
    capabilities(token, "com.unicorn.bookwormFriends")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
