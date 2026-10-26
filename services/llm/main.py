"""
LLM Inference Service
---------------------
Loads model weights from a PersistentVolume (mounted at MODEL_PATH).
Runs CPU-only inference using Hugging Face transformers.

Model: Qwen/Qwen2.5-0.5B-Instruct
  - Parameters : 0.5B
  - License    : Apache 2.0
  - Source     : https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct
  - Revision   : see model/README.md for pinned commit hash

Endpoints:
  GET  /healthz
  POST /generate  { "prompt": str, "max_new_tokens": int }
"""
import os

import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from transformers import AutoModelForCausalLM, AutoTokenizer

app = FastAPI(title="LLM Inference Service")

# MODEL_PATH is the directory where download_model.py placed the weights.
# In Kubernetes this directory is mounted from a PersistentVolumeClaim.
MODEL_PATH = os.getenv("MODEL_PATH", "/model-weights")

# ---------------------------------------------------------------------------
# Load model once at startup — this takes ~30s on CPU, hence the long
# initialDelaySeconds in the K8s liveness probe.
# ---------------------------------------------------------------------------
print(f"[startup] Loading tokenizer from {MODEL_PATH} ...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)

print(f"[startup] Loading model from {MODEL_PATH} ...")
model = AutoModelForCausalLM.from_pretrained(
    MODEL_PATH,
    torch_dtype=torch.float32,   # float32 for CPU; bfloat16 would need AVX512
    device_map="cpu",
)
model.eval()
print("[startup] Model ready.")


class GenerateRequest(BaseModel):
    prompt: str
    max_new_tokens: int = 200


class GenerateResponse(BaseModel):
    text: str


@app.get("/healthz")
def health():
    # If we got here, the model loaded successfully at startup
    return {"status": "ok"}


@app.post("/generate", response_model=GenerateResponse)
def generate(req: GenerateRequest):
    if not req.prompt.strip():
        raise HTTPException(status_code=400, detail="prompt cannot be empty")

    inputs = tokenizer(req.prompt, return_tensors="pt")

    with torch.no_grad():
        output_ids = model.generate(
            **inputs,
            max_new_tokens=req.max_new_tokens,
            do_sample=False,        # Greedy decode — deterministic, good for demo
            pad_token_id=tokenizer.eos_token_id,
        )

    # Decode only the newly generated tokens (not the input prompt)
    new_token_ids = output_ids[0][inputs["input_ids"].shape[1]:]
    text = tokenizer.decode(new_token_ids, skip_special_tokens=True).strip()

    return GenerateResponse(text=text)
