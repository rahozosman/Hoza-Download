"""Hoza Download reference backend.

Four small endpoints, all optional for the app:

  GET  /ping            -> 204, used by the phone to tell a real network from
                           one Android merely believes in.
  GET  /config          -> the remote config JSON (ETag + Cache-Control), read
                           from config/extractors.json so editing the file is
                           the whole release process.
  POST /events          -> anonymous counters from the app: which platform,
                           which outcome, which app version. Aggregated in
                           memory and written to events.jsonl; nothing about
                           the user or the post is ever received.
  POST /resolve         -> optional fallback resolver backed by yt-dlp, for
                           links the phone cannot read itself (region blocks,
                           markup changes). Rate-limited per client.

Run locally:   uvicorn app:app --host 0.0.0.0 --port 8080
Run in Docker: docker build -t hoza-backend . && docker run -p 8080:8080 hoza-backend
"""

from __future__ import annotations

import hashlib
import json
import os
import threading
import time
from collections import Counter, defaultdict, deque
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parent
CONFIG_FILE = ROOT / "config" / "extractors.json"
EVENTS_FILE = ROOT / "events.jsonl"

# How many /resolve calls one client may make per minute. The app only asks
# after its own extraction failed, so this is generous for real use and tight
# for abuse.
RESOLVE_PER_MINUTE = int(os.environ.get("HOZA_RESOLVE_PER_MINUTE", "6"))

app = FastAPI(title="Hoza Download backend", version="1.0.0")

_lock = threading.Lock()
_counts: Counter[tuple[str, str, str]] = Counter()
_resolve_calls: dict[str, deque[float]] = defaultdict(deque)


# ----------------------------------------------------------------- /ping


@app.get("/ping", status_code=204)
def ping() -> Response:
    """Answers with no body. A captive portal would answer with a page."""
    return Response(status_code=204)


# --------------------------------------------------------------- /config


def _read_config() -> tuple[bytes, str]:
    body = CONFIG_FILE.read_bytes()
    # Validate on every read so a typo in the file is a 500 here, not a
    # silently ignored config on every phone.
    json.loads(body)
    etag = '"' + hashlib.sha256(body).hexdigest()[:32] + '"'
    return body, etag


@app.get("/config")
def config(request: Request) -> Response:
    body, etag = _read_config()
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers={"ETag": etag})
    return Response(
        content=body,
        media_type="application/json",
        headers={"ETag": etag, "Cache-Control": "public, max-age=3600"},
    )


# --------------------------------------------------------------- /events


class Event(BaseModel):
    event: str = Field(max_length=40)
    platform: str = Field(max_length=40)
    provider: str | None = Field(default=None, max_length=40)
    reason: str | None = Field(default=None, max_length=40)
    app: str = Field(max_length=20)
    os: str | None = Field(default=None, max_length=120)
    at: str | None = Field(default=None, max_length=40)


class EventBatch(BaseModel):
    events: list[Event] = Field(max_length=100)


@app.post("/events", status_code=202)
def events(batch: EventBatch) -> dict[str, int]:
    with _lock:
        with EVENTS_FILE.open("a", encoding="utf-8") as sink:
            for event in batch.events:
                _counts[(event.platform, event.event, event.reason or "")] += 1
                sink.write(json.dumps(event.model_dump(), ensure_ascii=False) + "\n")
    return {"accepted": len(batch.events)}


@app.get("/events/summary")
def events_summary() -> dict[str, Any]:
    """The last thing you check when someone says 'Instagram is broken'."""
    with _lock:
        rows = [
            {"platform": p, "event": e, "reason": r, "count": n}
            for (p, e, r), n in sorted(_counts.items(), key=lambda kv: -kv[1])
        ]
    return {"since_start": rows}


# -------------------------------------------------------------- /resolve


class ResolveRequest(BaseModel):
    url: str = Field(max_length=2048)


def _allow_resolve(client: str) -> bool:
    now = time.monotonic()
    calls = _resolve_calls[client]
    while calls and now - calls[0] > 60:
        calls.popleft()
    if len(calls) >= RESOLVE_PER_MINUTE:
        return False
    calls.append(now)
    return True


@app.post("/resolve")
def resolve(body: ResolveRequest, request: Request) -> JSONResponse:
    """Server-side lookup with yt-dlp. Returns direct media URLs and headers.

    The phone tries this only after its own providers failed. The answer has
    the same shape the app's providers produce, so it slots into the same
    download path.
    """
    client = request.client.host if request.client else "unknown"
    if not _allow_resolve(client):
        raise HTTPException(status_code=429, detail="Too many lookups; wait a minute.")
    if not body.url.startswith(("http://", "https://")):
        raise HTTPException(status_code=400, detail="Only http(s) links are supported.")

    try:
        import yt_dlp  # imported lazily so the other endpoints run without it
    except ImportError:  # pragma: no cover
        raise HTTPException(status_code=501, detail="yt-dlp is not installed on this server.")

    options = {
        "quiet": True,
        "skip_download": True,
        "noplaylist": True,
        "socket_timeout": 20,
    }
    try:
        with yt_dlp.YoutubeDL(options) as ydl:
            info = ydl.extract_info(body.url, download=False)
    except yt_dlp.utils.DownloadError as error:
        message = str(error)
        status = 403 if "login" in message.lower() or "private" in message.lower() else 422
        raise HTTPException(status_code=status, detail=message[:300])

    variants = []
    for fmt in info.get("formats") or []:
        url = fmt.get("url")
        if not url or fmt.get("protocol", "").startswith("m3u8"):
            continue
        variants.append(
            {
                "id": fmt.get("format_id"),
                "label": fmt.get("format_note") or (f"{fmt['height']}p" if fmt.get("height") else "Original"),
                "url": url,
                "ext": fmt.get("ext"),
                "heightPx": fmt.get("height"),
                "bytes": fmt.get("filesize") or fmt.get("filesize_approx"),
                "hasAudio": fmt.get("acodec") not in (None, "none"),
                "hasVideo": fmt.get("vcodec") not in (None, "none"),
                "headers": fmt.get("http_headers") or {},
            }
        )

    return JSONResponse(
        {
            "title": info.get("title"),
            "author": info.get("uploader"),
            "thumbnailUrl": info.get("thumbnail"),
            "durationSeconds": info.get("duration"),
            "sourceUrl": info.get("webpage_url") or body.url,
            "variants": variants,
        }
    )
