#!/usr/bin/env python3
"""Backfill `books.authors` from the Kakao book catalogue.

A script rather than a SQL migration, because filling this column means one HTTP
request per distinct ISBN and a migration cannot make them.

Why Kakao and not Google Books
------------------------------
This library is Korean. Sampling 40 random finished books from
`migration_data/book.jsonl`:

    provider              ISBN found     authors present
    Kakao                 40 / 40        40 / 40
    Google Books (keyed)  16 / 40        --

Google Books simply does not have most of these titles. Kakao is also what the
app itself uses for `ko` locales (`book_search_provider.dart`), so backfilling
through it produces the same author strings a newly saved book gets, and the
"most-read author" tile is not split between "한강" and "Han Kang".

Resumability
------------
Every lookup is written to a cache file keyed by ISBN before any row is updated,
so a 429 or a dropped connection halfway through 600 books costs only the
in-flight request. Re-running skips everything already cached. The cache also
records ISBNs that Kakao has no document for, so they are not retried forever --
that is a real answer, not a failure.

Usage
-----
    python3 scripts/backfill_book_authors.py --dry-run     # look, change nothing
    python3 scripts/backfill_book_authors.py               # then do it

Credentials come from `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` if they are set,
and otherwise from the **linked Supabase CLI** -- the project ref in
`supabase/.temp/project-ref` plus `supabase projects api-keys --reveal`. That path
exists so the service key never has to be pasted into a shell, exported into an
environment, or written to a file where it can be committed by accident. It needs
nothing but a CLI that is already logged in and linked, which is what `supabase db
push` needs anyway.

The Kakao key is read from KAKAO_REST_API_KEY, falling back to `env.json` -- the same
file `--dart-define-from-file` uses, so there is one place to keep it.

Dependencies
------------
None beyond the standard library. Talks to PostgREST over HTTP directly rather than
through the `supabase` package, which `import_to_supabase.py` uses -- that script
creates auth users and genuinely needs a client, whereas this one makes a single GET
and a handful of PATCHes. Worth the difference: this runs on a bare `python3` with no
virtualenv, which matters for a script somebody will reach for once, months from now.
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
KAKAO_ENDPOINT = "https://dapi.kakao.com/v3/search/book"

# Kakao's documented ceiling is generous, but the whole corpus is only a few
# hundred distinct ISBNs, so there is nothing to gain by going fast and a 429
# costs a restart. Roughly four requests a second.
THROTTLE_SECONDS = 0.25

# Retries are for transport failures and 429s only. A 200 with no documents is a
# final answer and is cached as such.
MAX_RETRIES = 4

CACHE_PATH = Path(__file__).parent / ".author_backfill_cache.json"


def kakao_key() -> str:
    key = os.environ.get("KAKAO_REST_API_KEY", "")
    if key:
        return key
    env_file = PROJECT_ROOT / "env.json"
    if env_file.exists():
        return json.load(open(env_file)).get("KAKAO_REST_API_KEY", "")
    return ""


def supabase_credentials() -> tuple[str, str]:
    """The project URL and a service-role key, from the environment or the CLI.

    Environment first, so CI can override. Otherwise the linked CLI answers: the ref
    comes from `supabase/.temp/project-ref` (written by `supabase link`) and the key
    from `supabase projects api-keys --reveal`.

    Prefers a modern `sb_secret_...` key whose JWT template is service_role, and falls
    back to the legacy `service_role` key. Both bypass RLS, which this needs: it is
    writing rows belonging to 55 different users.

    Returns empty strings rather than raising, so the caller can print one message
    naming every way to supply them.
    """
    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if url and key:
        return url, key

    ref_file = PROJECT_ROOT / "supabase" / ".temp" / "project-ref"
    if not ref_file.exists():
        return url, key
    ref = ref_file.read_text().strip()

    try:
        raw = subprocess.run(
            [
                "supabase",
                "projects",
                "api-keys",
                "--project-ref",
                ref,
                "--reveal",
                "--output",
                "json",
            ],
            capture_output=True,
            text=True,
            timeout=60,
            check=True,
        ).stdout
        keys = json.loads(raw)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return url, key

    def pick(predicate) -> str:
        for entry in keys:
            if predicate(entry):
                return entry.get("api_key") or ""
        return ""

    resolved = pick(
        lambda e: e.get("type") == "secret"
        and (e.get("secret_jwt_template") or {}).get("role") == "service_role"
    ) or pick(lambda e: e.get("id") == "service_role")

    return url or f"https://{ref}.supabase.co", key or resolved


def load_cache() -> dict:
    if CACHE_PATH.exists():
        return json.load(open(CACHE_PATH))
    return {}


def save_cache(cache: dict) -> None:
    # Written through a temp file: the whole point of the cache is to survive a
    # crash, and a crash during the write itself would corrupt it.
    tmp = CACHE_PATH.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(cache, f, ensure_ascii=False, indent=1)
    tmp.replace(CACHE_PATH)


def lookup_authors(isbn: str, key: str) -> list[str] | None:
    """Authors for an ISBN, `[]` when Kakao knows the book but lists none, and
    None when Kakao has no document for it at all.

    The three cases are kept apart here and collapsed by the caller, because the
    cache wants to remember which one happened.
    """
    url = f"{KAKAO_ENDPOINT}?{urllib.parse.urlencode({'target': 'isbn', 'query': isbn})}"
    request = urllib.request.Request(url, headers={"Authorization": f"KakaoAK {key}"})

    for attempt in range(MAX_RETRIES):
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                payload = json.load(response)
            documents = payload.get("documents") or []
            if not documents:
                return None
            # First document *with authors*, not simply the first document. Kakao
            # can return several records for one ISBN -- querying 0000000000000
            # returns three, and the first of them lists no author while the second
            # does. Taking documents[0] blindly would cache an empty answer for a
            # book Kakao can actually name.
            for document in documents:
                authors = [a for a in (document.get("authors") or []) if a.strip()]
                if authors:
                    return authors
            return []
        except urllib.error.HTTPError as error:
            if error.code == 429 and attempt < MAX_RETRIES - 1:
                backoff = 2 ** (attempt + 1)
                print(f"    rate limited, sleeping {backoff}s", flush=True)
                time.sleep(backoff)
                continue
            raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < MAX_RETRIES - 1:
                time.sleep(2 ** (attempt + 1))
                continue
            raise
    return None


def rest_headers(service_key: str) -> dict:
    return {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }


def rest_get(url: str, service_key: str, table: str, params: dict) -> list[dict]:
    """Every row of [table], paged past PostgREST's default ceiling.

    Paged rather than trusting one request: PostgREST caps an unbounded select at
    1,000 rows by default, and it does so *silently* -- a corpus that outgrows the cap
    would look like a corpus that had been fully backfilled. 624 books fit today, which
    is exactly the situation in which this is easy to get wrong and never notice.
    """
    page_size = 1000
    offset = 0
    collected: list[dict] = []
    while True:
        query = dict(params)
        query["limit"] = str(page_size)
        query["offset"] = str(offset)
        endpoint = f"{url}/rest/v1/{table}?{urllib.parse.urlencode(query)}"
        request = urllib.request.Request(endpoint, headers=rest_headers(service_key))
        with urllib.request.urlopen(request, timeout=30) as response:
            page = json.load(response)
        collected.extend(page)
        if len(page) < page_size:
            return collected
        offset += page_size


def rest_patch_ids(
    url: str, service_key: str, table: str, ids: list[str], payload: dict
) -> None:
    """Updates exactly the rows named in [ids]."""
    # `in.(...)` needs the values quoted, because a uuid is passed as a string and an
    # unquoted list is parsed positionally.
    quoted = ",".join(f'"{row_id}"' for row_id in ids)
    endpoint = (
        f"{url}/rest/v1/{table}?"
        + urllib.parse.urlencode({"id": f"in.({quoted})"})
    )
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode(),
        headers={**rest_headers(service_key), "Prefer": "return=minimal"},
        method="PATCH",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="resolve authors and report, but write nothing to Supabase",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="stop after this many distinct ISBNs (0 = all)",
    )
    args = parser.parse_args()

    url, service_key = supabase_credentials()
    if not url or not service_key:
        print(
            "No Supabase credentials. Either set SUPABASE_URL and "
            "SUPABASE_SERVICE_ROLE_KEY, or link the CLI (`supabase link "
            "--project-ref <ref>`) and log in (`supabase login`)."
        )
        return 1

    key = kakao_key()
    if not key:
        print("Set KAKAO_REST_API_KEY, or put it in env.json")
        return 1

    # Only rows that still have the default. Re-running is therefore cheap, and a
    # book whose authors were entered by hand is never overwritten.
    rows = rest_get(url, service_key, "books", {"select": "id,isbn,authors"})
    pending = [r for r in rows if not r.get("authors")]

    # Per distinct ISBN, not per row: books are per-user rows, so a popular title
    # appears many times and one lookup answers for all of them.
    by_isbn: dict[str, list[str]] = {}
    no_isbn = 0
    for row in pending:
        isbn = (row.get("isbn") or "").strip()
        if not isbn:
            no_isbn += 1
            continue
        by_isbn.setdefault(isbn, []).append(row["id"])

    print(f"{len(rows)} books, {len(pending)} without authors")
    print(f"{len(by_isbn)} distinct ISBNs to look up")
    if no_isbn:
        # 15 of the migrated rows are like this. They keep '{}' forever, which is
        # the correct answer for a book nobody can identify.
        print(f"{no_isbn} rows have no ISBN and cannot be looked up -- skipped")

    cache = load_cache()
    isbns = list(by_isbn)
    if args.limit:
        isbns = isbns[: args.limit]

    resolved = unknown = empty = 0
    for index, isbn in enumerate(isbns, start=1):
        if isbn in cache:
            entry = cache[isbn]
        else:
            try:
                authors = lookup_authors(isbn, key)
            except Exception as error:  # noqa: BLE001 -- report and stop, resumably
                print(f"\nstopped at {isbn}: {error}")
                print("cache is intact; re-run to continue from here")
                save_cache(cache)
                return 1
            entry = {"authors": authors if authors is not None else [], "found": authors is not None}
            cache[isbn] = entry
            save_cache(cache)
            time.sleep(THROTTLE_SECONDS)

        if not entry["found"]:
            unknown += 1
        elif not entry["authors"]:
            empty += 1
        else:
            resolved += 1

        if index % 25 == 0 or index == len(isbns):
            print(
                f"  {index}/{len(isbns)}  resolved={resolved} "
                f"listed-no-authors={empty} not-in-kakao={unknown}",
                flush=True,
            )

    print()
    print(f"resolved authors for {resolved} of {len(isbns)} ISBNs")

    if args.dry_run:
        print("dry run -- nothing written")
        sample = [(i, cache[i]["authors"]) for i in isbns[:5] if cache[i]["authors"]]
        for isbn, authors in sample:
            print(f"    {isbn} -> {authors}")
        return 0

    written = 0
    for isbn in isbns:
        authors = cache[isbn]["authors"]
        if not authors:
            continue
        # By row id, not by ISBN. Updating `where isbn = ...` would be one
        # statement instead of a handful, but it would also reach rows this run
        # deliberately excluded -- another user's copy of the same title whose
        # authors are already set. The id list is exactly the rows that had the
        # default.
        ids = by_isbn[isbn]
        for start in range(0, len(ids), 100):
            chunk = ids[start : start + 100]
            try:
                rest_patch_ids(url, service_key, "books", chunk, {"authors": authors})
            except urllib.error.HTTPError as error:
                detail = error.read().decode(errors="replace")[:300]
                print(f"\nfailed writing {isbn}: HTTP {error.code} {detail}")
                print(f"{written} rows were written before this; re-run to continue")
                return 1
            written += len(chunk)

    print(f"wrote authors to {written} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
