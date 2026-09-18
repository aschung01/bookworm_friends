#!/usr/bin/env python3
"""Backfill `books.page_count` from Google Books, then Open Library.

A script rather than a SQL migration, for the same reason as
`backfill_book_authors.py`: filling this column means one HTTP request per distinct
ISBN and a migration cannot make them.

Expect low coverage, and that is fine
-------------------------------------
Unlike authors, this column cannot be filled for most of the library. Kakao is the
provider that actually knows these books -- `backfill_book_authors.py` measured
40/40 ISBNs found against Google Books' 16/40 -- and Kakao's book document has no
page field at all. Eleven keys, none of them pages. So the only sources are the two
that barely have the corpus.

That is not a reason to skip the run. The column feeds one thing: a book's drawn
thickness, which is *invented* today -- `BookJitter` hashes the ISBN, so a
1,200-page novel has even odds of being drawn thinner than a novella. A reader
cannot tell a hashed thickness from a measured one, so filling a third of the shelf
makes a third of it correct and leaves the rest exactly as plausible as it already
was. Nothing regresses. See `supabase/migrations/20260816160000_book_page_count.sql`
for why that argument holds here and did *not* hold for the Library Card's
page-count stat, which was cut.

Two sources, in the app's own order
-----------------------------------
Google Books first, Open Library second, mirroring `FallbackBookSearchProvider`.
Open Library is queried per edition (`/isbn/{isbn}.json` -> `number_of_pages`)
rather than through search's `number_of_pages_median`, because here we have an exact
ISBN and can get that edition's real count instead of a median across every printing.

`pageCount: 0` is not a page count
----------------------------------
Google returns `0` for volumes it has no count for, rather than omitting the key.
Banked naively it becomes the thinnest book on the shelf, presented as data. Zero and
negative values are treated as absence everywhere in this script, matching
`GoogleBooksSearchProvider._mapVolume` and `Book.fromJson`.

Resumability
------------
Every lookup is cached by ISBN before any row is updated, so a 429 or a dropped
connection partway through costs only the in-flight request. Re-running skips what is
cached, including the ISBNs that neither source knows -- that is a real answer, not a
failure, and retrying it forever is how a backfill script becomes a rate-limit
problem.

Usage
-----
    python3 scripts/backfill_book_page_count.py --dry-run     # look, change nothing
    python3 scripts/backfill_book_page_count.py               # then do it

Credentials follow `backfill_book_authors.py` exactly: `SUPABASE_URL` /
`SUPABASE_SERVICE_ROLE_KEY` if set, otherwise the linked Supabase CLI. The Google key
is read from GOOGLE_BOOKS_API_KEY, falling back to `env.json` -- the same file
`--dart-define-from-file` uses. Running keyless works but Google's anonymous quota is
low enough that a few hundred ISBNs will hit 429s.

Dependencies
------------
None beyond the standard library.
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
GOOGLE_ENDPOINT = "https://www.googleapis.com/books/v1/volumes"
OPENLIBRARY_ISBN_ENDPOINT = "https://openlibrary.org/isbn"

# Google's keyed quota is generous; the anonymous one is not, and a 429 costs a
# restart rather than a retry storm. Roughly three requests a second.
THROTTLE_SECONDS = 0.35

# Retries are for transport failures and 429s only. A 200 with no usable count is a
# final answer and is cached as such.
MAX_RETRIES = 4

# Below this a "page count" is a cataloguing artefact, not a book. Mirrors
# `kBookMinCrediblePageCount` in `book_geometry.dart`; kept in sync by hand because
# duplicating one integer is cheaper than a shared config for a script run twice.
MIN_CREDIBLE_PAGES = 20

CACHE_PATH = Path(__file__).parent / ".page_count_backfill_cache.json"


def google_key() -> str:
    key = os.environ.get("GOOGLE_BOOKS_API_KEY", "")
    if key:
        return key
    env_file = PROJECT_ROOT / "env.json"
    if env_file.exists():
        return json.load(open(env_file)).get("GOOGLE_BOOKS_API_KEY", "")
    return ""


def supabase_credentials() -> tuple[str, str]:
    """The project URL and a service-role key, from the environment or the CLI.

    Identical to `backfill_book_authors.py`. Duplicated rather than imported: these
    are standalone scripts somebody reaches for once, months apart, and a shared
    module would mean remembering which directory to run them from.
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
    # Written through a temp file: the point of the cache is to survive a crash, and
    # a crash during the write itself would corrupt it.
    tmp = CACHE_PATH.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(cache, f, ensure_ascii=False, indent=1)
    tmp.replace(CACHE_PATH)


def credible(value) -> int | None:
    """[value] as a page count, or None if it is not one.

    Catches Google's `0` sentinel, negative values, floats, and the strings Open
    Library occasionally puts in `number_of_pages`.
    """
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        pages = int(value)
    elif isinstance(value, str) and value.strip().isdigit():
        pages = int(value.strip())
    else:
        return None
    return pages if pages >= MIN_CREDIBLE_PAGES else None


def _get_json(url: str, headers: dict | None = None):
    """GET and parse, retrying transport failures and 429s. None on 404."""
    request = urllib.request.Request(url, headers=headers or {})
    for attempt in range(MAX_RETRIES):
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # 404 is Open Library saying it has no such edition, which is an answer.
            if error.code == 404:
                return None
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


def lookup_google(isbn: str, key: str) -> int | None:
    params = {"q": f"isbn:{isbn}", "maxResults": "5", "printType": "books"}
    if key:
        params["key"] = key
    payload = _get_json(f"{GOOGLE_ENDPOINT}?{urllib.parse.urlencode(params)}")
    for item in (payload or {}).get("items") or []:
        # First volume *with a usable count*, not simply the first volume. Google can
        # return several editions for one ISBN and the first often carries
        # `pageCount: 0` while a later one has the real number.
        pages = credible((item.get("volumeInfo") or {}).get("pageCount"))
        if pages:
            return pages
    return None


def lookup_openlibrary(isbn: str) -> int | None:
    payload = _get_json(
        f"{OPENLIBRARY_ISBN_ENDPOINT}/{urllib.parse.quote(isbn)}.json",
        headers={"User-Agent": "bookworm-friends-backfill/1.0"},
    )
    if not payload:
        return None
    return credible(payload.get("number_of_pages"))


def rest_headers(service_key: str) -> dict:
    return {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }


def rest_get(url: str, service_key: str, table: str, params: dict) -> list[dict]:
    """Every row of [table], paged past PostgREST's silent 1,000-row ceiling.

    Unbounded selects are capped without saying so, and a corpus that outgrew the cap
    would look exactly like a corpus that had been fully backfilled.
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
    """Updates exactly the rows named in [ids].

    Retries transport failures, 429s and 5xxs, exactly as the lookup path does. The
    first version of this did not, and one `Operation timed out` partway through
    killed the run with a traceback after 102 rows. It was resumable only because the
    select filters on NULL, which is luck rather than handling -- a write path that
    can fail needs the same retry as a read path that can.

    Safe to retry: the PATCH sets a fixed value on a fixed set of ids, so replaying
    it after an uncertain outcome cannot double-apply anything.
    """
    # `in.(...)` needs the values quoted: a uuid is passed as a string and an
    # unquoted list is parsed positionally.
    quoted = ",".join(f'"{row_id}"' for row_id in ids)
    endpoint = f"{url}/rest/v1/{table}?" + urllib.parse.urlencode(
        {"id": f"in.({quoted})"}
    )
    for attempt in range(MAX_RETRIES):
        request = urllib.request.Request(
            endpoint,
            data=json.dumps(payload).encode(),
            headers={**rest_headers(service_key), "Prefer": "return=minimal"},
            method="PATCH",
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                response.read()
            return
        except urllib.error.HTTPError as error:
            if error.code in (429, 500, 502, 503, 504) and attempt < MAX_RETRIES - 1:
                backoff = 2 ** (attempt + 1)
                print(f"    write failed {error.code}, sleeping {backoff}s", flush=True)
                time.sleep(backoff)
                continue
            raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < MAX_RETRIES - 1:
                backoff = 2 ** (attempt + 1)
                print(f"    write timed out, sleeping {backoff}s", flush=True)
                time.sleep(backoff)
                continue
            raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="resolve page counts and report, but write nothing to Supabase",
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

    key = google_key()
    if not key:
        print(
            "No GOOGLE_BOOKS_API_KEY (env or env.json) -- running keyless. "
            "Google's anonymous quota is low; expect 429s on a few hundred ISBNs."
        )

    # Only rows still NULL, so re-running is cheap and a count entered by hand is
    # never overwritten.
    rows = rest_get(url, service_key, "books", {"select": "id,isbn,page_count"})
    pending = [r for r in rows if r.get("page_count") is None]

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

    print(f"{len(rows)} books, {len(pending)} without a page count")
    print(f"{len(by_isbn)} distinct ISBNs to look up")
    if no_isbn:
        # These stay NULL forever, which is the correct answer for a book nobody can
        # identify -- and it simply means their thickness keeps coming from the hash.
        print(f"{no_isbn} rows have no ISBN and cannot be looked up -- skipped")

    cache = load_cache()
    isbns = list(by_isbn)
    if args.limit:
        isbns = isbns[: args.limit]

    from_google = from_openlibrary = unknown = 0
    for index, isbn in enumerate(isbns, start=1):
        if isbn in cache:
            entry = cache[isbn]
        else:
            try:
                pages = lookup_google(isbn, key)
                source = "google" if pages else None
                if not pages:
                    time.sleep(THROTTLE_SECONDS)
                    pages = lookup_openlibrary(isbn)
                    source = "openlibrary" if pages else None
            except Exception as error:  # noqa: BLE001 -- report and stop, resumably
                print(f"\nstopped at {isbn}: {error}")
                print("cache is intact; re-run to continue from here")
                save_cache(cache)
                return 1
            entry = {"pages": pages, "source": source}
            cache[isbn] = entry
            save_cache(cache)
            time.sleep(THROTTLE_SECONDS)

        if entry["source"] == "google":
            from_google += 1
        elif entry["source"] == "openlibrary":
            from_openlibrary += 1
        else:
            unknown += 1

        if index % 25 == 0 or index == len(isbns):
            print(
                f"  {index}/{len(isbns)}  google={from_google} "
                f"openlibrary={from_openlibrary} unknown={unknown}",
                flush=True,
            )

    resolved = from_google + from_openlibrary
    print()
    print(
        f"resolved a page count for {resolved} of {len(isbns)} ISBNs "
        f"({resolved * 100 // max(len(isbns), 1)}%)"
    )
    print("the rest keep their hashed thickness, which is what they have today")

    if args.dry_run:
        print("dry run -- nothing written")
        for isbn in isbns[:8]:
            entry = cache[isbn]
            if entry["pages"]:
                print(f"    {isbn} -> {entry['pages']} pages ({entry['source']})")
        return 0

    written = 0
    for isbn in isbns:
        pages = cache[isbn]["pages"]
        if not pages:
            continue
        # By row id, not `where isbn = ...`. One statement per ISBN would be fewer
        # requests but would also reach rows this run deliberately excluded -- another
        # user's copy of the same title whose count is already set.
        ids = by_isbn[isbn]
        for start in range(0, len(ids), 100):
            chunk = ids[start : start + 100]
            try:
                rest_patch_ids(
                    url, service_key, "books", chunk, {"page_count": pages}
                )
            except urllib.error.HTTPError as error:
                detail = error.read().decode(errors="replace")[:300]
                print(f"\nfailed writing {isbn}: HTTP {error.code} {detail}")
                print(f"{written} rows were written before this; re-run to continue")
                return 1
            except (urllib.error.URLError, TimeoutError) as error:
                # Retries are already exhausted by this point. Reported rather than
                # raised so the run ends with a count and an instruction instead of a
                # traceback -- the lookups are cached, so re-running only redoes the
                # writes that did not land.
                print(f"\nfailed writing {isbn}: {error}")
                print(f"{written} rows were written before this; re-run to continue")
                return 1
            written += len(chunk)

    print(f"wrote a page count to {written} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
