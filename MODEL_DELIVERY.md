# Model download and delivery

## Model identity

| Field | Value |
|---|---|
| Model | Qwen2.5-0.5B-Instruct |
| Publisher | Qwen team, Alibaba Cloud |
| Hugging Face repository | [Qwen/Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/tree/7ae557604adf67be50417f59c2c2f167def9a775) |
| Pinned revision | `7ae557604adf67be50417f59c2c2f167def9a775` |
| License | Apache-2.0 ([license at pinned revision](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/blob/7ae557604adf67be50417f59c2c2f167def9a775/LICENSE)) |
| Weights file | `model.safetensors` |
| Expected SHA-256 | `fdf756fa7fcbe7404d5c60e26bff1a0c8b8aa1f72ced49e7dd0210fe288fb7fe` |

The model repository, revision, and download logic are set in `services/llm/download_model.py`; the expected hash is injected from Kubernetes Secret `app-secrets`, key `model-checksum`. The checked-in Secret uses demo values only. Never commit production credentials.

## Download job and storage

The weights are kept outside the container image on PVC `model-weights-pvc`, mounted at `/model-weights`. The downloader writes to `/model-weights/data/model.safetensors`. The LLM container loads the local file at runtime and does not call a hosted inference service.

The script `services/llm/download_model.py` downloads the exact pinned revision using `huggingface_hub.snapshot_download`. It hashes an existing file or the downloaded file against `MODEL_CHECKSUM` and exits nonzero on mismatch. The deploy manifest also defines an LLM init container that invokes the same script; it ensures the weights are present before inference starts. A standalone `model-downloader` Job manifest is available at `infra/k8s/model-download-job.yaml` for explicit prewarming/manual use. These are two paths to the same idempotent downloader; avoid running competing downloads at once.

For a cluster where the standalone Job should populate the PVC first:

```bash
kubectl apply -f infra/k8s/namespace.yaml --context kind-dev
kubectl apply -f infra/k8s/secrets/app-secrets.yaml --context kind-dev
kubectl apply -f infra/k8s/llm/pvc.yaml --context kind-dev
kubectl apply -f infra/k8s/model-download-job.yaml --context kind-dev
kubectl wait --for=condition=complete job/model-downloader -n app --context kind-dev --timeout=30m
```

The project release applies Kubernetes manifests recursively and the LLM init container is the normal automatic path. Initial download needs outbound internet access to Hugging Face. The PVC requests 5 GiB. The download Job uses image `llm:v1`, so build and load that image into the Kind cluster first.

## Verify the artifact

Check the stored bytes in a running LLM pod:

```bash
kubectl exec -n app deployment/llm --context kind-dev -- \
  sha256sum /model-weights/data/model.safetensors
```

The output must match the expected SHA-256 above. A checksum mismatch should be treated as a failed download: inspect the Job/init-container logs and PVC contents; do not update the expected hash until the repository revision and artifact have been independently reviewed.

## License and redistribution

The pinned model revision identifies an Apache-2.0 license. Preserve the model's license and attribution with redistributed weights and review applicable terms before broader distribution. This document records the project configuration; verify the linked repository license before external redistribution.
