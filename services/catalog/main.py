"""
Catalog Service
---------------
Returns a seeded in-memory list of items.
No database required — static data is sufficient per spec.

Endpoints:
  GET /healthz
  GET /items
  GET /items/{item_id}
"""
from fastapi import FastAPI, HTTPException

app = FastAPI(title="Catalog Service")

# Seeded in-memory catalog — no database needed
ITEMS = [
    {
        "id": "item-1",
        "name": "Laptop Pro",
        "description": "A high-performance laptop with 32GB RAM and 1TB SSD.",
        "price": 1299.99,
        "category": "electronics",
    },
    {
        "id": "item-2",
        "name": "Wireless Mouse",
        "description": "Ergonomic wireless mouse with 12-month battery life.",
        "price": 29.99,
        "category": "accessories",
    },
    {
        "id": "item-3",
        "name": "USB-C Hub",
        "description": "7-in-1 USB-C hub with HDMI, USB 3.0, and SD card reader.",
        "price": 49.99,
        "category": "accessories",
    },
    {
        "id": "item-4",
        "name": "Mechanical Keyboard",
        "description": "Compact TKL mechanical keyboard with Cherry MX switches.",
        "price": 89.99,
        "category": "accessories",
    },
]

# Build a dict for O(1) lookups by id
_ITEMS_BY_ID = {item["id"]: item for item in ITEMS}


@app.get("/healthz")
def health():
    return {"status": "ok"}


@app.get("/items")
def list_items():
    return ITEMS


@app.get("/items/{item_id}")
def get_item(item_id: str):
    item = _ITEMS_BY_ID.get(item_id)
    if item is None:
        raise HTTPException(status_code=404, detail=f"Item '{item_id}' not found")
    return item
