# Design decisions and trade-offs

I kept the implementation small enough to run on a laptop and made the service boundaries visible. The main trade-off is that this is a reviewable local demonstration, not a production-ready platform. The [architecture](architecture.md), [security notes](security-decisions.md), and [runbook](runbook.md) describe the implementation details.

## Four small services instead of one application

The gateway is the only service reached through Ingress. It forwards catalog reads to the catalog service and ask requests to the assistant. The assistant can fetch item context and calls the internal LLM service. This makes the request path and the trust boundary easy to follow. Catalog data is a small in-memory list, so it resets with the process and does not need a database for this assessment.

## CPU model and local weights

I used Qwen2.5-0.5B-Instruct because it is under one billion parameters and can run on CPU. The revision and expected SHA-256 are pinned and documented in [model delivery](../model/README.md). Weights are kept on a PVC outside the application image. This avoids rebuilding and rescanning a large image just to change application code.

There are currently two downloader paths: a Kubernetes Job and the LLM Deployment init container. Both call the same script and both can access the PVC. The recorded dev release completed, but having duplicate owners adds unnecessary operational ambiguity. I would choose one path and make deployment ordering explicit before production use.

## Local infrastructure and environment separation

Kind stands in for a managed Kubernetes cluster, and Terraform creates the cluster plus Helm-installed ingress, monitoring, and Metrics Server components. The Makefile shows a Terraform plan and asks for explicit approval before apply. The user must type `apply`, then approve Terraform's own prompt. This makes the destructive infrastructure step visible during a local release.


## Build, scan, and release

`make check` runs Ruff, the Python unit tests, image builds, Syft SBOM generation, and Trivy scans. `make release` adds Terraform, local image loading, and Kubernetes deployment. HIGH and CRITICAL findings fail the scan unless the operator explicitly passes `ALLOW_HIGH_VULNS=true`; the override preserves the scan reports but allows the release to proceed. The latest assessment release used that override, so the image findings remain open work.

The Python base image is pinned by digest. The images are locally tagged `v1` and loaded into Kind with `imagePullPolicy: Never`, which keeps the demo independent of a hosted registry. Image signing and registry promotion are not implemented.

## Ingress and client IP checks

NGINX terminates TLS for the local hostname and forwards traffic to the gateway. The host ports bind to localhost. The allowlist accepts localhost and the cluster pod CIDR; NGINX trusts forwarded client IP information only from the configured single Kind bridge address. That lets the Mac smoke test send an allowed localhost address and a disallowed TEST-NET address without trusting all Docker bridge addresses. `make release` does not create the mkcert-backed `tls-secret`; the runbook includes the manual step. Smoke tests use `curl -k`, which does not prove browser trust.

## Scaling, availability, and operations

Metrics Server is installed through Terraform because Kubernetes HPA needs the resource metrics API. The gateway HPA is configured and `kubectl top` returned node and pod metrics. A load-driven scale-up has not been shown. I kept the LLM at one replica because each CPU instance loads the model into memory; production scaling would need a suitable model-serving runtime and enough CPU/GPU capacity.

The project includes a gateway PDB, readiness-gated deployments, a daily model checksum/smoke CronJob, Prometheus/Grafana, and alert rules. The CronJob was not added as a release gate or run during the recorded verification. Alert firing and routing to an incident channel were not verified. Logs remain available through `kubectl logs`; there is no centralized log backend.

## What I would improve next

1. Give each environment independent Terraform state and verify a second environment without risking the dev state.
2. Consolidate model download ownership and make model preparation a clear release dependency.
3. Add CronJob execution and result checks to `make verify` or the release flow.
4. Add a central log collector, test Prometheus rule loading/firing, and configure an incident receiver.
5. Demonstrate a load-driven HPA scale-up, policy enforcement with a blocked pod-to-pod test, and rollback of a deliberately bad app revision.
6. Remove demo credentials from Terraform values and source credentials from a local secret mechanism or managed secret store.
7. Patch the image vulnerabilities, add image signing, and publish immutable digests if the deployment moves beyond Kind.
