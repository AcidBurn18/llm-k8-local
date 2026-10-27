# Security and operational decisions

This is a local assessment deployment, not a production security claim. The controls below describe the code and manifests as deployed; the status note records checks that were not demonstrated.

## Decisions in the current deployment

| Area | Current choice | Reason and boundary |
|---|---|---|
| Container images | Four service images use the Python 3.11 slim base pinned by digest: `sha256:b7a9e5f6a93d6d4a31f129bbd4bdee69efccb6ded0fb230d78aafaf37af98377`. | Prevents the base tag from silently resolving to different bytes. The Trivy reports still show HIGH findings and a CRITICAL finding in the LLM image; digest pinning is not a substitute for patching. |
| Application pods | Run as non-root, drop Linux capabilities, use `RuntimeDefault` seccomp, disable ServiceAccount token automount, and set resource requests/limits. Main service containers use a read-only root filesystem. | Limits privilege and writable paths. The LLM init downloader is an exception to read-only root because its configuration allows a writable root filesystem; it still drops capabilities and uses a non-root UID. |
| Namespace and service access | The `app` namespace enforces the restricted Pod Security Standard. Internal services use `ClusterIP`; only the gateway is routed by Ingress. | Keeps catalog, assistant, and model inference inside the cluster network. |
| Network controls | Default-deny and explicit allow NetworkPolicy manifests are applied. The Ingress source allowlist is `127.0.0.1/32,10.244.0.0/16`; NGINX trusts forwarded client IP headers only from the configured single Kind Docker bridge address. | Enables the local allowlist check from the Mac while avoiding trust in an entire Docker bridge for client-IP headers. The assessment smoke test accepted a forwarded localhost address and blocked `203.0.113.10`. NetworkPolicy enforcement itself was not proven with a pod-to-pod negative test. A Kubernetes CNI must support NetworkPolicy enforcement for these objects to have effect; see the [Kubernetes NetworkPolicy documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/). |
| TLS | Local NGINX Ingress terminates HTTPS for `llm-app.local`; the certificate is generated with mkcert. | Local CA trust avoids using a public domain. `tls-secret` is not created by the release target and must be created manually. Smoke tests use `curl -k`, so they verify HTTPS routing but not certificate trust. |
| Secrets | The deployment uses a Kubernetes Secret for the model checksum and demo configuration. | The checked-in key is a placeholder, not a production credential. Kubernetes Secret values are not automatically protected merely because they are base64 encoded. The Terraform configuration also contains a demo Grafana password (`admin123`) |
| Metrics Server | Terraform installs chart version `3.12.2`; its local Kind values include `--kubelet-insecure-tls`. | This made the Metrics API and HPA available in Kind. Disabling kubelet certificate verification is limited to this local demo and should not be carried to a managed cluster. |
| Vulnerability gate | Trivy scans each image and fails on HIGH or CRITICAL by default. `ALLOW_HIGH_VULNS=true` explicitly changes the scanner exit code so a release can continue. | The override does not remove or hide findings. The recorded release used the override; reports are included with this submission. Review and patch findings before promoting these images. |

## Operational trade-offs and known limitations

- `dev` and `prod` have separate Terraform roots, local state, and cluster names. Both call the shared platform module. Only `dev` was deployed; `prod` is isolated but unverified.
- Metrics Server provides HPA resource metrics, while Prometheus scrapes the gateway. A Prometheus alert rule exists, but alert loading, firing, and incident-channel delivery were not verified or configured.
- Application logs are read with `kubectl logs`; there is no central log store. (We can setup Loki)
- The daily model CronJob is defined, but the release does not execute it or gate completion on its result. The one-time model Job and the LLM init container both invoke the downloader; this duplicate path should be consolidated.
- Gateway HPA and PDB manifests exist. `kubectl top` returned live metrics, but a load-driven scale-up and a bad-release rollback were not demonstrated.
- Kind is a single-node local cluster. The PDB is useful for showing configuration but does not provide real node-level availability. CPU inference is slow and resource intensive.
- Image signing, mTLS between services, remote Terraform state, and cloud-managed secrets are not implemented.

