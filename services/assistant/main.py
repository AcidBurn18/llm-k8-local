"""
Assistant Service
-----------------
Accepts a question and optional item_id.
Flow:
  1. If item_id provided → fetch item details from catalog service
  2. Build a prompt combining item context + the question
  3. Send prompt to LLM inference service
  4. Return the LLM's answer

Endpoints:
  GET  /healthz
  POST /answer   { "question": str, "item_id": str | null }
"""
from __future__ import annotations

import os
from typing import Optional

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Assistant Service")

# Service URLs injected via environment variables (set in K8s manifests)
CATALOG_URL = os.getenv("CATALOG_URL", "http://catalog:8005")
LLM_URL     = os.getenv("LLM_URL",     "http://llm:8005")


class AskRequest(BaseModel):
    question: str
    item_id: Optional[str] = None  # noqa: UP045 — Python 3.9 compatibility


class AskResponse(BaseModel):
    answer: str


@app.get("/healthz")
def health():
    return {"status": "ok"}


@app.post("/answer", response_model=AskResponse)
def answer(req: AskRequest):
    context = ""

    # Step 1: Fetch catalog context if item_id was supplied
    if req.item_id:
        try:
            catalog_resp = httpx.get(
                f"{CATALOG_URL}/items/{req.item_id}", timeout=5
            )
        except httpx.RequestError as e:
            raise HTTPException(status_code=503, detail=f"Catalog service unavailable: {e}")

        if catalog_resp.status_code == 404:
            raise HTTPException(status_code=404, detail=f"Item '{req.item_id}' not found")
        if catalog_resp.status_code != 200:
            raise HTTPException(status_code=502, detail="Unexpected response from catalog service")

        item = catalog_resp.json()
        context = (
            f"Product name: {item['name']}. "
            f"Description: {item['description']}. "
            f"Price: ${item['price']}."
        )

    # Step 2: Build prompt
    if context:
        prompt = f"You are a helpful product assistant.\n\nProduct info: {context}\n\nUser question: {req.question}\n\nAnswer:"
    else:
        prompt = f"You are a helpful assistant.\n\nUser question: {req.question}\n\nAnswer:"

    # Step 3: Call LLM inference service
    try:
        llm_resp = httpx.post(
            f"{LLM_URL}/generate",
            json={"prompt": prompt, "max_new_tokens": 64},
            timeout=120,  # LLM can be slow on CPU
        )
    except httpx.RequestError as e:
        raise HTTPException(status_code=503, detail=f"LLM service unavailable: {e}")

    if llm_resp.status_code != 200:
        raise HTTPException(status_code=502, detail="LLM service returned an error")

    return AskResponse(answer=llm_resp.json()["text"])
