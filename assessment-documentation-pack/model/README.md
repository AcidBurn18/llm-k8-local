# Model delivery

## Model identity

| Field | Value |
|---|---|
| Model | Qwen2.5-0.5B-Instruct |
| Publisher | Qwen team, Alibaba Cloud |
| Hugging Face repository at pinned revision | [Qwen/Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/tree/7ae557604adf67be50417f59c2c2f167def9a775) |
| Revision used by the downloader | `7ae557604adf67be50417f59c2c2f167def9a775` |
| License | Apache-2.0 ([license file at the pinned revision](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/blob/7ae557604adf67be50417f59c2c2f167def9a775/LICENSE)) |
| Weights format | SafeTensors |
| Expected `model.safetensors` SHA-256 | `fdf756fa7fcbe7404d5c60e26bff1a0c8b8aa1f72ced49e7dd0210fe288fb7fe` |

The repository, pinned revision, and expected hash are configured in `services/llm/download_model.py` and `infra/k8s/secrets/app-secrets.yaml`. The Secret manifest contains a model checksum and a demo placeholder API key; it does not contain the model weights. Do not put a real credential in Git.

## How the weights reach the pod

The image contains the downloader and inference code, but not the model weights. The PVC `model-weights-pvc` is mounted at `/model-weights`; the model file is stored at `/model-weights/data/model.safetensors`.

The codebase currently has two ways that invoke the same downloader:

1. `infra/k8s/model-download-job.yaml` defines a `model-downloader` Job to populate and verify the PVC.
2. `infra/k8s/llm/deployment.yaml` has a `model-downloader` init container, which checks or downloads the weights before the LLM container starts.

The CronJob at `infra/k8s/cronjob.yaml` runs daily at 02:00 UTC. It verifies the existing model checksum and sends a smoke prompt to the assistant. The LLM inference container loads from the PVC at runtime; Hugging Face is not called during inference. The release does not automatically wait for or run the daily CronJob. Also, the Job and init-container are redundant paths that should be consolidated so ownership of first download is unambiguous.

## Checksum behavior

`download_model.py` downloads the pinned repository revision when the weights file is absent. If a file already exists, the script hashes it and exits with an error if it does not match `MODEL_CHECKSUM`. After a new download, it performs the same SHA-256 comparison. The expected hash is supplied through the `app-secrets` Kubernetes Secret. In the recorded dev release, the initial model Job completed and the LLM pod became ready.

To inspect the stored weights in a running LLM pod:

```bash
kubectl exec -n app deployment/llm --context kind-dev -- \
  sha256sum /model-weights/data/model.safetensors
```

The resulting hash should match the expected SHA-256 above. This command reads the file; it does not update the Secret. Updating a checksum requires deliberate review of the pinned model revision and the downloaded artifact.

## License and runtime considerations

The model card identifies the model as Apache-2.0 licensed. Keep the model source and license with any redistributed copy, and review the repository's license and usage terms before broader distribution. The local demonstration downloads weights from Hugging Face during setup, so initial deployment needs internet access. Inference uses the local PVC and has no hosted inference API dependency. CPU inference is intentionally small-scale and can be slow on a laptop.
