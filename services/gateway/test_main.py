from unittest.mock import AsyncMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

from services.gateway.main import app


@pytest.fixture
def client():
    return TestClient(app)


def test_healthz(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_metrics_exposes_request_counter(client):
    client.get("/healthz")
    response = client.get("/metrics")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert 'http_requests_total{status="200"}' in response.text


@patch("services.gateway.main.httpx.get")
def test_list_items_success(mock_get, client):
    mock_items = [
        {"id": "item-1", "name": "Laptop Pro", "price": 1299.99, "category": "electronics"},
        {"id": "item-2", "name": "Wireless Mouse", "price": 29.99, "category": "accessories"},
    ]
    mock_get.return_value = httpx.Response(200, json=mock_items)

    response = client.get("/api/v1/items")

    assert response.status_code == 200
    assert response.json() == mock_items
    mock_get.assert_called_once()


@patch("services.gateway.main.httpx.get")
def test_list_items_catalog_down(mock_get, client):
    mock_get.side_effect = httpx.ConnectError("Connection refused")

    response = client.get("/api/v1/items")

    assert response.status_code == 503
    data = response.json()
    assert "Catalog service unavailable" in data["detail"]


@patch("services.gateway.main.httpx.get")
def test_list_items_catalog_timeout(mock_get, client):
    mock_get.side_effect = httpx.TimeoutException("Read timed out")

    response = client.get("/api/v1/items")

    assert response.status_code == 503
    data = response.json()
    assert "Catalog service unavailable" in data["detail"]


@patch("services.gateway.main.httpx.get")
def test_get_item_success(mock_get, client):
    mock_item = {"id": "item-1", "name": "Laptop Pro", "price": 1299.99, "category": "electronics"}
    mock_get.return_value = httpx.Response(200, json=mock_item)

    response = client.get("/api/v1/items/item-1")

    assert response.status_code == 200
    assert response.json() == mock_item
    mock_get.assert_called_once()


@patch("services.gateway.main.httpx.get")
def test_get_item_not_found(mock_get, client):
    mock_get.return_value = httpx.Response(404, json={"detail": "Item 'item-999' not found"})

    response = client.get("/api/v1/items/item-999")

    assert response.status_code == 404
    data = response.json()
    assert "not found" in data["detail"]


@patch("services.gateway.main.httpx.get")
def test_get_item_catalog_down(mock_get, client):
    mock_get.side_effect = httpx.ConnectError("Connection refused")

    response = client.get("/api/v1/items/item-1")

    assert response.status_code == 503
    data = response.json()
    assert "Catalog service unavailable" in data["detail"]


@patch("services.gateway.main.httpx.AsyncClient")
def test_ask_success(mock_async_client_cls, client):
    mock_instance = AsyncMock()
    mock_async_client_cls.return_value.__aenter__.return_value = mock_instance
    mock_async_client_cls.return_value.__aexit__.return_value = None
    mock_instance.post.return_value = httpx.Response(200, json={"answer": "The laptop has 32GB RAM."})

    response = client.post(
        "/api/v1/ask",
        json={"question": "How much RAM?", "item_id": "item-1"},
    )

    assert response.status_code == 200
    assert response.json() == {"answer": "The laptop has 32GB RAM."}
    mock_instance.post.assert_awaited_once()


@patch("services.gateway.main.httpx.AsyncClient")
def test_ask_assistant_down(mock_async_client_cls, client):
    mock_instance = AsyncMock()
    mock_async_client_cls.return_value.__aenter__.return_value = mock_instance
    mock_async_client_cls.return_value.__aexit__.return_value = None
    mock_instance.post.side_effect = httpx.ConnectError("Connection refused")

    response = client.post(
        "/api/v1/ask",
        json={"question": "What is the warranty?"},
    )

    assert response.status_code == 503
    data = response.json()
    assert "Assistant service unavailable" in data["detail"]


@patch("services.gateway.main.httpx.AsyncClient")
def test_ask_assistant_timeout(mock_async_client_cls, client):
    mock_instance = AsyncMock()
    mock_async_client_cls.return_value.__aenter__.return_value = mock_instance
    mock_async_client_cls.return_value.__aexit__.return_value = None
    mock_instance.post.side_effect = httpx.TimeoutException("Request timed out")

    response = client.post(
        "/api/v1/ask",
        json={"question": "What is the warranty?"},
    )

    assert response.status_code == 503
    data = response.json()
    assert "Assistant service unavailable" in data["detail"]


@patch("services.gateway.main.httpx.AsyncClient")
def test_ask_assistant_downstream_error(mock_async_client_cls, client):
    mock_instance = AsyncMock()
    mock_async_client_cls.return_value.__aenter__.return_value = mock_instance
    mock_async_client_cls.return_value.__aexit__.return_value = None
    mock_instance.post.return_value = httpx.Response(502, json={"detail": "LLM service returned an error"})

    response = client.post(
        "/api/v1/ask",
        json={"question": "Hello"},
    )

    assert response.status_code == 502
    data = response.json()
    assert data["detail"] == "LLM service returned an error"
