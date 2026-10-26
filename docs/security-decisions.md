# Security & Operational Decisions

## Security Decisions

### Non-root containers
All containers run as a dedicated system user (`appuser`, UID 1000).  
**Why**: If a container is compromised, the attacker cannot write to the host filesystem or escalate privileges.

### Read-only root filesystem
Applied to all service containers. A writable `emptyDir` volume is mounted at `/tmp` for uvicorn's temp files.  
**Why**: Prevents an attacker from modifying application binaries at runtime.

### Drop all Linux capabilities
`capabilities: drop: [ALL]` removes all capabilities (e.g., `NET_BIND_SERVICE`, `SYS_PTRACE`) from containers.  
**Why**: Principle of least privilege — the services don't need any elevated kernel permissions.

### seccomp: RuntimeDefault
Enables the container runtime's default seccomp profile which blocks ~100 dangerous syscalls.  
**Why**: Reduces the kernel attack surface without writing a custom profile (reasonable for a demo).

### NetworkPolicy: default-deny
The `default-deny-all` policy blocks all traffic in the `app` namespace.  
Explicit allow rules are created for each service pair that actually needs to communicate.  
**Why**: Zero-trust networking — services can only talk to exactly who they need to.

### Pod Security Standard: restricted
Applied via namespace label (`pod-security.kubernetes.io/enforce: restricted`).  
Kubernetes itself will reject any pod spec that doesn't meet the `restricted` profile at admission time.  
**Why**: Defense in depth — even if a manifest is misconfigured, the API server rejects it.

### Secrets management
- All sensitive values go into K8s Secrets, never into source code or Dockerfiles.
- `automountServiceAccountToken: false` on all ServiceAccounts — no K8s API token is mounted into pods unless explicitly needed.
- In production: would use External Secrets Operator to source from GCP Secret Manager / AWS Secrets Manager / Vault.

### TLS on Ingress
Self-signed certificate generated with `mkcert` (trusted by the local OS via mkcert's CA).  
**Why**: Encrypts traffic from the client to the Nginx Ingress. In production, use cert-manager + Let's Encrypt.

### IP allowlist on Ingress
`nginx.ingress.kubernetes.io/whitelist-source-range: "127.0.0.1/32"` restricts inbound access to localhost only.  
**Why**: Demonstrates restricted inbound access as required. In production this would be a corporate IP range.

### Base image pinning
Dockerfiles use `FROM python:3.11-slim` (should be pinned to digest in production).  
**Why**: Prevents supply-chain attacks where an upstream image tag is silently changed.

## Operational Decisions

### HPA on gateway only
The gateway is the only stateless service that benefits from horizontal scaling.  
Catalog is trivially fast (in-memory). Assistant is IO-bound (waits for LLM). LLM is CPU-bound and stateful.  
**Why**: HPA on LLM would create cold-start problems (each replica loads the model independently).

### Single replica for LLM
The LLM needs ~2 GB RAM to load the model. Multiple replicas would exhaust a laptop's RAM.  
**Why**: Practical trade-off for a local demo. In production you'd use GPU nodes with model serving frameworks (vLLM).

### Rolling update with maxUnavailable=0
Ensures zero-downtime rollouts. A new pod must be ready before the old one is removed.  
**Trade-off**: Slightly slower rollouts, uses more resources momentarily.

### CronJob for model integrity
A daily CronJob re-verifies the model checksum and runs smoke prompts.  
**Why**: Detects filesystem corruption or accidental model overwrite without manual intervention.

## Known Limitations

| Limitation | Production Fix |
|------------|---------------|
| Self-signed TLS | cert-manager + Let's Encrypt / ACM |
| No image signing (documented) | `cosign` in CI/CD pipeline |
| K8s Secrets are base64, not encrypted | Enable etcd encryption at rest |
| No mTLS between services | Istio / Linkerd service mesh |
| Single-node Kind — PDB is demonstrative | Multi-node cluster |
| LLM inference is slow on CPU (~10–30s) | GPU nodes, vLLM, llama.cpp |
