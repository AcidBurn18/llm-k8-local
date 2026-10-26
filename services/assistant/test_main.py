from unittest.mock import patch

import httpx
import pytest
from fastapi.testclient import TestClient

from services.assistant.main import app


@pytest.fixture
def client():
    return TestClient(app)


def test_healthz(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@patch("services.assistant.main.httpx.get")
@patch("services.assistant.main.httpx.post")
def test_answer_without_item_id(mock_llm_post, mock_catalog_get, client):
    mock_llm_post.return_value = httpx.Response(200, json={"text": "Hello! How can I help you today?"})

    response = client.post("/answer", json={"question": "Hello!"})

    assert response.status_code == 200
    assert response.json() == {"answer": "Hello! How can I help you today?"}
    mock_catalog_get.assert_not_called()
    mock_llm_post.assert_called_once()
    payload = mock_llm_post.call_args[1]["json"]
    assert "User question: Hello!" in payload["prompt"]
    assert payload["max_new_tokens"] == 64


@patch("services.assistant.main.httpx.get")
@patch("services.assistant.main.httpx.post")
def test_answer_with_item_id(mock_llm_post, mock_catalog_get, client):
    mock_catalog_get.return_value = httpx.Response(
        200,
        json={
            "id": "item-1",
            "name": "Laptop Pro",
            "description": "High-performance laptop",
            "price": 1299.99,
            "category": "electronics",
        },
    )
    mock_llm_post.return_value = httpx.Response(
        200, json={"text": "The Laptop Pro is priced at $1299.99."}
    )

    response = client.post(
        "/answer",
        json={"question": "How much is the laptop?", "item_id": "item-1"},
    )

    assert response.status_code == 200
    assert response.json() == {"answer": "The Laptop Pro is priced at $1299.99."}
    mock_catalog_get.assert_called_once_with("http://catalog:8005/items/item-1", timeout=5)
    mock_llm_post.assert_called_once()
    payload = mock_llm_post.call_args[1]["json"]
    assert "Product info: Product name: Laptop Pro." in payload["prompt"]
    assert "User question: How much is the laptop?" in payload["prompt"]


@patch("services.assistant.main.httpx.get")
def test_answer_catalog_unavailable(mock_catalog_get, client):
    mock_catalog_get.side_effect = httpx.ConnectError("Connection refused")

    response = client.post(
        "/answer",
        json={"question": "Specs please", "item_id": "item-1"},
    )

    assert response.status_code == 503
    data = response.json()
    assert "Catalog service unavailable" in data["detail"]


@patch("services.assistant.main.httpx.get")
def test_answer_catalog_timeout(mock_catalog_get, client):
    mock_catalog_get.side_effect = httpx.TimeoutException("Read timed out")

    response = client.post(
        "/answer",
        json={"question": "Specs please", "item_id": "item-1"},
    )

    assert response.status_code == 503
    data = response.json()
    assert "Catalog service unavailable" in data["detail"]


@patch("services.assistant.main.httpx.get")
def test_answer_catalog_unexpected_status(mock_catalog_get, client):
    mock_catalog_get.return_value = httpx.Response(500, json={"error": "Database error"})

    response = client.post(
        "/answer",
        json={"question": "Specs please", "item_id": "item-1"},
    )

    assert response.status_code == 502
    data = response.json()
    assert "Unexpected response from catalog service" in data["detail"]


@patch("services.assistant.main.httpx.get")
def test_answer_item_not_found(mock_catalog_get, client):
    mock_catalog_get.return_value = httpx.Response(404, json={"detail": "Item 'item-999' not found"})

    response = client.post(
        "/answer",
        json={"question": "Specs please", "item_id": "item-999"},
    )

    assert response.status_code == 404
    data = response.json()
    assert data["detail"] == "Item 'item-999' not found"


@patch("services.assistant.main.httpx.post")
def test_answer_llm_unavailable(mock_llm_post, client):
    mock_llm_post.side_effect = httpx.ConnectError("Connection refused")

    response = client.post("/answer", json={"question": "Hello"})

    assert response.status_code == 503
    data = response.json()
    assert "LLM service unavailable" in data["detail"]


@patch("services.assistant.main.httpx.post")
def test_answer_llm_timeout(mock_llm_post, client):
    mock_llm_post.side_effect = httpx.TimeoutException("Read timed out")

    response = client.post("/answer", json={"question": "Hello"})

    assert response.status_code == 503
    data = response.json()
    assert "LLM service unavailable" in data["detail"]


@patch("services.assistant.main.httpx.post")
def test_answer_llm_error_status(mock_llm_post, client):
    mock_llm_post.return_value = httpx.Response(500, json={"error": "Inference failure"})

    response = client.post("/answer", json={"question": "Hello"})

    assert response.status_code == 502
    data = response.json()
    assert "LLM service returned an error" in data["detail"]
