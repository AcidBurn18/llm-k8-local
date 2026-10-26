# Model Information

## Model

| Field | Value |
|-------|-------|
| **Name** | Qwen2.5-0.5B-Instruct |
| **Publisher** | Alibaba Cloud (Qwen team) |
| **HuggingFace Repo** | https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct |
| **Parameters** | 0.5 billion |
| **License** | Apache 2.0 |
| **Revision (pinned)** | `main` — TODO: replace with exact commit hash after first download |
| **Weights format** | SafeTensors |

## Why This Model

- Under 1B parameters as required by the spec
- Instruction-tuned — responds well to Q&A prompts without fine-tuning
- Apache 2.0 license allows use in this assessment
- Small enough to load on a MacBook CPU in ~30 seconds

## How Weights Are Delivered

1. The `services/llm/download_model.py` script downloads weights from HuggingFace Hub using `snapshot_download()`.
2. This script runs inside a **Kubernetes Job** (`infra/k8s/model-download-job.yaml`) before the LLM service starts.
3. Weights are stored in a **PersistentVolumeClaim** (`model-weights-pvc`) — they survive pod restarts.
4. The LLM Deployment mounts the same PVC at `/model-weights`.
5. Model weights are **never baked into the container image**.

## Checksum Verification

After the first download, run:

```bash
# Inside the model-downloader pod after job completes
kubectl exec -n app job/model-downloader -- sha256sum /model-weights/model.safetensors
```

Store the output hash as a Kubernetes Secret:

```bash
kubectl create secret generic app-secrets \
  --from-literal=model-checksum=<SHA256_HASH> \
  -n app
```

The checksum is verified:
- After every download (in `download_model.py`)
- Daily by the CronJob (`infra/k8s/cronjob.yaml`)

## HuggingFace as Runtime Dependency

HuggingFace is **only used at model download time** (once, via the Job).  
At runtime the LLM service loads weights **directly from the local PersistentVolume** — no network call to HuggingFace is made during inference. The cluster can operate fully air-gapped after the initial download.
