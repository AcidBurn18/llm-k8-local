import pytest
from fastapi.testclient import TestClient

from services.catalog.main import app


@pytest.fixture
def client():
    return TestClient(app)


def test_healthz(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_list_items(client):
    response = client.get("/items")
    assert response.status_code == 200
    items = response.json()
    assert isinstance(items, list)
    assert len(items) == 4
    item_ids = [item["id"] for item in items]
    assert item_ids == ["item-1", "item-2", "item-3", "item-4"]


def test_get_item_success(client):
    response = client.get("/items/item-1")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == "item-1"
    assert data["name"] == "Laptop Pro"
    assert data["price"] == 1299.99
    assert data["category"] == "electronics"


def test_get_item_mouse(client):
    response = client.get("/items/item-2")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == "item-2"
    assert data["name"] == "Wireless Mouse"
    assert data["price"] == 29.99
    assert data["category"] == "accessories"


def test_get_item_not_found(client):
    response = client.get("/items/non-existent-item")
    assert response.status_code == 404
    data = response.json()
    assert data["detail"] == "Item 'non-existent-item' not found"
