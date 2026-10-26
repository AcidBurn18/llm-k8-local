"""
API Gateway Service
-------------------
Single public entry point for the application.
Forwards:
  GET  /api/v1/items        → catalog service
  GET  /api/v1/items/{id}   → catalog service
  POST /api/v1/ask          → assistant service
"""
import json
import os
from collections import defaultdict
from threading import Lock

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import PlainTextResponse

app = FastAPI(title="API Gateway")

CATALOG_URL   = os.getenv("CATALOG_URL",   "http://catalog:8005")
ASSISTANT_URL = os.getenv("ASSISTANT_URL", "http://assistant:8005")
_request_counts = defaultdict(int)
_request_counts_lock = Lock()


@app.middleware("http")
async def count_http_requests(request: Request, call_next):
    response = await call_next(request)
    if request.url.path != "/metrics":
        with _request_counts_lock:
            _request_counts[response.status_code] += 1
    return response


@app.get("/healthz")
def health():
    return {"status": "ok"}


@app.get("/metrics", include_in_schema=False)
def metrics():
    with _request_counts_lock:
        samples = sorted(_request_counts.items())
    lines = [
        "# HELP http_requests_total Total HTTP requests handled by the gateway.",
        "# TYPE http_requests_total counter",
    ]
    lines.extend(
        f'http_requests_total{{status="{status}"}} {count}'
        for status, count in samples
    )
    return PlainTextResponse("\n".join(lines) + "\n", media_type="text/plain; version=0.0.4")


@app.get("/api/v1/items")
def list_items():
    try:
        r = httpx.get(f"{CATALOG_URL}/items", timeout=5)
        return Response(content=r.content, media_type="application/json", status_code=r.status_code)
    except httpx.RequestError as exc:
        return Response(
            content=json.dumps({"detail": f"Catalog service unavailable: {exc}"}),
            media_type="application/json",
            status_code=503,
        )


@app.get("/api/v1/items/{item_id}")
def get_item(item_id: str):
    try:
        r = httpx.get(f"{CATALOG_URL}/items/{item_id}", timeout=5)
        return Response(content=r.content, media_type="application/json", status_code=r.status_code)
    except httpx.RequestError as exc:
        return Response(
            content=json.dumps({"detail": f"Catalog service unavailable: {exc}"}),
            media_type="application/json",
            status_code=503,
        )


@app.post("/api/v1/ask")
async def ask(request: Request):
    body = await request.body()
    try:
        async with httpx.AsyncClient() as client:
            r = await client.post(
                f"{ASSISTANT_URL}/answer",
                content=body,
                headers={"Content-Type": "application/json"},
                timeout=120,
            )
        return Response(content=r.content, media_type="application/json", status_code=r.status_code)
    except httpx.RequestError as exc:
        return Response(
            content=json.dumps({"detail": f"Assistant service unavailable: {exc}"}),
            media_type="application/json",
            status_code=503,
        )
