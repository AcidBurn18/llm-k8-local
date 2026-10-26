"""
Model Download Script
---------------------
Downloads Qwen2.5-0.5B-Instruct weights from Hugging Face Hub
into the directory specified by MODEL_PATH (default: /model-weights).

This script is run by:
  - The Kubernetes model-download Job (one-time, before LLM pods start)
  - The daily CronJob (for checksum re-verification)

It is IDEMPOTENT: if weights already exist and the checksum matches, it exits 0
without re-downloading.

Model details:
  Repo     : Qwen/Qwen2.5-0.5B-Instruct
  License  : Apache 2.0
  Revision : see MODEL_REVISION below — pin to a specific commit hash
"""
import hashlib
import os
import sys

from huggingface_hub import snapshot_download

# ── Configuration ──────────────────────────────────────────────────────────────

MODEL_REPO = "Qwen/Qwen2.5-0.5B-Instruct"

# TODO: After first download, run:
#   sha256sum /model-weights/model.safetensors
# and paste the output hash here AND in the K8s model-secrets Secret.
# Also pin MODEL_REVISION to the exact git commit shown on the HuggingFace page.
MODEL_REVISION = "e36e5015279de6f34684e01e917547ba2e74b5d6"  # Pinned commit hash
EXPECTED_SHA256 = os.getenv("MODEL_CHECKSUM", "")   # Set via K8s Secret

DEST_DIR = os.getenv("MODEL_PATH", "/model-weights")
WEIGHTS_FILE = os.path.join(DEST_DIR, "model.safetensors")


# ── Helpers ────────────────────────────────────────────────────────────────────

def sha256_of_file(path: str) -> str:
    """Stream-hash a file to avoid loading it all into RAM."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def weights_exist() -> bool:
    return os.path.isfile(WEIGHTS_FILE)


# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    os.makedirs(DEST_DIR, exist_ok=True)

    # If weights already present, just verify checksum and exit
    if weights_exist():
        print(f"[downloader] Weights already present at {WEIGHTS_FILE}.")
        if EXPECTED_SHA256:
            actual = sha256_of_file(WEIGHTS_FILE)
            if actual != EXPECTED_SHA256:
                print("[downloader] ERROR: Checksum mismatch!")
                print(f"  Expected : {EXPECTED_SHA256}")
                print(f"  Actual   : {actual}")
                sys.exit(1)
            print(f"[downloader] Checksum OK: {actual}")
        else:
            print("[downloader] WARNING: No MODEL_CHECKSUM set — skipping verification.")
        return

    # Download weights
    print(f"[downloader] Downloading {MODEL_REPO} @ {MODEL_REVISION} to {DEST_DIR} ...")
    snapshot_download(
        repo_id=MODEL_REPO,
        revision=MODEL_REVISION,
        local_dir=DEST_DIR,
        cache_dir=os.getenv("HF_HOME", "/tmp/hf"),
        force_download=True,
        ignore_patterns=["*.md", "*.gitattributes", "*.txt"],
    )
    print("[downloader] Download complete.")

    # Verify checksum after download
    if EXPECTED_SHA256:
        actual = sha256_of_file(WEIGHTS_FILE)
        if actual != EXPECTED_SHA256:
            print("[downloader] ERROR: Post-download checksum mismatch! Aborting.")
            print(f"  Expected : {EXPECTED_SHA256}")
            print(f"  Actual   : {actual}")
            sys.exit(1)
        print(f"[downloader] Post-download checksum OK: {actual}")
    else:
        if os.path.isfile(WEIGHTS_FILE):
            actual = sha256_of_file(WEIGHTS_FILE)
            print(f"[downloader] Checksum (for your records): {actual}")
            print("[downloader] TIP: Set this as MODEL_CHECKSUM in your K8s Secret.")


if __name__ == "__main__":
    main()
