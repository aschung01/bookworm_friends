#!/usr/bin/env python3
"""Mint or inspect the Apple client secret that Supabase's Apple provider needs.

**Why this exists.** The value in Supabase's "Secret Key (for OAuth)" field is not a
key -- it is a short-lived ES256 JWT signed *by* a key, and Apple caps its lifetime at
six months. When it expires, `signInWithOAuth(OAuthProvider.apple)` starts failing for
everyone and nothing in the app changes to explain it. Supabase's own docs point at a
browser tool that wants the `.p8` pasted into a web page; this does the same arithmetic
locally.

    # What is currently configured? Reveal the value in the Supabase dashboard,
    # paste it into a file, and read its claims back. No key needed -- a JWT's
    # payload is only base64, so this works on a secret you cannot sign.
    ./scripts/apple_client_secret.py --decode build/current-secret.txt

    # Mint a replacement, good for six months.
    ./scripts/apple_client_secret.py --mint \
        --key ~/Downloads/AuthKey_QKZ8QK6SWU.p8 --key-id QKZ8QK6SWU

**The signing key is not the App Store Connect key.** `ios/asc.json` points at
`AuthKey_345369BRVZ.p8`, which comes from Users and Access > Integrations and can only
talk to the App Store Connect API. A Sign in with Apple secret must be signed by a key
created under Certificates, Identifiers and Profiles > Keys with the Sign in with Apple
capability enabled and a primary App ID selected. They are both P-256 keys in the same
file format, which is exactly why they get confused -- `--decode` reports the `kid` of
whatever signed the live secret, which is the only reliable way to tell which key is
actually in use.

Apple only lets a `.p8` be downloaded once. If neither key on disk is the right one,
revoke the old Sign in with Apple key in the portal and create a new one; nothing here
depends on the old one's identity.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import stat
import sys
import time

import jwt

# The three fixed facts. Team ID is the signing team recorded in AGENTS.md; the
# Services ID is the SERVICES identifier already registered in the developer account
# (`com.bookwormFriends.signin`, "Bookworm Friends Sign in"), confirmed present with
# the APPLE_ID_AUTH capability via the App Store Connect API.
TEAM_ID = "58P4CVB7L8"
SERVICES_ID = "com.bookwormFriends.signin"
AUDIENCE = "https://appleid.apple.com"

# Apple's hard ceiling on a client secret's lifetime: 6 months to the second. A JWT
# asking for more is rejected outright rather than clamped, which presents as an
# opaque `invalid_client`.
MAX_LIFETIME_SECONDS = 15777000

DEFAULT_OUT = "build/apple_client_secret.txt"


def _b64(segment: str) -> dict:
    """Decode one base64url JWT segment. Padding is re-added; JWTs strip it."""
    return json.loads(base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4)))


def decode(path: str) -> int:
    if path == "-":
        raw = sys.stdin.read().strip()
    else:
        try:
            with open(path) as fh:
                raw = fh.read().strip()
        except FileNotFoundError:
            print(f"error: {path} does not exist yet.", file=sys.stderr)
            print(file=sys.stderr)
            print("This reads a secret you already have; it does not fetch one. Get the", file=sys.stderr)
            print("current value out of the Supabase dashboard first:", file=sys.stderr)
            print(file=sys.stderr)
            print("  Authentication > Sign In / Providers > Apple > Secret Key > Reveal,", file=sys.stderr)
            print("  select it, copy, then:", file=sys.stderr)
            print(file=sys.stderr)
            print(f"    mkdir -p {os.path.dirname(path) or '.'} && pbpaste > {path}", file=sys.stderr)
            print(f"    .venv/bin/python scripts/apple_client_secret.py --decode {path}", file=sys.stderr)
            print(file=sys.stderr)
            print("Or pipe it straight in without a file at all:", file=sys.stderr)
            print("    pbpaste | .venv/bin/python scripts/apple_client_secret.py --decode -", file=sys.stderr)
            print(file=sys.stderr)
            print("If the field is empty, or you would rather not handle the old value,", file=sys.stderr)
            print("skip this entirely and just mint a replacement -- see --mint.", file=sys.stderr)
            return 2

    if not raw:
        print("error: nothing to decode -- the input was empty.", file=sys.stderr)
        return 2
    if raw.count(".") != 2:
        print(
            f"error: {path} does not hold a JWT (expected three dot-separated parts).",
            file=sys.stderr,
        )
        print(
            "A client secret looks like `eyJ...`. If what you pasted is the contents of a\n"
            ".p8 file, that is the signing *key*, not the secret -- pass it to --mint instead.",
            file=sys.stderr,
        )
        return 2

    header_b64, payload_b64, _ = raw.split(".")
    header, claims = _b64(header_b64), _b64(payload_b64)
    now = int(time.time())
    exp, iat = claims.get("exp"), claims.get("iat")

    print(f"signed by key   {header.get('kid')!r}  (alg {header.get('alg')})")
    print(f"team    (iss)   {claims.get('iss')!r}")
    print(f"client  (sub)   {claims.get('sub')!r}")
    print(f"audience(aud)   {claims.get('aud')!r}")
    if iat:
        print(f"issued          {dt.datetime.fromtimestamp(iat):%Y-%m-%d %H:%M}")
    if exp:
        left = exp - now
        when = dt.datetime.fromtimestamp(exp)
        state = f"{left // 86400} days left" if left > 0 else "**EXPIRED**"
        print(f"expires         {when:%Y-%m-%d %H:%M}  ({state})")

    print()
    problems = []
    if claims.get("iss") != TEAM_ID:
        problems.append(f"iss is not the signing team {TEAM_ID}")
    if claims.get("sub") != SERVICES_ID:
        problems.append(
            f"sub is {claims.get('sub')!r}, not the Services ID {SERVICES_ID!r}. "
            "Apple matches this against the client_id Supabase sends, so the two "
            "must agree -- and Client IDs in Supabase must list that same Services "
            "ID first."
        )
    if claims.get("aud") != AUDIENCE:
        problems.append(f"aud is not {AUDIENCE}")
    if exp and exp <= now:
        problems.append("it has expired; mint a replacement")
    if iat and exp and exp - iat > MAX_LIFETIME_SECONDS:
        problems.append("lifetime exceeds Apple's 6-month ceiling")

    if problems:
        for p in problems:
            print(f"  !! {p}")
        return 1
    print("  ok -- team, client and audience all match, and it has not expired.")
    return 0


def mint(key_path: str, key_id: str, services_id: str, days: int, out: str) -> int:
    lifetime = min(days * 86400, MAX_LIFETIME_SECONDS)
    expanded = os.path.expanduser(key_path)
    try:
        with open(expanded) as fh:
            private_key = fh.read()
    except FileNotFoundError:
        print(f"error: no .p8 at {expanded}", file=sys.stderr)
        print(file=sys.stderr)
        print("Keys found on this machine:", file=sys.stderr)
        for candidate in (
            "~/private_keys",
            "~/Downloads",
            "~/Desktop",
        ):
            folder = os.path.expanduser(candidate)
            if not os.path.isdir(folder):
                continue
            for name in sorted(os.listdir(folder)):
                if name.endswith(".p8"):
                    print(f"  {candidate}/{name}", file=sys.stderr)
        print(file=sys.stderr)
        print("Remember that the App Store Connect key (the one ios/asc.json points at)", file=sys.stderr)
        print("cannot sign an Apple client secret -- see docs/apple-sign-in.md.", file=sys.stderr)
        return 2
    if "PRIVATE KEY" not in private_key:
        print(f"error: {key_path} does not look like a .p8 private key.", file=sys.stderr)
        return 2

    now = int(time.time())
    secret = jwt.encode(
        {
            "iss": TEAM_ID,
            "iat": now,
            "exp": now + lifetime,
            "aud": AUDIENCE,
            # The client_id Supabase will present. For the web OAuth flow this is the
            # Services ID, never the app's bundle ID.
            "sub": services_id,
        },
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "alg": "ES256"},
    )

    # Written to a file rather than printed, so the secret does not end up in shell
    # history, scrollback, or a transcript. `build/` is gitignored.
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w") as fh:
        fh.write(secret + "\n")
    os.chmod(out, stat.S_IRUSR | stat.S_IWUSR)

    print(f"wrote {out}  (mode 0600, {len(secret)} chars)")
    print(f"  signed by key {key_id}")
    print(f"  sub  {services_id}")
    print(f"  exp  {dt.datetime.fromtimestamp(now + lifetime):%Y-%m-%d}  "
          f"({lifetime // 86400} days)")
    print()
    print("Paste it into Supabase > Authentication > Sign In / Providers > Apple >")
    print('"Secret Key (for OAuth)", then Save. Set a reminder to rotate before that date.')
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--decode",
        metavar="PATH",
        help="inspect a secret you already have; `-` reads stdin",
    )
    group.add_argument("--mint", action="store_true", help="sign a new secret")
    parser.add_argument("--key", help="path to the Sign in with Apple .p8")
    parser.add_argument("--key-id", help="the 10-character Key ID of that .p8")
    parser.add_argument("--services-id", default=SERVICES_ID)
    parser.add_argument("--days", type=int, default=180)
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()

    if args.decode:
        return decode(args.decode)
    if not args.key or not args.key_id:
        parser.error("--mint needs --key and --key-id")
    return mint(args.key, args.key_id, args.services_id, args.days, args.out)


if __name__ == "__main__":
    raise SystemExit(main())
