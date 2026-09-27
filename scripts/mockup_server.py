#!/usr/bin/env python3
"""A tiny local server for collecting design picks off a mockup page.

    .venv/bin/python scripts/mockup_server.py           # foreground
    .venv/bin/python scripts/mockup_server.py --port N  # if 8765 is taken

Then open http://127.0.0.1:8765/_widget_grid.html, tick the lines you want, edit any
text you want changed, and press Submit. Each submission lands in
`docs/mockups/streak-widget/_submissions/` as a timestamped JSON file AND is echoed to
this process's stdout, so it can be read back either way.

**Why a server rather than "copy this JSON out of the console".** The page already
renders every candidate; the missing half is getting a decision back without it being
retyped, because retyping is where a chosen line quietly becomes a slightly different
line. A POST to a file removes that step entirely: what is submitted is byte-for-byte
what was on screen, including edits.

Deliberately stdlib only -- no Flask, no dependency added to this repo for a tool that
exists to move a few hundred bytes across localhost. And deliberately bound to 127.0.0.1:
this writes files from unauthenticated POSTs, which is fine on loopback and is not fine
on anything else.
"""

from __future__ import annotations

import argparse
import datetime
import http.server
import json
import pathlib
import sys

ROOT = pathlib.Path("docs/mockups/streak-widget").resolve()
DROP = ROOT / "_submissions"
MAX_BODY = 2 * 1024 * 1024  # a submission is a few KB; this is only a sanity bound.


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(ROOT), **kw)

    # Quieter than the default, which logs every asset request and buries the one line
    # that matters -- the submission.
    #
    # `str(...)` on the arguments is not defensive noise: `log_error` calls this with an
    # HTTPStatus as its first argument, not a string, so an `in` test against it raises
    # TypeError *inside the error handler* and takes down the whole request thread. A
    # missing favicon.ico -- which every browser asks for -- was enough to trigger it.
    def log_message(self, fmt, *args):
        text = " ".join(str(a) for a in args)
        if "POST" in text or "error" in str(fmt).lower():
            sys.stderr.write("  %s\n" % text)

    # Browsers ask for this unprompted and its absence is not interesting. Answered here
    # so it cannot reach the 404 path at all.
    def do_GET(self):
        if self.path == "/favicon.ico":
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        super().do_GET()

    def do_POST(self):
        if self.path.rstrip("/") != "/submit":
            self.send_error(404, "only /submit accepts POST")
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            self.send_error(400, "bad Content-Length")
            return
        if length <= 0 or length > MAX_BODY:
            self.send_error(413, "body must be 1 byte to 2MB")
            return
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as exc:
            self.send_error(400, f"body is not JSON: {exc}")
            return

        DROP.mkdir(parents=True, exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        out = DROP / f"{stamp}.json"
        # The server's own timestamp goes in alongside the page's, because the page's
        # comes from a browser clock and this one does not.
        payload["receivedAt"] = datetime.datetime.now().isoformat(timespec="seconds")
        out.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")

        # Echoed to stdout so a submission is visible without opening the file. `latest`
        # is a plain copy rather than a symlink so it survives being read from anywhere.
        (DROP / "latest.json").write_text(out.read_text())
        print(f"\n=== submission {stamp} -> {out} ===")
        print(summarise(payload))
        sys.stdout.flush()

        body = json.dumps({"ok": True, "saved": out.name}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def summarise(p: dict) -> str:
    """A readable digest of one submission, for the terminal."""
    lines = []
    # Sheet B is now selected per card, so its picks are the headline -- printed first
    # since that is the sheet the round is actually about.
    pose_picks = p.get("posePicks") or []
    lines.append(f"pose picks: {len(pose_picks)}")
    for pp in pose_picks:
        mark = " (reposed)" if pp.get("reposed") else ""
        lines.append(f"  {pp.get('label'):<10} {pp.get('pose'):<12} {pp.get('text')!r}{mark}")
    picks = p.get("picks") or []
    lines.append(f"copy picks: {len(picks)}")
    for pick in picks:
        mark = " (EDITED)" if pick.get("edited") else ""
        lines.append(f"  {pick.get('label'):<16} {pick.get('text')!r}{mark}")
        if pick.get("edited"):
            lines.append(f"  {'':<16} was {pick.get('original')!r}")
    changed = p.get("poseChanges") or []
    if changed:
        lines.append(f"pose changes: {len(changed)}")
        for c in changed:
            lines.append(
                f"  {c.get('voice')}.{c.get('state'):<10} {c.get('from')} -> {c.get('to')}"
            )
    if p.get("notes"):
        lines.append("notes:")
        for ln in str(p["notes"]).splitlines():
            lines.append("  " + ln)
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()

    if not ROOT.is_dir():
        sys.exit(f"{ROOT} is not a directory -- run this from the repo root")

    srv = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/_widget_grid.html"
    print(f"serving {ROOT}")
    print(f"open    {url}")
    print(f"drops   {DROP}")
    print("ctrl-c to stop")
    sys.stdout.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
