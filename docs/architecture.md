# Architecture

## Component Diagram

```mermaid
graph TD
    Client["🖥️ Browser / curl\n(localhost only)"]
    Ingress["Nginx Ingress Controller\n(TLS terminated, port 443)\nIP allowlist: 127.0.0.1/32"]
    Gateway["API Gateway\n(FastAPI, port 8000)\n2 replicas + HPA"]
    Catalog["Catalog Service\n(FastAPI, port 8000)\n1 replica"]
    Assistant["Assistant Service\n(FastAPI, port 8000)\n1 replica"]
    LLM["LLM Inference\n(FastAPI + Transformers)\nQwen2.5-0.5B\n1 replica"]
    PV["PersistentVolume\n(model weights ~1 GB)"]
    CronJob["CronJob\n(daily @ 2 AM UTC)\nchecksum + smoke prompts"]
    Prometheus["Prometheus\n(metrics)"]
    Grafana["Grafana\n(dashboards + alerts)"]
    Loki["Loki\n(log aggregation)"]

    Client -->|"HTTPS :443"| Ingress
    Ingress -->|"HTTP :8000"| Gateway
    Gateway -->|"GET /items"| Catalog
    Gateway -->|"POST /answer"| Assistant
    Assistant -->|"GET /items/:id"| Catalog
    Assistant -->|"POST /generate"| LLM
    LLM --- PV
    CronJob -->|"verify checksum"| PV
    CronJob -->|"smoke prompts"| Assistant

    subgraph "monitoring namespace"
        Prometheus
        Grafana
        Loki
    end

    Gateway -.->|"metrics"| Prometheus
    Catalog -.->|"metrics"| Prometheus
    Assistant -.->|"metrics"| Prometheus
    LLM -.->|"metrics"| Prometheus
    Prometheus --- Grafana
    Loki --- Grafana
```

## Data Flow for POST /api/v1/ask

```
curl → Ingress (TLS) → Gateway → Assistant → Catalog (if item_id given)
                                           → LLM → Answer
                                Gateway ← Assistant
curl ← Ingress ← Gateway
```

## Namespaces

| Namespace | Contents |
|-----------|----------|
| `app` | gateway, catalog, assistant, llm, CronJob |
| `ingress-nginx` | Nginx Ingress Controller |
| `monitoring` | Prometheus, Grafana, Loki |

## Security Boundaries

- Only the gateway is reachable from outside the cluster (via Ingress)
- Catalog, assistant, and LLM services are `ClusterIP` — no external exposure
- NetworkPolicies enforce default-deny; only explicit allow rules work
- All pods run as non-root with read-only root filesystems
