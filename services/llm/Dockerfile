# LLM Inference Dockerfile
#
# IMPORTANT: torch is installed first using the CPU-only wheel index.
# This prevents pip from downloading the much larger CUDA build (~2 GB saved).
FROM python:3.11-slim@sha256:b7a9e5f6a93d6d4a31f129bbd4bdee69efccb6ded0fb230d78aafaf37af98377

RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup --no-create-home appuser

WORKDIR /app

# Step 1: Install CPU-only PyTorch first (separate layer for better caching)
RUN pip install --no-cache-dir \
    torch==2.3.0 \
    --index-url https://download.pytorch.org/whl/cpu

# Step 2: Install remaining dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Step 3: Copy application code
COPY main.py .
COPY download_model.py .

USER appuser

EXPOSE 8005

# MODEL_PATH is the mount point of the PersistentVolume containing model weights.
# It is also used by download_model.py when run as init-container.
ENV MODEL_PATH=/model-weights

# LLM startup takes ~30s to load weights — give it extra time before liveness checks
HEALTHCHECK --interval=60s --timeout=10s --start-period=60s --retries=5 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8005/healthz')"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8005"]
