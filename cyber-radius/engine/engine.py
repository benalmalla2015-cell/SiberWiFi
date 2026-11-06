#!/usr/bin/env python3
"""
engine.py — CyberNet ledger bridge (CYB-01).

Tails the FreeRADIUS detail ledgers (accounting `detail-*` and auth
`cyberauth-detail-*` files written by the `detail`/`cyberauth` modules) and
POSTs each record to the testapp Laravel backend.

Transport : POST $CYBER_ENGINE_URL  (JSON body {"source","events":[...]})
Auth      : Authorization: Bearer $CYBER_ENGINE_TOKEN
State     : per-file byte offsets in $ENGINE_STATE_DIR/offsets.json —
            offsets only advance after a 2xx response, so a backend
            outage means at-least-once delivery with no loss.

Only the Python standard library is used (container: python:3.12-alpine).
"""

import json
import logging
import os
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from email.utils import parsedate_to_datetime
from pathlib import Path

LOG_DIR = Path(os.environ.get("ENGINE_LOG_DIR", "/logs"))
STATE_DIR = Path(os.environ.get("ENGINE_STATE_DIR", "/state"))
STATE_FILE = STATE_DIR / "offsets.json"
POLL_INTERVAL = float(os.environ.get("ENGINE_POLL_INTERVAL", "5"))
BATCH_MAX = int(os.environ.get("ENGINE_BATCH_MAX", "200"))
HTTP_TIMEOUT = float(os.environ.get("ENGINE_HTTP_TIMEOUT", "15"))

ENGINE_URL = os.environ.get("CYBER_ENGINE_URL", "").strip()
ENGINE_TOKEN = os.environ.get("CYBER_ENGINE_TOKEN", "").strip()

if not ENGINE_URL or not ENGINE_TOKEN:
    sys.exit("CYBER_ENGINE_URL and CYBER_ENGINE_TOKEN are required")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("cyber-engine")

LEDGER_RE = re.compile(r"^(cyberauth-detail|detail)-\d{8}")
ATTR_RE = re.compile(r"^\t([A-Za-z0-9._-]+)\s*=\s*(.*)$")
HEADER_RE = re.compile(r"^[A-Z][a-z]{2} ")  # detail record header: "Mon Nov  2 ..."

ACCT_EVENTS = {
    "Start": "acct.start",
    "Stop": "acct.stop",
    "Interim-Update": "acct.interim",
    "Accounting-On": "acct.on",
    "Accounting-Off": "acct.off",
}


def load_state() -> dict:
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {}


def save_state(state: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state))
    tmp.replace(STATE_FILE)


def iter_ledgers():
    """Yield ledger files (detail-*/cyberauth-detail-*) newest-modified last."""
    if not LOG_DIR.is_dir():
        return
    for path in sorted(LOG_DIR.rglob("*")):
        if path.is_file() and LEDGER_RE.match(path.name):
            yield path


def parse_records(path: Path, offset: int):
    """
    Read complete detail records from `path` starting at `offset`.
    Returns (records, new_offset). A record ends on a blank line; a
    trailing partial record is left for the next pass.
    """
    size = path.stat().st_size
    if size < offset:  # rotated/truncated — start over
        offset = 0
    if size == offset:
        return [], offset

    records = []
    pos = offset
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        fh.seek(offset)
        header, attrs = None, {}
        while True:
            line_start = fh.tell()
            line = fh.readline()
            if not line:
                break
            stripped = line.rstrip("\n")
            if not stripped:
                if header is not None or attrs:
                    records.append((header, attrs, pos, fh.tell()))
                    pos = fh.tell()
                header, attrs = None, {}
                continue
            m = ATTR_RE.match(line)
            if m:
                attrs[m.group(1)] = m.group(2).strip('"')
            elif HEADER_RE.match(line):
                if header is not None or attrs:  # missing blank line — flush
                    records.append((header, attrs, pos, line_start))
                    pos = line_start
                header, attrs = line.strip(), {}
            # else: continuation/garbage line — ignore
        # `pos` points just past the last *complete* record.
    return records, pos


def classify(is_auth: bool, attrs: dict) -> str:
    if is_auth:
        outcome = attrs.get("Tmp-String-0") or attrs.get("Packet-Type", "")
        return {
            "Access-Accept": "auth.accept",
            "Access-Reject": "auth.reject",
        }.get(outcome, "auth.other")
    return ACCT_EVENTS.get(attrs.get("Acct-Status-Type", ""), "acct.other")


def to_event(path: Path, header, attrs, rec_end) -> dict:
    logged_at = None
    if header:
        try:
            logged_at = parsedate_to_datetime(header).isoformat()
        except (TypeError, ValueError):
            try:
                logged_at = datetime.strptime(header, "%a %b %d %H:%M:%S %Y").isoformat()
            except ValueError:
                logged_at = header

    return {
        "type": classify(path.name.startswith("cyberauth-detail"), attrs),
        "logged_at": logged_at,
        "subscriber": attrs.get("User-Name"),
        "nas": attrs.get("NAS-Identifier") or attrs.get("NAS-IP-Address"),
        "nas_ip": attrs.get("NAS-IP-Address"),
        "session_id": attrs.get("Acct-Session-Id"),
        "attributes": attrs,
        "source": {
            "file": str(path.relative_to(LOG_DIR)),
            "offset": rec_end,
        },
    }


def post_events(events: list) -> bool:
    body = json.dumps(
        {"source": "cyber-radius", "events": events}
    ).encode()
    req = urllib.request.Request(
        ENGINE_URL,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {ENGINE_TOKEN}",
            "X-Cyber-Source": "cyber-radius",
            "User-Agent": "cyber-engine/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            ok = 200 <= resp.status < 300
            if not ok:
                log.warning("backend returned HTTP %s", resp.status)
            return ok
    except urllib.error.HTTPError as exc:
        log.warning("backend HTTP %s: %s", exc.code, exc.read()[:200])
    except (urllib.error.URLError, OSError) as exc:
        log.warning("backend unreachable: %s", exc)
    return False


def main() -> None:
    state = load_state()
    log.info(
        "watching %s -> %s (poll %.1fs, batch %d)",
        LOG_DIR, ENGINE_URL, POLL_INTERVAL, BATCH_MAX,
    )
    backoff = POLL_INTERVAL

    while True:
        pending = []          # events to send
        marks = []            # (state_key, new_offset) applied on success
        saw_work = False

        for path in iter_ledgers():
            if len(pending) >= BATCH_MAX:
                break
            key = str(path.relative_to(LOG_DIR))
            offset = int(state.get(key, 0))
            try:
                records, new_pos = parse_records(path, offset)
            except OSError as exc:
                log.warning("cannot read %s: %s", path, exc)
                continue
            if not records:
                if new_pos != offset:
                    marks.append((key, new_pos))
                continue
            saw_work = True
            for header, attrs, _rec_start, rec_end in records:
                pending.append(to_event(path, header, attrs, rec_end))
                if len(pending) >= BATCH_MAX:
                    marks.append((key, rec_end))
                    break
            else:
                marks.append((key, new_pos))

        if pending:
            if post_events(pending):
                for key, new_offset in marks:
                    state[key] = new_offset
                save_state(state)
                log.info("forwarded %d event(s)", len(pending))
                backoff = POLL_INTERVAL
            else:
                # Keep offsets; retry with capped backoff.
                backoff = min(backoff * 2, 300)
                time.sleep(backoff)
                continue
        elif marks:  # file truncated with no complete records — still advance
            for key, new_offset in marks:
                state[key] = new_offset
            save_state(state)

        time.sleep(0.1 if saw_work else POLL_INTERVAL)


if __name__ == "__main__":
    main()
